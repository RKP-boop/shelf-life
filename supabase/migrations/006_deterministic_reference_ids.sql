-- Deterministic ids for seeded reference data.
--
-- The problem this fixes
-- ----------------------
-- `ingredients.id` and `recipes.id` defaulted to gen_random_uuid(). That is
-- correct for user data and wrong for seeded reference data, because the app
-- is offline-first: it ships the same catalogue in Hive and must be able to
-- write `inventory_items.ingredient_id` on a phone that has never reached the
-- server. With server-assigned random ids the client cannot know them, so
-- every queued insert would fail its foreign key on the first sync.
--
-- The fix
-- -------
-- Reference rows become content-addressed: the id is derived from the natural
-- key, so Postgres and Dart independently compute the same uuid.
--
--     ingredients.id = md5(canonical_name)::uuid
--     recipes.id     = md5(lower(name))::uuid
--
-- md5-as-uuid rather than uuid_generate_v5 deliberately: v5 needs the
-- uuid-ossp extension, and the property being relied on here is only
-- determinism, not RFC-4122 version semantics. `products` already keys on
-- barcode, which is deterministic by nature, so it needs nothing.
--
-- Why `on update cascade`
-- -----------------------
-- The ids have to change in place, and Postgres checks parent-side FKs
-- immediately. Adding `on update cascade` lets one UPDATE on the parent carry
-- every child with it, instead of a deferred-constraint dance or a
-- delete-and-reinsert that would lose user rows. It is also simply the right
-- declaration for a key that is derived rather than surrogate.
--
-- Idempotent: re-running recomputes the same values and changes nothing.

begin;

-- ---------------------------------------------------------------- FKs

alter table recipe_ingredients
  drop constraint recipe_ingredients_ingredient_id_fkey,
  add constraint recipe_ingredients_ingredient_id_fkey
    foreign key (ingredient_id) references ingredients (id)
    on delete cascade on update cascade;

alter table recipe_ingredients
  drop constraint recipe_ingredients_recipe_id_fkey,
  add constraint recipe_ingredients_recipe_id_fkey
    foreign key (recipe_id) references recipes (id)
    on delete cascade on update cascade;

alter table inventory_items
  drop constraint inventory_items_ingredient_id_fkey,
  add constraint inventory_items_ingredient_id_fkey
    foreign key (ingredient_id) references ingredients (id)
    on delete set null on update cascade;

alter table products
  drop constraint products_ingredient_id_fkey,
  add constraint products_ingredient_id_fkey
    foreign key (ingredient_id) references ingredients (id)
    on delete set null on update cascade;

alter table shopping_list_items
  drop constraint shopping_list_items_ingredient_id_fkey,
  add constraint shopping_list_items_ingredient_id_fkey
    foreign key (ingredient_id) references ingredients (id)
    on delete set null on update cascade;

alter table shopping_list_items
  drop constraint shopping_list_items_source_recipe_id_fkey,
  add constraint shopping_list_items_source_recipe_id_fkey
    foreign key (source_recipe_id) references recipes (id)
    on delete set null on update cascade;

alter table consumption_events
  drop constraint consumption_events_ingredient_id_fkey,
  add constraint consumption_events_ingredient_id_fkey
    foreign key (ingredient_id) references ingredients (id)
    on delete set null on update cascade;

alter table consumption_events
  drop constraint consumption_events_recipe_id_fkey,
  add constraint consumption_events_recipe_id_fkey
    foreign key (recipe_id) references recipes (id)
    on delete set null on update cascade;

-- ------------------------------------------------------------ rewrite

update ingredients
   set id = md5(canonical_name)::uuid
 where id is distinct from md5(canonical_name)::uuid;

update recipes
   set id = md5(lower(name))::uuid
 where id is distinct from md5(lower(name))::uuid;

-- --------------------------------------------------------- new defaults
--
-- So a row inserted later by the seed script lands on the same id without the
-- caller having to compute it.

alter table ingredients alter column id drop default;
alter table recipes     alter column id drop default;

commit;

-- ------------------------------------------------------------- checks
--
-- These raise rather than return a row, so running the file is itself the
-- verification. A silent no-op migration is how a broken FK reaches a phone.

do $$
declare
  bad_ingredients int;
  bad_recipes     int;
begin
  select count(*) into bad_ingredients
    from ingredients where id <> md5(canonical_name)::uuid;
  select count(*) into bad_recipes
    from recipes where id <> md5(lower(name))::uuid;

  if bad_ingredients > 0 then
    raise exception 'ingredients: % rows do not match md5(canonical_name)',
      bad_ingredients;
  end if;
  if bad_recipes > 0 then
    raise exception 'recipes: % rows do not match md5(lower(name))', bad_recipes;
  end if;

  raise notice 'reference ids are deterministic: % ingredients, % recipes',
    (select count(*) from ingredients), (select count(*) from recipes);
end $$;
