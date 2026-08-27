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
