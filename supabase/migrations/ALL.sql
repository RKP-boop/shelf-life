-- ShelfLife MVP -- complete backend, all migrations concatenated in order.
-- Generated: do not edit. Source files are in supabase/migrations/.
-- Safe to re-run: every seed insert is `on conflict do nothing`.


-- ==========================================================================
-- 001_schema.sql
-- ==========================================================================

-- ShelfLife MVP — schema
-- Ten tables. PRD §5.5 specifies five; the five additions are justified in
-- docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md §4.
--
-- Apply order matters: FKs require ingredients and recipes to exist first.

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------- enums
-- Values mirror the UI exactly, so no translation layer is needed.

create type storage_location as enum ('fridge', 'freezer', 'pantry', 'counter');

create type food_category as enum ('dairy', 'fruits', 'vegetables', 'pantry', 'frozen', 'other');

-- Spec §5.1 precedence: user override beats a printed date beats a per-item
-- estimate beats a category fallback. BR-01: the user's value always wins.
create type expiry_source as enum ('user', 'printed', 'estimated', 'category_default');

create type item_status as enum ('active', 'consumed');

-- 'used'    -> counts as rescued
-- 'removed' -> does not (delete-confirm: "this won't count as rescued")
-- Both are recorded because FR-09's "% used before expiry" needs the denominator.
-- No view or function ever returns a "wasted" figure (Principle 3).
create type consumption_kind as enum ('used', 'removed');

-- Screen 39 renders this enum directly as the row caption:
-- 'recipe'  -> "Added from Palak Paneer"
-- 'ran_out' -> "You've run out"
create type shopping_source as enum ('manual', 'ran_out', 'recipe');

create type notification_level as enum ('three_day', 'one_day', 'same_day');

-- ---------------------------------------------------------------- profiles
create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at  timestamptz not null default now()
);

comment on table profiles is
  'Mirrors auth.users. No household_id: sharing is out of MVP scope (D6, BR-05).';

-- Create the profile row on signup so the client never has to.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------- ingredients
-- The keystone table (spec §3). Three input paths — OCR text, typed names and
-- recipe references — all resolve to a row here before anything else works.
create table ingredients (
  id                uuid primary key default gen_random_uuid(),
  canonical_name    text not null unique,
  category          food_category not null,
  default_unit      text not null,
  -- must name a component that exists in the Figma asset library
  glyph_key         text not null,
  -- per-storage shelf life; null means "not sensibly stored this way"
  shelf_life_fridge_days  int,
  shelf_life_freezer_days int,
  shelf_life_pantry_days  int,
  shelf_life_counter_days int,
  -- rough Indian market rate, used only for the "estimated value" stats.
  -- ALWAYS surfaced as an estimate in the UI, never as a measured figure.
  est_price_inr     numeric(10, 2),
  created_at        timestamptz not null default now()
);

comment on column ingredients.glyph_key is
  'Figma asset component name without the Produce/ prefix, or a category fallback.';

-- ---------------------------------------------------------- ingredient_aliases
-- palak -> spinach, toned milk -> milk, amul taaza -> milk
create table ingredient_aliases (
  id            uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references ingredients (id) on delete cascade,
  alias         text not null unique,
  created_at    timestamptz not null default now()
);

comment on column ingredient_aliases.alias is
  'Globally unique: one alias resolves to exactly one ingredient, so parsing is deterministic.';

-- ---------------------------------------------------------------- products
-- Barcode cache. D1: no external API — this ships seeded and grows every time a
-- user names an unknown barcode, which is what screen 22 promises
-- ("we''ll remember it for next time").
create table products (
  barcode        text primary key,
  product_name   text not null,
  brand          text,
  ingredient_id  uuid references ingredients (id) on delete set null,
  category       food_category,
  pack_size      text,
  -- who contributed it; null for seeded rows
  contributed_by uuid references auth.users (id) on delete set null,
  -- true for seeded rows, false for user contributions
  verified       boolean not null default false,
  created_at     timestamptz not null default now()
);

comment on table products is
  'Shared, client-writable catalogue (D1). Insert-only by policy: a catalogue any user could edit or delete is a data-integrity risk, and D1 only requires growth.';

