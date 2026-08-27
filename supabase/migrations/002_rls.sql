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
