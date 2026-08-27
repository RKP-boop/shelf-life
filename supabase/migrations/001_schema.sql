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