-- ---------------------------------------------------------------- recipes
create table recipes (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,
  prep_minutes  int not null check (prep_minutes > 0),
  servings      int not null default 4 check (servings > 0),
  difficulty    text not null default 'Easy',
  category      text,
  -- display-only and never queried, so JSON is correct here (D5)
  method_steps  jsonb not null default '[]'::jsonb,
  -- Figma Dish/* component name
  image_key     text,
  created_at    timestamptz not null default now()
);

-- ------------------------------------------------------- recipe_ingredients
-- Normalised, departing from PRD §5.5's JSON blob (D5): FR-07 ranks by
-- ingredient availability, which is a join against inventory. A blob would
-- force a full scan plus client-side parsing on every Recipes tab open.
create table recipe_ingredients (
  recipe_id     uuid not null references recipes (id) on delete cascade,
  ingredient_id uuid not null references ingredients (id) on delete cascade,
  quantity      numeric(10, 2),
  unit          text,
  optional      boolean not null default false,
  primary key (recipe_id, ingredient_id)
);

comment on column recipe_ingredients.optional is
  'Optional ingredients are excluded from the have/total match count.';

-- ------------------------------------------------------------ inventory_items
create table inventory_items (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  -- null when the user typed something not in the catalogue; the board allows
  -- free text ("Name not in the catalogue -> free text accepted and saved")
  ingredient_id uuid references ingredients (id) on delete set null,
  -- what the user sees. May differ from canonical_name: "Amul Taaza" not "milk".
  product_name  text not null,
  category      food_category not null,
  quantity      numeric(10, 2) not null default 1 check (quantity > 0),
  unit          text not null,
  storage       storage_location not null,
  purchase_date date not null,
  expiry_date   date not null,
  expiry_source expiry_source not null,
  -- plain-English justification, e.g. "You bought this five days ago, and fresh
  -- greens keep about six." Principle 4 requires the estimate to explain itself,
  -- so the explanation is stored rather than reconstructed in the UI.
  expiry_reason text,
  barcode       text,
  status        item_status not null default 'active',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table inventory_items is
  'Hard delete only (D7 / BR-02): no soft-delete column and no restore path.';

create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Only this table needs it: it is the sole table the offline sync queue
-- reconciles by timestamp (PRD 5.8, last-write-wins with both timestamps kept).
create trigger inventory_items_touch
  before update on inventory_items
  for each row execute function touch_updated_at();

-- --------------------------------------------------------- consumption_events
-- Required by FR-09. "Money saved", "meals rescued", "current streak" and
-- screen 43's "94% used in time" are not computable from a mutable inventory
-- row, because the row is gone once the item is consumed or removed.
create table consumption_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  ingredient_id uuid references ingredients (id) on delete set null,
  product_name  text not null,
  kind          consumption_kind not null,
  quantity      numeric(10, 2),
  unit          text,
  -- the item's expiry at the moment of the event, so "used in time" is
  -- answerable later without keeping the inventory row
  expiry_date   date,
  est_value_inr numeric(10, 2),
  recipe_id     uuid references recipes (id) on delete set null,
  occurred_at   timestamptz not null default now()
);

-- -------------------------------------------------------- shopping_list_items
create table shopping_list_items (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  ingredient_id    uuid references ingredients (id) on delete set null,
  product_name     text not null,
  quantity         numeric(10, 2) default 1,
  unit             text,
  source           shopping_source not null default 'manual',
  source_recipe_id uuid references recipes (id) on delete set null,
  purchased        boolean not null default false,
  created_at       timestamptz not null default now()
);

comment on table shopping_list_items is
  'BR-06: independent of inventory until the user confirms a purchase. Nothing here writes to inventory_items implicitly.';

-- ---------------------------------------------------------------- notifications
-- D8: a dedup ledger, not a delivery queue. The PRD chose
-- flutter_local_notifications over Firebase, so delivery is device-local.
create table notifications (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  inventory_item_id uuid not null references inventory_items (id) on delete cascade,
  level             notification_level not null,
  scheduled_for     timestamptz not null,
  delivered_at      timestamptz,
  created_at        timestamptz not null default now(),
  -- THIS is the BR-04 guarantee. "One reminder per item per level" is enforced
  -- by the database, not by app logic that could be bypassed by a retry.
  constraint notifications_one_per_item_level unique (inventory_item_id, level)
);

comment on constraint notifications_one_per_item_level on notifications is
  'BR-04 / board: one notification per item per level. Enforced here, not in app code.';


-- ==========================================================================
-- 002_rls.sql
-- ==========================================================================

-- ShelfLife MVP — row-level security
--
-- BR-05: inventory is unique per user account. Board: "Row-level security
-- scopes every row to user_id."
--
-- A table with RLS enabled and no policy denies everything. That is the safe
-- default, so each table below gets an explicit, deliberate decision.

-- ------------------------------------------------ enable on all ten tables
alter table profiles            enable row level security;
alter table ingredients         enable row level security;
alter table ingredient_aliases  enable row level security;
alter table products            enable row level security;
alter table recipes             enable row level security;
alter table recipe_ingredients  enable row level security;
alter table inventory_items     enable row level security;
alter table consumption_events  enable row level security;
alter table shopping_list_items enable row level security;
alter table notifications       enable row level security;

-- ==========================================================================
-- USER-OWNED TABLES
-- Four policies each. `with check` on insert and update matters as much as
-- `using` on select: without it a user could write a row belonging to someone
-- else, or move one of their own rows to another user_id.
-- ==========================================================================

-- ---------------------------------------------------------------- profiles
create policy profiles_select on profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_insert on profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_update on profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- No delete policy: account deletion cascades from auth.users.

-- ---------------------------------------------------------- inventory_items
create policy inventory_select on inventory_items
  for select to authenticated using (user_id = auth.uid());
create policy inventory_insert on inventory_items
  for insert to authenticated with check (user_id = auth.uid());
create policy inventory_update on inventory_items
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Delete is permitted and permanent (D7 / BR-02).
create policy inventory_delete on inventory_items
  for delete to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------- consumption_events
create policy consumption_select on consumption_events
  for select to authenticated using (user_id = auth.uid());
create policy consumption_insert on consumption_events
  for insert to authenticated with check (user_id = auth.uid());
-- Deliberately no update or delete: this is an append-only history. Allowing
-- edits would let the "meals rescued" and streak figures be rewritten after
-- the fact, which makes every statistic on screens 42 and 43 meaningless.

-- ------------------------------------------------------ shopping_list_items
create policy shopping_select on shopping_list_items
  for select to authenticated using (user_id = auth.uid());
create policy shopping_insert on shopping_list_items
  for insert to authenticated with check (user_id = auth.uid());
create policy shopping_update on shopping_list_items
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy shopping_delete on shopping_list_items
  for delete to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------ notifications
create policy notifications_select on notifications
  for select to authenticated using (user_id = auth.uid());
create policy notifications_insert on notifications
  for insert to authenticated with check (user_id = auth.uid());
create policy notifications_update on notifications
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Delete allowed: the board requires a scheduled notification to be cancelled
-- when its item is consumed or removed.
create policy notifications_delete on notifications
  for delete to authenticated using (user_id = auth.uid());

-- ==========================================================================
-- REFERENCE TABLES — read-only to every client
-- Seeded by migration. A `select` policy and nothing else, so insert, update
-- and delete are all refused with no policy to permit them.
-- ==========================================================================

create policy ingredients_read on ingredients
  for select to authenticated using (true);

create policy aliases_read on ingredient_aliases
  for select to authenticated using (true);

create policy recipes_read on recipes
  for select to authenticated using (true);

create policy recipe_ingredients_read on recipe_ingredients
  for select to authenticated using (true);

-- ==========================================================================
-- PRODUCTS — the one shared writable table
-- D1: the barcode cache "grows every time a user names an unknown barcode".
-- Insert-only. No update or delete policy, so a shared catalogue cannot be
-- edited or emptied by any client; D1 only requires that it grows.
-- ==========================================================================

create policy products_read on products
  for select to authenticated using (true);

create policy products_insert on products
  for insert to authenticated with check (contributed_by = auth.uid() and verified = false);

comment on policy products_insert on products is
  'verified = false is forced: a client cannot pass its own contribution off as seeded reference data.';


-- ==========================================================================
-- 003_indexes.sql
-- ==========================================================================

-- ShelfLife MVP — indexes
--
-- Every index below traces to a query the app actually runs. Speculative
-- indexes cost write throughput on a table the sync queue writes to often.
-- Targets from PRD 5.13: inventory search <1 s, dashboard load <2 s.

-- Inventory list (screen 24) and the Home "use these first" row (screen 10).
-- Both filter by user + active and sort by expiry ascending.
create index inventory_user_status_expiry
  on inventory_items (user_id, status, expiry_date);

-- Recipe matching and shopping-list suppression both ask "which canonical
-- ingredients does this user currently hold?". Partial, because neither ever
-- asks about consumed rows.
create index inventory_user_ingredient_active
  on inventory_items (user_id, ingredient_id)
  where status = 'active';

-- FR-02 search must return in under a second. The UI does substring matching
-- ("pan" finds "Paneer"), which a btree index cannot serve — a leading
-- wildcard forces a scan. Trigram GIN handles %term% directly.
create index inventory_product_name_trgm
  on inventory_items using gin (product_name gin_trgm_ops);

-- Alias resolution during receipt parsing: exact lookups are served by the
-- unique constraint, but the parser also does fuzzy matching on near-misses.
create index ingredient_aliases_alias_trgm
  on ingredient_aliases using gin (alias gin_trgm_ops);

-- Stats window on screens 42 and 43: "this month", "this year", "all time".
create index consumption_user_time
  on consumption_events (user_id, occurred_at desc);

-- Shopping list splits into "To buy" and "In the basket" (screen 39).
create index shopping_user_purchased
  on shopping_list_items (user_id, purchased);

-- Recipe matching joins from held ingredients back to recipes.
create index recipe_ingredients_ingredient
  on recipe_ingredients (ingredient_id);

-- The notification scheduler only ever asks for undelivered, due reminders.
create index notifications_pending
  on notifications (user_id, scheduled_for)
  where delivered_at is null;

-- Barcode-to-ingredient resolution after a successful scan.
create index products_ingredient
  on products (ingredient_id);


-- ==========================================================================
-- 004_functions.sql
-- ==========================================================================

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


-- ==========================================================================
-- 010_seed_ingredients.sql
-- ==========================================================================

-- GENERATED by supabase/seed/generate.py from supabase/seed/data.py
-- Do not edit. Change data.py and regenerate.

-- Canonical ingredient catalogue (spec §3). Shelf life is per storage
-- location; null means 'not sensibly stored this way'. Prices are rough
-- Indian retail rates and are ALWAYS surfaced as estimates.
insert into ingredients (canonical_name, category, default_unit, glyph_key,
  shelf_life_fridge_days, shelf_life_freezer_days, shelf_life_pantry_days,
  shelf_life_counter_days, est_price_inr) values
  ('spinach', 'vegetables'::food_category, 'g', 'spinach', 6, 90, null, 2, 40),
  ('tomato', 'vegetables'::food_category, 'kg', 'tomato', 10, null, null, 5, 40),
  ('onion', 'vegetables'::food_category, 'kg', 'onion', 30, null, 45, 30, 35),
  ('potato', 'vegetables'::food_category, 'kg', 'potato', 21, null, 40, 21, 30),
  ('cauliflower', 'vegetables'::food_category, 'head', 'cauliflower', 10, 60, null, 3, 40),
  ('broccoli', 'vegetables'::food_category, 'head', 'broccoli', 8, 60, null, 3, 80),
  ('capsicum', 'vegetables'::food_category, 'kg', 'capsicum', 12, 60, null, 4, 80),
  ('carrot', 'vegetables'::food_category, 'kg', 'carrot', 21, 90, null, 5, 50),
  ('cucumber', 'vegetables'::food_category, 'kg', 'cucumber', 7, null, null, 3, 40),
  ('coriander', 'vegetables'::food_category, 'bunch', 'coriander', 7, 30, null, 2, 15),
  ('ginger', 'vegetables'::food_category, 'g', 'ginger', 21, 90, 30, 14, 30),
  ('garlic', 'vegetables'::food_category, 'g', 'garlic', 30, 180, 90, 30, 40),
  ('green chilli', 'vegetables'::food_category, 'g', 'cat-vegetables', 14, 90, null, 4, 20),
  ('okra', 'vegetables'::food_category, 'kg', 'cat-vegetables', 5, 60, null, 2, 50),
  ('brinjal', 'vegetables'::food_category, 'kg', 'cat-vegetables', 7, null, null, 3, 40),
  ('beans', 'vegetables'::food_category, 'kg', 'cat-vegetables', 7, 90, null, 3, 60),
  ('cabbage', 'vegetables'::food_category, 'head', 'cat-vegetables', 14, null, null, 4, 30),
  ('bottle gourd', 'vegetables'::food_category, 'kg', 'cat-vegetables', 10, null, null, 4, 30),
  ('curry leaves', 'vegetables'::food_category, 'sprig', 'cat-vegetables', 10, 90, null, 3, 10),
  ('mushroom', 'vegetables'::food_category, 'g', 'cat-vegetables', 6, null, null, 2, 60),
  ('spring onion', 'vegetables'::food_category, 'bunch', 'cat-vegetables', 8, 60, null, 2, 25),
  ('peas', 'vegetables'::food_category, 'g', 'peas-frozen', 5, 180, null, 2, 40),
  ('banana', 'fruits'::food_category, 'pcs', 'banana', 7, null, null, 4, 50),
  ('apple', 'fruits'::food_category, 'kg', 'apple', 30, null, null, 7, 150),
  ('lemon', 'fruits'::food_category, 'pcs', 'lemon', 21, null, null, 7, 10),
  ('avocado', 'fruits'::food_category, 'pcs', 'avocado', 7, null, null, 3, 90),
  ('mango', 'fruits'::food_category, 'kg', 'cat-fruits', 7, 180, null, 4, 100),
  ('orange', 'fruits'::food_category, 'kg', 'cat-fruits', 21, null, null, 7, 80),
  ('grapes', 'fruits'::food_category, 'g', 'cat-fruits', 10, 90, null, 3, 80),
  ('pomegranate', 'fruits'::food_category, 'pcs', 'cat-fruits', 21, null, null, 7, 60),
  ('papaya', 'fruits'::food_category, 'kg', 'cat-fruits', 7, null, null, 3, 50),
  ('watermelon', 'fruits'::food_category, 'kg', 'cat-fruits', 10, null, null, 5, 30),
  ('guava', 'fruits'::food_category, 'kg', 'cat-fruits', 10, null, null, 4, 60),
  ('milk', 'dairy'::food_category, 'l', 'milk', 3, 30, null, null, 60),
  ('curd', 'dairy'::food_category, 'g', 'curd', 7, null, null, null, 40),
  ('paneer', 'dairy'::food_category, 'g', 'paneer', 5, 60, null, null, 90),
  ('butter', 'dairy'::food_category, 'g', 'cat-dairy', 45, 180, null, null, 60),
  ('ghee', 'dairy'::food_category, 'g', 'cat-dairy', 180, null, 180, 180, 120),
  ('cheese', 'dairy'::food_category, 'g', 'cat-dairy', 21, 120, null, null, 120),
  ('cream', 'dairy'::food_category, 'ml', 'cream', 7, null, null, null, 70),
  ('buttermilk', 'dairy'::food_category, 'ml', 'cat-dairy', 4, null, null, null, 25),
  ('atta', 'pantry'::food_category, 'kg', 'atta', null, null, 120, null, 250),
  ('rice', 'pantry'::food_category, 'kg', 'rice', null, null, 365, null, 120),
  ('toor dal', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 240, null, 160),
  ('moong dal', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 240, null, 150),
  ('chana dal', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 240, null, 140),
  ('sugar', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 730, null, 50),
  ('salt', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 999, null, 25),
  ('cooking oil', 'pantry'::food_category, 'l', 'cat-pantry', null, null, 365, null, 140),
  ('tea', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 365, null, 200),
  ('coffee', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 240, null, 300),
  ('bread', 'pantry'::food_category, 'pcs', 'cat-pantry', 7, 30, 3, 3, 50),
  ('eggs', 'pantry'::food_category, 'pcs', 'cat-pantry', 28, null, null, 7, 90),
  ('poha', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 180, null, 60),
  ('besan', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 180, null, 90),
  ('jaggery', 'pantry'::food_category, 'kg', 'cat-pantry', null, null, 365, null, 70),
  ('garam masala', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 365, null, 80),
  ('turmeric', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 730, null, 40),
  ('cumin', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 730, null, 60),
  ('kasuri methi', 'pantry'::food_category, 'g', 'cat-pantry', null, null, 365, null, 40),
  ('cashew', 'pantry'::food_category, 'g', 'cat-pantry', 180, 365, 120, null, 200),
  ('frozen peas', 'frozen'::food_category, 'g', 'peas-frozen', null, 180, null, null, 60),
  ('frozen paratha', 'frozen'::food_category, 'pcs', 'cat-frozen', null, 180, null, null, 80),
  ('ice cream', 'frozen'::food_category, 'ml', 'cat-frozen', null, 120, null, null, 150),
  ('frozen vegetables', 'frozen'::food_category, 'g', 'cat-frozen', null, 180, null, null, 70)
on conflict (canonical_name) do nothing;

-- Alias resolution: OCR text, typed names and recipe references all
-- resolve through here. Aliases are globally unique so parsing is
-- deterministic.
insert into ingredient_aliases (ingredient_id, alias) values
  ((select id from ingredients where canonical_name = 'mango'), 'aam'),
  ((select id from ingredients where canonical_name = 'atta'), 'aashirvaad atta'),
  ((select id from ingredients where canonical_name = 'ginger'), 'adrak'),
  ((select id from ingredients where canonical_name = 'potato'), 'aloo'),
  ((select id from ingredients where canonical_name = 'potato'), 'alu'),
  ((select id from ingredients where canonical_name = 'guava'), 'amrud'),
  ((select id from ingredients where canonical_name = 'butter'), 'amul butter'),
  ((select id from ingredients where canonical_name = 'cheese'), 'amul cheese'),
  ((select id from ingredients where canonical_name = 'cream'), 'amul cream'),
  ((select id from ingredients where canonical_name = 'curd'), 'amul dahi'),
  ((select id from ingredients where canonical_name = 'milk'), 'amul gold'),
  ((select id from ingredients where canonical_name = 'paneer'), 'amul paneer'),
  ((select id from ingredients where canonical_name = 'milk'), 'amul taaza'),
  ((select id from ingredients where canonical_name = 'pomegranate'), 'anar'),
  ((select id from ingredients where canonical_name = 'eggs'), 'anda'),
  ((select id from ingredients where canonical_name = 'grapes'), 'angoor'),
  ((select id from ingredients where canonical_name = 'apple'), 'apples'),
  ((select id from ingredients where canonical_name = 'toor dal'), 'arhar dal'),
  ((select id from ingredients where canonical_name = 'brinjal'), 'aubergine'),
  ((select id from ingredients where canonical_name = 'avocado'), 'avacado'),
  ((select id from ingredients where canonical_name = 'avocado'), 'avocados'),
  ((select id from ingredients where canonical_name = 'spinach'), 'baby spinach'),
  ((select id from ingredients where canonical_name = 'brinjal'), 'baingan'),
  ((select id from ingredients where canonical_name = 'banana'), 'bananas'),
  ((select id from ingredients where canonical_name = 'rice'), 'basmati rice'),
  ((select id from ingredients where canonical_name = 'potato'), 'batata'),
  ((select id from ingredients where canonical_name = 'capsicum'), 'bell pepper'),
  ((select id from ingredients where canonical_name = 'chana dal'), 'bengal gram'),
  ((select id from ingredients where canonical_name = 'okra'), 'bhindi'),
  ((select id from ingredients where canonical_name = 'bread'), 'bread loaf'),
  ((select id from ingredients where canonical_name = 'broccoli'), 'brocoli'),
  ((select id from ingredients where canonical_name = 'broccoli'), 'brocolli'),
  ((select id from ingredients where canonical_name = 'bread'), 'brown bread'),
  ((select id from ingredients where canonical_name = 'avocado'), 'butter fruit'),
  ((select id from ingredients where canonical_name = 'mushroom'), 'button mushroom'),
  ((select id from ingredients where canonical_name = 'capsicum'), 'capsicum green'),
  ((select id from ingredients where canonical_name = 'carrot'), 'carrots'),
  ((select id from ingredients where canonical_name = 'cashew'), 'cashewnut'),
  ((select id from ingredients where canonical_name = 'buttermilk'), 'chaas'),
  ((select id from ingredients where canonical_name = 'tea'), 'chai patti'),
  ((select id from ingredients where canonical_name = 'atta'), 'chakki atta'),
  ((select id from ingredients where canonical_name = 'chana dal'), 'chana daal'),
  ((select id from ingredients where canonical_name = 'rice'), 'chawal'),
  ((select id from ingredients where canonical_name = 'sugar'), 'cheeni'),
  ((select id from ingredients where canonical_name = 'cheese'), 'cheese slices'),
  ((select id from ingredients where canonical_name = 'poha'), 'chiwda'),
  ((select id from ingredients where canonical_name = 'coriander'), 'cilantro'),
  ((select id from ingredients where canonical_name = 'ghee'), 'clarified butter'),
  ((select id from ingredients where canonical_name = 'coriander'), 'coriander leaves'),
  ((select id from ingredients where canonical_name = 'paneer'), 'cottage cheese'),
  ((select id from ingredients where canonical_name = 'milk'), 'cow milk'),
  ((select id from ingredients where canonical_name = 'cucumber'), 'cucumbers'),
  ((select id from ingredients where canonical_name = 'cumin'), 'cumin seeds'),
  ((select id from ingredients where canonical_name = 'curd'), 'dahi'),
  ((select id from ingredients where canonical_name = 'ghee'), 'desi ghee'),
  ((select id from ingredients where canonical_name = 'tomato'), 'desi tomato'),
  ((select id from ingredients where canonical_name = 'coriander'), 'dhania'),
  ((select id from ingredients where canonical_name = 'milk'), 'doodh'),
  ((select id from ingredients where canonical_name = 'bottle gourd'), 'doodhi'),
  ((select id from ingredients where canonical_name = 'kasuri methi'), 'dried fenugreek'),
  ((select id from ingredients where canonical_name = 'eggs'), 'egg'),
  ((select id from ingredients where canonical_name = 'brinjal'), 'eggplant'),
  ((select id from ingredients where canonical_name = 'poha'), 'flattened rice'),
  ((select id from ingredients where canonical_name = 'cooking oil'), 'fortune oil'),
  ((select id from ingredients where canonical_name = 'beans'), 'french beans'),
  ((select id from ingredients where canonical_name = 'cream'), 'fresh cream'),
  ((select id from ingredients where canonical_name = 'spinach'), 'fresh spinach'),
  ((select id from ingredients where canonical_name = 'frozen peas'), 'frozen matar'),
  ((select id from ingredients where canonical_name = 'milk'), 'full cream milk'),
  ((select id from ingredients where canonical_name = 'carrot'), 'gajar'),
  ((select id from ingredients where canonical_name = 'garam masala'), 'garam masala powder'),
  ((select id from ingredients where canonical_name = 'garlic'), 'garlic pods'),
  ((select id from ingredients where canonical_name = 'atta'), 'gehun ka atta'),
  ((select id from ingredients where canonical_name = 'ginger'), 'ginger fresh'),
  ((select id from ingredients where canonical_name = 'cauliflower'), 'gobhi'),
  ((select id from ingredients where canonical_name = 'cauliflower'), 'gobi'),
  ((select id from ingredients where canonical_name = 'besan'), 'gram flour'),
  ((select id from ingredients where canonical_name = 'beans'), 'green beans'),
  ((select id from ingredients where canonical_name = 'green chilli'), 'green chillies'),
  ((select id from ingredients where canonical_name = 'peas'), 'green peas'),
  ((select id from ingredients where canonical_name = 'capsicum'), 'green pepper'),
  ((select id from ingredients where canonical_name = 'jaggery'), 'gud'),
  ((select id from ingredients where canonical_name = 'turmeric'), 'haldi'),
  ((select id from ingredients where canonical_name = 'coriander'), 'hara dhania'),
  ((select id from ingredients where canonical_name = 'spring onion'), 'hara pyaz'),
  ((select id from ingredients where canonical_name = 'green chilli'), 'hari mirch'),
  ((select id from ingredients where canonical_name = 'tomato'), 'hybrid tomato'),
  ((select id from ingredients where canonical_name = 'rice'), 'india gate rice'),
  ((select id from ingredients where canonical_name = 'coffee'), 'instant coffee'),
  ((select id from ingredients where canonical_name = 'cumin'), 'jeera'),
  ((select id from ingredients where canonical_name = 'curry leaves'), 'kadi patta'),
  ((select id from ingredients where canonical_name = 'cashew'), 'kaju'),
  ((select id from ingredients where canonical_name = 'onion'), 'kanda'),
  ((select id from ingredients where canonical_name = 'banana'), 'kela'),
  ((select id from ingredients where canonical_name = 'cucumber'), 'kheera'),
  ((select id from ingredients where canonical_name = 'cucumber'), 'khira'),
  ((select id from ingredients where canonical_name = 'okra'), 'ladies finger'),
  ((select id from ingredients where canonical_name = 'buttermilk'), 'lassi'),
  ((select id from ingredients where canonical_name = 'garlic'), 'lasun'),
  ((select id from ingredients where canonical_name = 'bottle gourd'), 'lauki'),
  ((select id from ingredients where canonical_name = 'garlic'), 'lehsun'),
  ((select id from ingredients where canonical_name = 'lemon'), 'lemons'),
  ((select id from ingredients where canonical_name = 'lemon'), 'lime'),
  ((select id from ingredients where canonical_name = 'butter'), 'makhan'),
  ((select id from ingredients where canonical_name = 'paneer'), 'malai paneer'),
  ((select id from ingredients where canonical_name = 'peas'), 'matar'),
  ((select id from ingredients where canonical_name = 'kasuri methi'), 'methi'),
  ((select id from ingredients where canonical_name = 'milk'), 'milk 1l'),
  ((select id from ingredients where canonical_name = 'green chilli'), 'mirchi'),
  ((select id from ingredients where canonical_name = 'moong dal'), 'moong daal'),
  ((select id from ingredients where canonical_name = 'mushroom'), 'mushrooms'),
  ((select id from ingredients where canonical_name = 'cooking oil'), 'mustard oil'),
  ((select id from ingredients where canonical_name = 'salt'), 'namak'),
  ((select id from ingredients where canonical_name = 'lemon'), 'nimbu'),
  ((select id from ingredients where canonical_name = 'okra'), 'okra fresh'),
  ((select id from ingredients where canonical_name = 'onion'), 'onion big'),
  ((select id from ingredients where canonical_name = 'onion'), 'onions'),
  ((select id from ingredients where canonical_name = 'orange'), 'oranges'),
  ((select id from ingredients where canonical_name = 'spinach'), 'paalak'),
  ((select id from ingredients where canonical_name = 'spinach'), 'palak'),
  ((select id from ingredients where canonical_name = 'papaya'), 'papita'),
  ((select id from ingredients where canonical_name = 'frozen paratha'), 'paratha frozen'),
  ((select id from ingredients where canonical_name = 'cabbage'), 'patta gobi'),
  ((select id from ingredients where canonical_name = 'bread'), 'pav'),
  ((select id from ingredients where canonical_name = 'cauliflower'), 'phool gobi'),
  ((select id from ingredients where canonical_name = 'potato'), 'potatoes'),
  ((select id from ingredients where canonical_name = 'onion'), 'pyaz'),
  ((select id from ingredients where canonical_name = 'onion'), 'red onion'),
  ((select id from ingredients where canonical_name = 'cooking oil'), 'refined oil'),
  ((select id from ingredients where canonical_name = 'banana'), 'robusta banana'),
  ((select id from ingredients where canonical_name = 'frozen peas'), 'safal frozen peas'),
  ((select id from ingredients where canonical_name = 'orange'), 'santra'),
  ((select id from ingredients where canonical_name = 'apple'), 'seb'),
  ((select id from ingredients where canonical_name = 'sugar'), 'shakkar'),
  ((select id from ingredients where canonical_name = 'apple'), 'shimla apple'),
  ((select id from ingredients where canonical_name = 'capsicum'), 'shimla mirch'),
  ((select id from ingredients where canonical_name = 'rice'), 'sona masoori'),
  ((select id from ingredients where canonical_name = 'spinach'), 'spinach leaves'),
  ((select id from ingredients where canonical_name = 'cooking oil'), 'sunflower oil'),
  ((select id from ingredients where canonical_name = 'tomato'), 'tamatar'),
  ((select id from ingredients where canonical_name = 'watermelon'), 'tarbooj'),
  ((select id from ingredients where canonical_name = 'tea'), 'tata tea'),
  ((select id from ingredients where canonical_name = 'tea'), 'tea leaves'),
  ((select id from ingredients where canonical_name = 'tomato'), 'tomato local'),
  ((select id from ingredients where canonical_name = 'tomato'), 'tomatoes'),
  ((select id from ingredients where canonical_name = 'milk'), 'toned milk'),
  ((select id from ingredients where canonical_name = 'toor dal'), 'toor daal'),
  ((select id from ingredients where canonical_name = 'turmeric'), 'turmeric powder'),
  ((select id from ingredients where canonical_name = 'toor dal'), 'tuvar dal'),
  ((select id from ingredients where canonical_name = 'atta'), 'wheat flour'),
  ((select id from ingredients where canonical_name = 'moong dal'), 'yellow moong dal'),
  ((select id from ingredients where canonical_name = 'curd'), 'yoghurt'),
  ((select id from ingredients where canonical_name = 'curd'), 'yogurt')
on conflict (alias) do nothing;


-- ==========================================================================
-- 011_seed_recipes.sql
-- ==========================================================================

-- GENERATED by supabase/seed/generate.py from supabase/seed/data.py
-- Do not edit. Change data.py and regenerate.

insert into recipes (name, prep_minutes, servings, difficulty, category,
  method_steps, image_key) values
  ('Palak Paneer', 25, 4, 'Easy', 'main', '["Blanch the spinach for two minutes, then blend to a smooth puree.", "Fry the onion, ginger and garlic until golden.", "Add tomato and garam masala; cook until the oil separates.", "Stir in the spinach puree and simmer for five minutes.", "Fold in the paneer cubes and finish with cream."]'::jsonb, 'palak-paneer'),
  ('Aloo Gobi', 30, 4, 'Easy', 'main', '["Cut the potato and cauliflower into even florets and cubes.", "Temper cumin in hot oil until it crackles.", "Add the potato, cover and cook until half done.", "Add cauliflower, turmeric and salt; cook uncovered until edges brown.", "Finish with coriander."]'::jsonb, 'aloo-gobi'),
  ('Vegetable Pulao', 40, 4, 'Easy', 'main', '["Rinse and soak the rice for twenty minutes.", "Fry whole spices and onion in ghee until fragrant.", "Add the mixed vegetables and saute briefly.", "Add rice and water at one to one and a half, then bring to a boil.", "Cover and cook on low for twelve minutes, then rest before fluffing."]'::jsonb, 'vegetable-pulao'),
  ('Paneer Bhurji', 20, 3, 'Easy', 'main', '["Crumble the paneer coarsely.", "Saute onion, green chilli and ginger until soft.", "Add tomato and cook until pulpy.", "Stir in the crumbled paneer and turmeric; cook two minutes.", "Finish with coriander and a squeeze of lemon."]'::jsonb, 'paneer-bhurji'),
  ('Avocado Toast', 10, 2, 'Easy', 'breakfast', '["Toast the bread until crisp.", "Mash the avocado with salt and lemon.", "Spread thickly and top with chilli flakes."]'::jsonb, 'avocado-toast'),
  ('Jeera Aloo', 20, 3, 'Easy', 'side', '["Boil and cube the potatoes.", "Crackle cumin in hot oil.", "Toss the potatoes with turmeric and salt until coated.", "Finish with coriander."]'::jsonb, 'aloo-gobi'),
  ('Palak Dal', 35, 4, 'Easy', 'main', '["Pressure cook the toor dal until soft.", "Saute garlic, cumin and green chilli.", "Add chopped spinach and wilt.", "Combine with the dal and simmer ten minutes."]'::jsonb, 'palak-paneer'),
  ('Tomato Rasam', 25, 4, 'Easy', 'soup', '["Simmer tomato with turmeric and salt.", "Add cooked toor dal and water.", "Temper cumin and curry leaves; pour over.", "Finish with coriander."]'::jsonb, 'aloo-gobi'),
  ('Bhindi Masala', 25, 3, 'Easy', 'side', '["Wash and dry the okra completely, then slice.", "Fry until the sliminess disappears.", "Add onion and tomato; cook down.", "Season with garam masala and salt."]'::jsonb, 'aloo-gobi'),
  ('Baingan Bharta', 40, 4, 'Medium', 'main', '["Char the brinjal directly over flame until collapsed.", "Peel and mash the smoked flesh.", "Fry onion, ginger, garlic and tomato.", "Fold in the mashed brinjal and cook until dry.", "Finish with coriander."]'::jsonb, 'aloo-gobi'),
  ('Poha', 15, 2, 'Easy', 'breakfast', '["Rinse the poha briefly and drain.", "Temper mustard, curry leaves and green chilli.", "Add onion and potato; cook through.", "Fold in the poha with turmeric and salt.", "Finish with lemon and coriander."]'::jsonb, 'vegetable-pulao'),
  ('Besan Chilla', 15, 2, 'Easy', 'breakfast', '["Whisk besan with water to a pourable batter.", "Stir in onion, tomato, chilli and coriander.", "Ladle onto a hot pan and spread thin.", "Cook both sides until golden."]'::jsonb, 'avocado-toast'),
  ('Masala Omelette', 10, 2, 'Easy', 'breakfast', '["Beat the eggs with salt.", "Add onion, tomato, chilli and coriander.", "Cook on a hot pan, folding once."]'::jsonb, 'paneer-bhurji'),
  ('Matar Paneer', 30, 4, 'Easy', 'main', '["Blend onion and tomato into a smooth base.", "Cook the base until the oil separates.", "Add peas and simmer until tender.", "Add paneer and garam masala; rest before serving."]'::jsonb, 'paneer-bhurji'),
  ('Cabbage Poriyal', 20, 3, 'Easy', 'side', '["Shred the cabbage finely.", "Temper mustard, curry leaves and chana dal.", "Add cabbage and cook uncovered until just tender."]'::jsonb, 'aloo-gobi'),
  ('Lauki Sabzi', 25, 3, 'Easy', 'side', '["Peel and cube the bottle gourd.", "Temper cumin, then add tomato and turmeric.", "Add the gourd, cover and cook until soft."]'::jsonb, 'aloo-gobi'),
  ('Carrot Halwa', 45, 4, 'Medium', 'dessert', '["Grate the carrots finely.", "Cook in milk until the liquid reduces almost fully.", "Add sugar and ghee; cook until glossy.", "Finish with cashews."]'::jsonb, 'vegetable-pulao'),
  ('Cucumber Raita', 10, 4, 'Easy', 'side', '["Whisk the curd smooth.", "Grate the cucumber and squeeze out excess water.", "Fold together with cumin and salt."]'::jsonb, 'curd'),
  ('Boondi Kadhi', 35, 4, 'Medium', 'main', '["Whisk curd with besan and turmeric until lump-free.", "Simmer gently, stirring, for twenty minutes.", "Temper cumin and curry leaves; pour over."]'::jsonb, 'curd'),
  ('Mushroom Masala', 25, 3, 'Easy', 'main', '["Clean and quarter the mushrooms.", "Fry onion, ginger and garlic until golden.", "Add tomato and cook down.", "Add mushrooms and cook until they release and reabsorb their liquid."]'::jsonb, 'aloo-gobi'),
  ('Paneer Tikka', 35, 4, 'Medium', 'starter', '["Marinate paneer and capsicum in spiced curd for twenty minutes.", "Thread onto skewers with onion.", "Grill or pan-sear until charred at the edges.", "Finish with lemon."]'::jsonb, 'paneer-bhurji'),
  ('Dal Tadka', 30, 4, 'Easy', 'main', '["Pressure cook toor dal with turmeric until soft.", "Heat ghee and crackle cumin, garlic and chilli.", "Pour the tempering over the dal.", "Finish with coriander."]'::jsonb, 'aloo-gobi'),
  ('Moong Dal Khichdi', 30, 3, 'Easy', 'main', '["Rinse rice and moong dal together.", "Pressure cook with turmeric, salt and water.", "Temper cumin in ghee and stir through."]'::jsonb, 'vegetable-pulao'),
  ('Vegetable Upma', 20, 3, 'Easy', 'breakfast', '["Dry roast the poha lightly.", "Temper mustard, curry leaves and chana dal.", "Add onion, carrot and peas; cook briefly.", "Add water, then fold in the poha and cook covered."]'::jsonb, 'vegetable-pulao'),
  ('Tomato Onion Salad', 8, 2, 'Easy', 'salad', '["Slice tomato, onion and cucumber thinly.", "Dress with lemon, salt and coriander."]'::jsonb, 'cucumber'),
  ('Aloo Paratha', 40, 4, 'Medium', 'breakfast', '["Boil, peel and mash the potatoes.", "Season with chilli, coriander and salt.", "Stuff into atta dough rounds and roll gently.", "Cook on a hot tawa with ghee until spotted."]'::jsonb, 'aloo-gobi'),
  ('Chana Dal Sundal', 25, 4, 'Easy', 'side', '["Soak and boil the chana dal until just firm.", "Temper mustard, curry leaves and chilli.", "Toss the dal through and season."]'::jsonb, 'aloo-gobi'),
  ('Paneer Butter Masala', 35, 4, 'Medium', 'main', '["Blend tomato, cashew, ginger and garlic into a smooth base.", "Cook the base in butter until deep red.", "Add cream and garam masala.", "Fold in paneer and finish with kasuri methi."]'::jsonb, 'palak-paneer'),
  ('Green Beans Stir Fry', 18, 3, 'Easy', 'side', '["Trim and chop the beans small.", "Temper mustard and chana dal.", "Add beans with a splash of water and cook covered until tender."]'::jsonb, 'aloo-gobi'),
  ('Masala Chai', 10, 2, 'Easy', 'beverage', '["Boil water with crushed ginger and tea leaves.", "Add milk and sugar; bring to a rolling boil.", "Strain and serve."]'::jsonb, 'curd'),
  ('Banana Smoothie', 8, 2, 'Easy', 'beverage', '["Blend banana, curd and milk until smooth.", "Sweeten with jaggery to taste."]'::jsonb, 'curd'),
  ('Apple Cinnamon Porridge', 15, 2, 'Easy', 'breakfast', '["Simmer poha in milk until thickened.", "Grate in the apple and sweeten with jaggery."]'::jsonb, 'curd'),
  ('Cheese Toast', 10, 2, 'Easy', 'snack', '["Butter the bread lightly.", "Layer cheese, tomato and chilli.", "Grill until bubbling."]'::jsonb, 'avocado-toast'),
  ('Capsicum Rice', 25, 3, 'Easy', 'main', '["Cook and cool the rice.", "Saute capsicum and onion until blistered.", "Fold the rice through with garam masala."]'::jsonb, 'vegetable-pulao'),
  ('Spinach Soup', 25, 4, 'Easy', 'soup', '["Wilt the spinach with garlic.", "Blend smooth with a little milk.", "Reheat gently and season."]'::jsonb, 'palak-paneer'),
  ('Frozen Peas Pulao', 25, 3, 'Easy', 'main', '["Soak the rice twenty minutes.", "Fry onion and whole spices in ghee.", "Add frozen peas straight from the freezer.", "Add rice and water; cook covered on low."]'::jsonb, 'vegetable-pulao'),
  ('Curd Rice', 15, 3, 'Easy', 'main', '["Mash warm cooked rice with curd and salt.", "Temper mustard, curry leaves and chilli.", "Stir through and rest before serving."]'::jsonb, 'curd'),
  ('Guava Chaat', 8, 2, 'Easy', 'snack', '["Cube the guava.", "Toss with lemon, salt and cumin."]'::jsonb, 'cucumber'),
  ('Mango Lassi', 8, 2, 'Easy', 'beverage', '["Blend mango with curd and sugar.", "Thin with a little milk and chill."]'::jsonb, 'curd'),
  ('Ghee Roast Paratha', 20, 2, 'Easy', 'breakfast', '["Knead atta into a soft dough and rest.", "Roll into rounds and layer with ghee.", "Cook on a hot tawa until puffed."]'::jsonb, 'aloo-gobi')
on conflict (name) do nothing;

-- Normalised ingredient rows (D5): FR-07 ranks by availability, which
-- is a join against inventory. Optional rows never count toward the
-- have/total match.
insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit, optional) values
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'spinach'), 500, 'g', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'paneer'), 200, 'g', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'onion'), 2, 'pcs', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'ginger'), 1, 'inch', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'garlic'), 4, 'cloves', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'cream'), 100, 'ml', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'kasuri methi'), 1, 'tsp', false),
  ((select id from recipes where name = 'Palak Paneer'), (select id from ingredients where canonical_name = 'cooking oil'), 2, 'tbsp', true),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'potato'), 3, 'pcs', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'cauliflower'), 1, 'head', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'turmeric'), 1, 'tsp', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'cooking oil'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Aloo Gobi'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', true),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'rice'), 2, 'cups', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'carrot'), 1, 'pcs', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'beans'), 100, 'g', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'peas'), 100, 'g', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'ghee'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Vegetable Pulao'), (select id from ingredients where canonical_name = 'cashew'), 10, 'pcs', true),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'paneer'), 250, 'g', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'tomato'), 2, 'pcs', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'ginger'), 1, 'inch', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Paneer Bhurji'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', true),
  ((select id from recipes where name = 'Avocado Toast'), (select id from ingredients where canonical_name = 'bread'), 2, 'pcs', false),
  ((select id from recipes where name = 'Avocado Toast'), (select id from ingredients where canonical_name = 'avocado'), 1, 'pcs', false),
  ((select id from recipes where name = 'Avocado Toast'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Avocado Toast'), (select id from ingredients where canonical_name = 'salt'), 1, 'pinch', false),
  ((select id from recipes where name = 'Avocado Toast'), (select id from ingredients where canonical_name = 'green chilli'), 1, 'pcs', true),
  ((select id from recipes where name = 'Jeera Aloo'), (select id from ingredients where canonical_name = 'potato'), 4, 'pcs', false),
  ((select id from recipes where name = 'Jeera Aloo'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Jeera Aloo'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Jeera Aloo'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Jeera Aloo'), (select id from ingredients where canonical_name = 'cooking oil'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'toor dal'), 1, 'cup', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'spinach'), 250, 'g', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'garlic'), 4, 'cloves', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Palak Dal'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', true),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'tomato'), 4, 'pcs', false),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'toor dal'), 0.5, 'cup', false),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Tomato Rasam'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Bhindi Masala'), (select id from ingredients where canonical_name = 'okra'), 400, 'g', false),
  ((select id from recipes where name = 'Bhindi Masala'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Bhindi Masala'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Bhindi Masala'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Bhindi Masala'), (select id from ingredients where canonical_name = 'cooking oil'), 3, 'tbsp', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'brinjal'), 1, 'pcs', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'onion'), 2, 'pcs', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'tomato'), 2, 'pcs', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'ginger'), 1, 'inch', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'garlic'), 4, 'cloves', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Baingan Bharta'), (select id from ingredients where canonical_name = 'cooking oil'), 3, 'tbsp', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'poha'), 2, 'cups', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'potato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Poha'), (select id from ingredients where canonical_name = 'peas'), 50, 'g', true),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'besan'), 1, 'cup', false),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'green chilli'), 1, 'pcs', false),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Besan Chilla'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', true),
  ((select id from recipes where name = 'Masala Omelette'), (select id from ingredients where canonical_name = 'eggs'), 3, 'pcs', false),
  ((select id from recipes where name = 'Masala Omelette'), (select id from ingredients where canonical_name = 'onion'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Masala Omelette'), (select id from ingredients where canonical_name = 'tomato'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Masala Omelette'), (select id from ingredients where canonical_name = 'green chilli'), 1, 'pcs', false),
  ((select id from recipes where name = 'Masala Omelette'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'paneer'), 200, 'g', false),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'peas'), 150, 'g', false),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'onion'), 2, 'pcs', false),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'tomato'), 2, 'pcs', false),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Matar Paneer'), (select id from ingredients where canonical_name = 'cream'), 50, 'ml', true),
  ((select id from recipes where name = 'Cabbage Poriyal'), (select id from ingredients where canonical_name = 'cabbage'), 1, 'head', false),
  ((select id from recipes where name = 'Cabbage Poriyal'), (select id from ingredients where canonical_name = 'chana dal'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Cabbage Poriyal'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Cabbage Poriyal'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', false),
  ((select id from recipes where name = 'Cabbage Poriyal'), (select id from ingredients where canonical_name = 'cooking oil'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Lauki Sabzi'), (select id from ingredients where canonical_name = 'bottle gourd'), 1, 'pcs', false),
  ((select id from recipes where name = 'Lauki Sabzi'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Lauki Sabzi'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Lauki Sabzi'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Lauki Sabzi'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Carrot Halwa'), (select id from ingredients where canonical_name = 'carrot'), 1, 'kg', false),
  ((select id from recipes where name = 'Carrot Halwa'), (select id from ingredients where canonical_name = 'milk'), 1, 'l', false),
  ((select id from recipes where name = 'Carrot Halwa'), (select id from ingredients where canonical_name = 'sugar'), 1, 'cup', false),
  ((select id from recipes where name = 'Carrot Halwa'), (select id from ingredients where canonical_name = 'ghee'), 3, 'tbsp', false),
  ((select id from recipes where name = 'Carrot Halwa'), (select id from ingredients where canonical_name = 'cashew'), 15, 'pcs', true),
  ((select id from recipes where name = 'Cucumber Raita'), (select id from ingredients where canonical_name = 'curd'), 400, 'g', false),
  ((select id from recipes where name = 'Cucumber Raita'), (select id from ingredients where canonical_name = 'cucumber'), 1, 'pcs', false),
  ((select id from recipes where name = 'Cucumber Raita'), (select id from ingredients where canonical_name = 'cumin'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Cucumber Raita'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Boondi Kadhi'), (select id from ingredients where canonical_name = 'curd'), 500, 'g', false),
  ((select id from recipes where name = 'Boondi Kadhi'), (select id from ingredients where canonical_name = 'besan'), 4, 'tbsp', false),
  ((select id from recipes where name = 'Boondi Kadhi'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Boondi Kadhi'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Boondi Kadhi'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'mushroom'), 400, 'g', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'tomato'), 2, 'pcs', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'ginger'), 1, 'inch', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'garlic'), 3, 'cloves', false),
  ((select id from recipes where name = 'Mushroom Masala'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'paneer'), 250, 'g', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'curd'), 100, 'g', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'capsicum'), 1, 'pcs', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Paneer Tikka'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'toor dal'), 1, 'cup', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'ghee'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'garlic'), 4, 'cloves', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Dal Tadka'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'rice'), 1, 'cup', false),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'moong dal'), 0.5, 'cup', false),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'ghee'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'cumin'), 1, 'tsp', false),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'turmeric'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Moong Dal Khichdi'), (select id from ingredients where canonical_name = 'peas'), 50, 'g', true),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'poha'), 1.5, 'cups', false),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'carrot'), 1, 'pcs', false),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'peas'), 50, 'g', false),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Vegetable Upma'), (select id from ingredients where canonical_name = 'cooking oil'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Tomato Onion Salad'), (select id from ingredients where canonical_name = 'tomato'), 2, 'pcs', false),
  ((select id from recipes where name = 'Tomato Onion Salad'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Tomato Onion Salad'), (select id from ingredients where canonical_name = 'cucumber'), 1, 'pcs', false),
  ((select id from recipes where name = 'Tomato Onion Salad'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Tomato Onion Salad'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', true),
  ((select id from recipes where name = 'Aloo Paratha'), (select id from ingredients where canonical_name = 'atta'), 2, 'cups', false),
  ((select id from recipes where name = 'Aloo Paratha'), (select id from ingredients where canonical_name = 'potato'), 4, 'pcs', false),
  ((select id from recipes where name = 'Aloo Paratha'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', false),
  ((select id from recipes where name = 'Aloo Paratha'), (select id from ingredients where canonical_name = 'coriander'), 1, 'bunch', false),
  ((select id from recipes where name = 'Aloo Paratha'), (select id from ingredients where canonical_name = 'ghee'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Chana Dal Sundal'), (select id from ingredients where canonical_name = 'chana dal'), 1, 'cup', false),
  ((select id from recipes where name = 'Chana Dal Sundal'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Chana Dal Sundal'), (select id from ingredients where canonical_name = 'green chilli'), 2, 'pcs', false),
  ((select id from recipes where name = 'Chana Dal Sundal'), (select id from ingredients where canonical_name = 'cooking oil'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'paneer'), 250, 'g', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'tomato'), 4, 'pcs', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'cashew'), 12, 'pcs', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'butter'), 40, 'g', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'cream'), 80, 'ml', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'kasuri methi'), 1, 'tsp', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'ginger'), 1, 'inch', false),
  ((select id from recipes where name = 'Paneer Butter Masala'), (select id from ingredients where canonical_name = 'garlic'), 4, 'cloves', false),
  ((select id from recipes where name = 'Green Beans Stir Fry'), (select id from ingredients where canonical_name = 'beans'), 300, 'g', false),
  ((select id from recipes where name = 'Green Beans Stir Fry'), (select id from ingredients where canonical_name = 'chana dal'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Green Beans Stir Fry'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Green Beans Stir Fry'), (select id from ingredients where canonical_name = 'cooking oil'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Masala Chai'), (select id from ingredients where canonical_name = 'tea'), 2, 'tsp', false),
  ((select id from recipes where name = 'Masala Chai'), (select id from ingredients where canonical_name = 'milk'), 200, 'ml', false),
  ((select id from recipes where name = 'Masala Chai'), (select id from ingredients where canonical_name = 'sugar'), 2, 'tsp', false),
  ((select id from recipes where name = 'Masala Chai'), (select id from ingredients where canonical_name = 'ginger'), 0.5, 'inch', false),
  ((select id from recipes where name = 'Banana Smoothie'), (select id from ingredients where canonical_name = 'banana'), 2, 'pcs', false),
  ((select id from recipes where name = 'Banana Smoothie'), (select id from ingredients where canonical_name = 'curd'), 150, 'g', false),
  ((select id from recipes where name = 'Banana Smoothie'), (select id from ingredients where canonical_name = 'milk'), 150, 'ml', false),
  ((select id from recipes where name = 'Banana Smoothie'), (select id from ingredients where canonical_name = 'jaggery'), 1, 'tbsp', true),
  ((select id from recipes where name = 'Apple Cinnamon Porridge'), (select id from ingredients where canonical_name = 'poha'), 1, 'cup', false),
  ((select id from recipes where name = 'Apple Cinnamon Porridge'), (select id from ingredients where canonical_name = 'milk'), 400, 'ml', false),
  ((select id from recipes where name = 'Apple Cinnamon Porridge'), (select id from ingredients where canonical_name = 'apple'), 1, 'pcs', false),
  ((select id from recipes where name = 'Apple Cinnamon Porridge'), (select id from ingredients where canonical_name = 'jaggery'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Cheese Toast'), (select id from ingredients where canonical_name = 'bread'), 4, 'pcs', false),
  ((select id from recipes where name = 'Cheese Toast'), (select id from ingredients where canonical_name = 'cheese'), 60, 'g', false),
  ((select id from recipes where name = 'Cheese Toast'), (select id from ingredients where canonical_name = 'tomato'), 1, 'pcs', false),
  ((select id from recipes where name = 'Cheese Toast'), (select id from ingredients where canonical_name = 'butter'), 10, 'g', false),
  ((select id from recipes where name = 'Cheese Toast'), (select id from ingredients where canonical_name = 'green chilli'), 1, 'pcs', true),
  ((select id from recipes where name = 'Capsicum Rice'), (select id from ingredients where canonical_name = 'rice'), 2, 'cups', false),
  ((select id from recipes where name = 'Capsicum Rice'), (select id from ingredients where canonical_name = 'capsicum'), 2, 'pcs', false),
  ((select id from recipes where name = 'Capsicum Rice'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Capsicum Rice'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Capsicum Rice'), (select id from ingredients where canonical_name = 'cooking oil'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Spinach Soup'), (select id from ingredients where canonical_name = 'spinach'), 400, 'g', false),
  ((select id from recipes where name = 'Spinach Soup'), (select id from ingredients where canonical_name = 'garlic'), 3, 'cloves', false),
  ((select id from recipes where name = 'Spinach Soup'), (select id from ingredients where canonical_name = 'milk'), 200, 'ml', false),
  ((select id from recipes where name = 'Spinach Soup'), (select id from ingredients where canonical_name = 'butter'), 15, 'g', true),
  ((select id from recipes where name = 'Frozen Peas Pulao'), (select id from ingredients where canonical_name = 'rice'), 2, 'cups', false),
  ((select id from recipes where name = 'Frozen Peas Pulao'), (select id from ingredients where canonical_name = 'frozen peas'), 150, 'g', false),
  ((select id from recipes where name = 'Frozen Peas Pulao'), (select id from ingredients where canonical_name = 'onion'), 1, 'pcs', false),
  ((select id from recipes where name = 'Frozen Peas Pulao'), (select id from ingredients where canonical_name = 'ghee'), 2, 'tbsp', false),
  ((select id from recipes where name = 'Frozen Peas Pulao'), (select id from ingredients where canonical_name = 'garam masala'), 1, 'tsp', false),
  ((select id from recipes where name = 'Curd Rice'), (select id from ingredients where canonical_name = 'rice'), 2, 'cups', false),
  ((select id from recipes where name = 'Curd Rice'), (select id from ingredients where canonical_name = 'curd'), 400, 'g', false),
  ((select id from recipes where name = 'Curd Rice'), (select id from ingredients where canonical_name = 'curry leaves'), 2, 'sprig', false),
  ((select id from recipes where name = 'Curd Rice'), (select id from ingredients where canonical_name = 'green chilli'), 1, 'pcs', false),
  ((select id from recipes where name = 'Curd Rice'), (select id from ingredients where canonical_name = 'cooking oil'), 1, 'tbsp', false),
  ((select id from recipes where name = 'Guava Chaat'), (select id from ingredients where canonical_name = 'guava'), 2, 'pcs', false),
  ((select id from recipes where name = 'Guava Chaat'), (select id from ingredients where canonical_name = 'lemon'), 0.5, 'pcs', false),
  ((select id from recipes where name = 'Guava Chaat'), (select id from ingredients where canonical_name = 'cumin'), 0.5, 'tsp', false),
  ((select id from recipes where name = 'Guava Chaat'), (select id from ingredients where canonical_name = 'salt'), 1, 'pinch', false),
  ((select id from recipes where name = 'Mango Lassi'), (select id from ingredients where canonical_name = 'mango'), 1, 'pcs', false),
  ((select id from recipes where name = 'Mango Lassi'), (select id from ingredients where canonical_name = 'curd'), 200, 'g', false),
  ((select id from recipes where name = 'Mango Lassi'), (select id from ingredients where canonical_name = 'sugar'), 2, 'tsp', false),
  ((select id from recipes where name = 'Mango Lassi'), (select id from ingredients where canonical_name = 'milk'), 100, 'ml', true),
  ((select id from recipes where name = 'Ghee Roast Paratha'), (select id from ingredients where canonical_name = 'atta'), 2, 'cups', false),
  ((select id from recipes where name = 'Ghee Roast Paratha'), (select id from ingredients where canonical_name = 'ghee'), 3, 'tbsp', false),
  ((select id from recipes where name = 'Ghee Roast Paratha'), (select id from ingredients where canonical_name = 'salt'), 1, 'pinch', false)
on conflict (recipe_id, ingredient_id) do nothing;


-- ==========================================================================
-- 012_seed_products.sql
-- ==========================================================================

-- GENERATED by supabase/seed/generate.py from supabase/seed/data.py
-- Do not edit. Change data.py and regenerate.

-- Seeded Indian FMCG barcodes. D1: no external API -- the cache ships
-- populated and grows whenever a user names an unknown barcode.
-- verified = true marks these as reference rows; user contributions are false.
insert into products (barcode, product_name, brand, ingredient_id, category,
  pack_size, verified) values
  ('8901030865278', 'Amul Taaza Toned Milk', 'Amul', (select id from ingredients where canonical_name = 'milk'), 'dairy'::food_category, '1 L', true),
  ('8901030700033', 'Amul Gold Full Cream Milk', 'Amul', (select id from ingredients where canonical_name = 'milk'), 'dairy'::food_category, '1 L', true),
  ('8901030815010', 'Amul Masti Dahi', 'Amul', (select id from ingredients where canonical_name = 'curd'), 'dairy'::food_category, '400 g', true),
  ('8901030612345', 'Amul Fresh Paneer', 'Amul', (select id from ingredients where canonical_name = 'paneer'), 'dairy'::food_category, '200 g', true),
  ('8901030500019', 'Amul Butter', 'Amul', (select id from ingredients where canonical_name = 'butter'), 'dairy'::food_category, '500 g', true),
  ('8901030410017', 'Amul Fresh Cream', 'Amul', (select id from ingredients where canonical_name = 'cream'), 'dairy'::food_category, '250 ml', true),
  ('8901030320019', 'Amul Cheese Slices', 'Amul', (select id from ingredients where canonical_name = 'cheese'), 'dairy'::food_category, '200 g', true),
  ('8901491101813', 'Aashirvaad Shudh Chakki Atta', 'Aashirvaad', (select id from ingredients where canonical_name = 'atta'), 'pantry'::food_category, '5 kg', true),
  ('8901491234567', 'Aashirvaad Select Atta', 'Aashirvaad', (select id from ingredients where canonical_name = 'atta'), 'pantry'::food_category, '10 kg', true),
  ('8906002501013', 'India Gate Basmati Rice', 'India Gate', (select id from ingredients where canonical_name = 'rice'), 'pantry'::food_category, '5 kg', true),
  ('8906002502010', 'India Gate Feast Rozzana', 'India Gate', (select id from ingredients where canonical_name = 'rice'), 'pantry'::food_category, '1 kg', true),
  ('8901719104568', 'Tata Salt', 'Tata', (select id from ingredients where canonical_name = 'salt'), 'pantry'::food_category, '1 kg', true),
  ('8901719110019', 'Tata Tea Premium', 'Tata', (select id from ingredients where canonical_name = 'tea'), 'pantry'::food_category, '500 g', true),
  ('8901058000023', 'Nescafe Classic', 'Nestle', (select id from ingredients where canonical_name = 'coffee'), 'pantry'::food_category, '100 g', true),
  ('8901063013016', 'Britannia Brown Bread', 'Britannia', (select id from ingredients where canonical_name = 'bread'), 'pantry'::food_category, '400 g', true),
  ('8901063092013', 'Britannia Whole Wheat Bread', 'Britannia', (select id from ingredients where canonical_name = 'bread'), 'pantry'::food_category, '400 g', true),
  ('8901725121013', 'Fortune Sunlite Refined Oil', 'Fortune', (select id from ingredients where canonical_name = 'cooking oil'), 'pantry'::food_category, '1 L', true),
  ('8901725133016', 'Fortune Kachi Ghani Mustard Oil', 'Fortune', (select id from ingredients where canonical_name = 'cooking oil'), 'pantry'::food_category, '1 L', true),
  ('8901030360015', 'Amul Pure Ghee', 'Amul', (select id from ingredients where canonical_name = 'ghee'), 'pantry'::food_category, '500 ml', true),
  ('8901396111114', 'Everest Garam Masala', 'Everest', (select id from ingredients where canonical_name = 'garam masala'), 'pantry'::food_category, '100 g', true),
  ('8901396222227', 'Everest Turmeric Powder', 'Everest', (select id from ingredients where canonical_name = 'turmeric'), 'pantry'::food_category, '200 g', true),
  ('8901396333330', 'Everest Jeera Whole', 'Everest', (select id from ingredients where canonical_name = 'cumin'), 'pantry'::food_category, '100 g', true),
  ('8901052041018', 'Tata Sampann Toor Dal', 'Tata Sampann', (select id from ingredients where canonical_name = 'toor dal'), 'pantry'::food_category, '1 kg', true),
  ('8901052052014', 'Tata Sampann Moong Dal', 'Tata Sampann', (select id from ingredients where canonical_name = 'moong dal'), 'pantry'::food_category, '1 kg', true),
  ('8901052063010', 'Tata Sampann Chana Dal', 'Tata Sampann', (select id from ingredients where canonical_name = 'chana dal'), 'pantry'::food_category, '1 kg', true),
  ('8901052074016', 'Tata Sampann Besan', 'Tata Sampann', (select id from ingredients where canonical_name = 'besan'), 'pantry'::food_category, '500 g', true),
  ('8901764012341', 'Madhur Pure Sugar', 'Madhur', (select id from ingredients where canonical_name = 'sugar'), 'pantry'::food_category, '1 kg', true),
  ('8904004400014', 'Safal Frozen Green Peas', 'Safal', (select id from ingredients where canonical_name = 'frozen peas'), 'frozen'::food_category, '500 g', true),
  ('8904004411010', 'Safal Frozen Mixed Vegetables', 'Safal', (select id from ingredients where canonical_name = 'frozen vegetables'), 'frozen'::food_category, '500 g', true),
  ('8901058853018', 'Nestle A+ Slim Milk', 'Nestle', (select id from ingredients where canonical_name = 'milk'), 'dairy'::food_category, '1 L', true),
  ('8901262010016', 'Mother Dairy Toned Milk', 'Mother Dairy', (select id from ingredients where canonical_name = 'milk'), 'dairy'::food_category, '500 ml', true),
  ('8901262021012', 'Mother Dairy Dahi', 'Mother Dairy', (select id from ingredients where canonical_name = 'curd'), 'dairy'::food_category, '400 g', true),
  ('8901262032019', 'Mother Dairy Paneer', 'Mother Dairy', (select id from ingredients where canonical_name = 'paneer'), 'dairy'::food_category, '200 g', true),
  ('8901262043015', 'Mother Dairy Butter', 'Mother Dairy', (select id from ingredients where canonical_name = 'butter'), 'dairy'::food_category, '100 g', true),
  ('8901396444443', 'Everest Kasuri Methi', 'Everest', (select id from ingredients where canonical_name = 'kasuri methi'), 'pantry'::food_category, '25 g', true),
  ('8906010500011', 'Nutraj Cashew W240', 'Nutraj', (select id from ingredients where canonical_name = 'cashew'), 'pantry'::food_category, '250 g', true),
  ('8901719220015', 'Tata Sampann Poha', 'Tata Sampann', (select id from ingredients where canonical_name = 'poha'), 'pantry'::food_category, '500 g', true),
  ('8901012000018', 'Patanjali Jaggery', 'Patanjali', (select id from ingredients where canonical_name = 'jaggery'), 'pantry'::food_category, '500 g', true),
  ('8904004422016', 'Safal Frozen Paratha', 'Safal', (select id from ingredients where canonical_name = 'frozen paratha'), 'frozen'::food_category, '5 pcs', true),
  ('8901058111117', 'Nestle Milkmaid', 'Nestle', (select id from ingredients where canonical_name = 'milk'), 'dairy'::food_category, '400 g', true)
on conflict (barcode) do nothing;
