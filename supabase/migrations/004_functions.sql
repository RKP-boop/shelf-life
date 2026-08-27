-- ShelfLife MVP — query functions
--
-- Both are `security invoker`, so they execute as the calling user and RLS
-- applies. `security definer` would let one RPC return every user's inventory.

-- ==========================================================================
-- match_recipes — FR-07
--
-- Implements spec §5.2 exactly:
--   score = 0.6 * (have / total) + 0.3 * urgency + 0.1 * speed
--   urgency = max(0, 1 - daysToExpiry / 3)   over matched held items
--   speed   = max(0, 1 - prepMinutes / 60)
--
-- Weights follow FR-07's stated priority: availability, then expiry urgency,
-- then preparation time.
--
-- Returns missing_names and urgent_names, not just a score. Two UI rules
-- depend on it:
--   * the score is NEVER rendered -- screens show "7 of 9 ingredients"
--   * screen 33 must name which urgent items a recipe uses:
--     "Uses your spinach and paneer, both best used today."
-- ==========================================================================

create or replace function match_recipes(p_limit int default 20)
returns table (
  recipe_id      uuid,
  name           text,
  prep_minutes   int,
  image_key      text,
  total_required int,
  have_count     int,
  have_names     text[],
  missing_names  text[],
  urgent_names   text[],
  score          numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with held as (
    -- one row per canonical ingredient the caller currently holds,
    -- carrying the soonest expiry among duplicates
    select ingredient_id, min(expiry_date) as soonest
    from inventory_items
    where user_id = auth.uid()
      and status = 'active'
      and ingredient_id is not null
    group by ingredient_id
  ),
  required as (
    -- optional ingredients never count toward have/total
    select recipe_id, ingredient_id
    from recipe_ingredients
    where not optional
  ),
  joined as (
    select
      r.id, r.name, r.prep_minutes, r.image_key,
      req.ingredient_id,
      ing.canonical_name,
      held.soonest,
      case
        when held.soonest is null then null
        else greatest(0, least(1, 1 - (held.soonest - current_date)::numeric / 3))
      end as item_urgency
    from recipes r
    join required req  on req.recipe_id = r.id
    join ingredients ing on ing.id = req.ingredient_id
    left join held      on held.ingredient_id = req.ingredient_id
  ),
  agg as (
    select
      id, name, prep_minutes, image_key,
      count(*)::int                                                    as total_required,
      count(soonest)::int                                              as have_count,
      coalesce(array_agg(canonical_name order by canonical_name)
               filter (where soonest is not null), '{}')               as have_names,
      coalesce(array_agg(canonical_name order by canonical_name)
               filter (where soonest is null), '{}')                   as missing_names,
      -- "best used today" means expiring today or already due
      coalesce(array_agg(canonical_name order by canonical_name)
               filter (where soonest is not null and soonest <= current_date), '{}') as urgent_names,
      coalesce(max(item_urgency), 0)                                   as urgency
    from joined
    group by id, name, prep_minutes, image_key
  )
  select
    id, name, prep_minutes, image_key,
    total_required, have_count, have_names, missing_names, urgent_names,
    round(
        0.6 * (have_count::numeric / greatest(total_required, 1))
      + 0.3 * urgency
      + 0.1 * greatest(0, 1 - prep_minutes::numeric / 60)
    , 4) as score
  from agg
  -- a recipe with nothing available is noise on the Recipes tab
  where have_count > 0
  order by score desc, have_count desc, prep_minutes asc
  limit p_limit;
$$;

comment on function match_recipes is
  'FR-07 ranking. Never render score in the UI; show "N of M ingredients" and name the urgent items (spec 5.2).';


-- ==========================================================================
-- kitchen_stats — FR-09
--
-- Every figure the dashboard and statistics screens need, in one round trip,
-- to hold the <2 s dashboard target.
--
-- Principle 3 governs the OUTPUT, not the storage: `removed` events are
-- recorded because "% used in time" needs a denominator, but nothing here
-- returns a waste count.
-- ==========================================================================

create or replace function kitchen_stats()
returns json
language sql
stable
security invoker
set search_path = public
as $$
  with active as (
    select count(*) as n,
           count(*) filter (where expiry_date <= current_date + 3) as expiring_soon,
           count(*) filter (where expiry_date <= current_date)     as due_today
    from inventory_items
    where user_id = auth.uid() and status = 'active'
  ),
  month_events as (
    select
      count(*) filter (where kind = 'used')                        as used,
      coalesce(sum(est_value_inr) filter (where kind = 'used'), 0) as value_rescued
    from consumption_events
    where user_id = auth.uid()
      and occurred_at >= date_trunc('month', now())
  ),
  -- % used before expiry, all time. Counts an event as "in time" when the item
  -- was used on or before its expiry date.
  in_time as (
    select
      count(*) as total,
      count(*) filter (
        where kind = 'used' and (expiry_date is null or occurred_at::date <= expiry_date)
      ) as good
    from consumption_events
    where user_id = auth.uid()
  ),
  -- Current streak: consecutive days, ending today or yesterday, on which at
  -- least one item was used. Yesterday is allowed so the streak does not
  -- appear broken before the user has cooked today.
  used_days as (
    select distinct occurred_at::date as d
    from consumption_events
    where user_id = auth.uid() and kind = 'used'
  ),
  grouped as (
    -- gaps-and-islands: for DESC dates the island key is d + rn, not d - rn.
    -- With a minus sign every consecutive day forms its own group and the
    -- streak always returns 1.
    select d, d + (row_number() over (order by d desc) * interval '1 day')::interval as grp
    from used_days
  ),
  streak as (
    select count(*) as len, max(d) as latest
    from grouped
    group by grp
    order by max(d) desc
    limit 1
  )
  select json_build_object(
    'active_items',      (select n             from active),
    'expiring_soon',     (select expiring_soon from active),
    'due_today',         (select due_today     from active),
    'meals_rescued',     (select used          from month_events),
    'value_rescued_inr', (select round(value_rescued, 0) from month_events),
    'current_streak',    coalesce((
                            select len from streak
                            where latest >= current_date - 1
                         ), 0),
    'pct_used_in_time',  case
                            when coalesce((select total from in_time), 0) = 0 then null
                            else round(
                              100.0 * (select good from in_time) / (select total from in_time), 0)
                         end
  );
$$;

comment on function kitchen_stats is
  'FR-09 dashboard figures in one round trip. value_rescued_inr is an ESTIMATE derived from ingredients.est_price_inr and must be labelled as such in the UI.';
