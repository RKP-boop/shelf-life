# ShelfLife Supabase Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete ShelfLife backend on Supabase — ten tables, row-level security, indexes sized to the PRD's performance targets, two query functions, and seeded reference data — verified against the live project with two real users.

**Architecture:** Versioned SQL migrations applied through the dashboard SQL editor (the publishable key cannot run DDL). Reference data is generated from Python source rather than hand-written SQL, so ~60 ingredients, ~180 aliases and ~40 recipes stay reviewable and regenerable. Recipe matching lives in SQL because FR-07 ranks by ingredient availability, which is a join against inventory; expiry estimation and receipt parsing stay on-device in Dart (Plan 3) because they must work offline.

**Tech Stack:** PostgreSQL 15 (Supabase), PostgREST, `pg_trgm`, Python 3.12 for seed generation.

**Spec:** `docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md`

## Global Constraints

- **Project:** `iodzysmxzjfqbrvktzgc` — `https://iodzysmxzjfqbrvktzgc.supabase.co`. Verified empty: no `public` tables exist yet.
- **Credentials:** publishable/anon key only. **Never** request or use the service-role key — it bypasses RLS and would make the isolation test pass falsely.
- **RLS on every user-owned table**, with `auth.uid()` as the only scope. No table exposes another user's rows (BR-05).
- **Reference tables are read-only to clients**: `ingredients`, `ingredient_aliases`, `recipes`, `recipe_ingredients`. Seeded by migration, never written by the app.
- **`products` is the one shared writable table** (D1: the barcode cache "grows every time a user names an unknown barcode"). Insert-only for authenticated users, no update or delete.
- **Hard delete only** on `inventory_items` (D7 / BR-02). No soft-delete column, no restore path.
- **No `household_id`** anywhere (D6).
- **Performance targets** from PRD 5.13: inventory search <1 s, dashboard load <2 s. Every query the app runs on open must be index-backed.
- **Positive framing (Principle 3)** applies to *derived* values, not stored ones. The schema records `removed` events because FR-09's "94% used before expiry" is not computable without them; no view or function ever returns a "wasted" count.
- Money is `numeric(10,2)`, always an **estimate** — the UI must label it so.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/001_schema.sql` | Extensions, enums, ten tables, FKs, the `updated_at` trigger |
| `supabase/migrations/002_rls.sql` | RLS enabled + policies for every table |
| `supabase/migrations/003_indexes.sql` | Indexes derived from the app's actual query shapes |
| `supabase/migrations/004_functions.sql` | `match_recipes()`, `kitchen_stats()` |
| `supabase/seed/data.py` | Python source of truth for reference data — the reviewable artefact |
| `supabase/seed/generate.py` | Emits `010_seed_*.sql` from `data.py` |
| `supabase/migrations/010_seed_ingredients.sql` | Generated |
| `supabase/migrations/011_seed_recipes.sql` | Generated |
| `supabase/migrations/012_seed_products.sql` | Generated |
| `supabase/APPLY.md` | Exact paste order for the dashboard, plus what to switch off for verification |
| `tools/verify_backend.py` | End-to-end verification against the live project |

---

### Task 1: Schema

**Files:** Create `supabase/migrations/001_schema.sql`

**Interfaces:**
- Produces: enums `storage_location`, `food_category`, `expiry_source`, `item_status`, `consumption_kind`, `shopping_source`, `notification_level`; tables `profiles`, `ingredients`, `ingredient_aliases`, `products`, `recipes`, `recipe_ingredients`, `inventory_items`, `consumption_events`, `shopping_list_items`, `notifications`.

- [ ] **Step 1: Write the migration.** Table order must satisfy FK dependencies: `ingredients` → `ingredient_aliases`/`products`, `recipes` → `recipe_ingredients`, and `recipes` before `consumption_events` (which references it for "used via this recipe").
- [ ] **Step 2:** `notifications` carries `unique (inventory_item_id, level)`. That constraint **is** the BR-04 dedup guarantee — "one reminder per item per level" is enforced by the database, not by app logic.
- [ ] **Step 3:** `profiles.id` references `auth.users(id) on delete cascade`, plus a trigger to create the row on signup so the app never has to.
- [ ] **Step 4:** `updated_at` trigger on `inventory_items` only — it is the sole table the sync queue reconciles by timestamp (PRD 5.8, last-write-wins).
- [ ] **Step 5: Commit.**

### Task 2: Row-level security

**Files:** Create `supabase/migrations/002_rls.sql`

- [ ] **Step 1:** `alter table … enable row level security` on all ten tables. A table with RLS enabled and no policy denies everything — that is the safe default, so policies are added deliberately per table.
- [ ] **Step 2:** User-owned tables (`profiles`, `inventory_items`, `consumption_events`, `shopping_list_items`, `notifications`): four policies each (select/insert/update/delete) all scoped `user_id = auth.uid()`, with `with check` on insert and update so a row cannot be written *to* another user either.
- [ ] **Step 3:** Reference tables: a single `select` policy `to authenticated using (true)`. No insert/update/delete policy exists, so writes are refused.
- [ ] **Step 4:** `products`: `select` for authenticated, `insert` with `check (contributed_by = auth.uid())`. No update or delete — a shared catalogue that any user could edit or delete is a data-integrity risk, and D1 only requires *growth*.
- [ ] **Step 5: Commit.**

### Task 3: Indexes

**Files:** Create `supabase/migrations/003_indexes.sql`

Each index must trace to a query the app actually runs. Speculative indexes cost write throughput.

- [ ] **Step 1:** `inventory_items (user_id, status, expiry_date)` — the inventory list and the "use these first" home row, both sorted by urgency.
- [ ] **Step 2:** `inventory_items (user_id, ingredient_id) where status = 'active'` — partial index for recipe matching and shopping-list suppression.
- [ ] **Step 3:** `pg_trgm` GIN index on `inventory_items (product_name)` for FR-02 substring search under 1 s. Plain btree cannot serve `%term%`.
- [ ] **Step 4:** `consumption_events (user_id, occurred_at desc)` for the stats window; `shopping_list_items (user_id, purchased)`; `recipe_ingredients (ingredient_id)` for reverse lookup; `notifications (user_id, scheduled_for) where delivered_at is null`.
- [ ] **Step 5: Commit.**

### Task 4: Query functions

**Files:** Create `supabase/migrations/004_functions.sql`

**Interfaces:**
- Produces: `match_recipes(p_limit int)` returning `(recipe_id, name, prep_minutes, total_required, have_count, missing_names, urgent_names, score)`; `kitchen_stats()` returning a single JSON object.

- [ ] **Step 1: `match_recipes`.** Implements the spec §5.2 formula exactly:
  `0.6·(have/total) + 0.3·urgency + 0.1·speed`, where `urgency = max(0, 1 − daysToExpiry/3)` over matched items and `speed = max(0, 1 − prep/60)`. Counts **non-optional** ingredients only.
- [ ] **Step 2:** It must return `missing_names` and `urgent_names` as arrays, not just the score. Two hard UI constraints depend on this: the score is never rendered ("7 of 9 ingredients" instead), and screen 33 must name *which* urgent items a recipe uses.
- [ ] **Step 3:** `security invoker` on both functions so RLS applies and `auth.uid()` resolves to the caller. `security definer` would leak every user's inventory through one RPC.
- [ ] **Step 4: `kitchen_stats`.** Returns active count, expiring-soon count, estimated value rescued this month, meals rescued, current streak, and percent used in time. Streak = consecutive days ending today or yesterday with ≥1 `used` event.
- [ ] **Step 5: Commit.**

### Task 5: Reference data

**Files:** Create `supabase/seed/data.py`, `supabase/seed/generate.py`; generate `010`–`012`.

- [ ] **Step 1: `data.py`.** Python lists/dicts as the source of truth — ~60 ingredients with per-storage shelf life and estimated price, ~180 aliases, ~40 Indian recipes with structured ingredients and method steps, ~40 seeded barcodes. Reviewing 40 recipes as Python data is tractable; reviewing them as hand-written SQL is not.
- [ ] **Step 2:** Every ingredient's `glyph_key` must match a component that exists in the Figma library (23 real renders + category fallbacks), so the app never requests an image that isn't there.
- [ ] **Step 3: `generate.py`.** Emits idempotent SQL: `insert … on conflict do nothing`, and resolves ingredient names to IDs via subquery rather than hardcoded UUIDs, so the seed can be re-run safely.
- [ ] **Step 4: Verify.** Assert every recipe ingredient resolves to a real ingredient name and every alias target exists — before the SQL reaches the database.
- [ ] **Step 5: Commit.**

### Task 6: Apply and verify

**Files:** Create `supabase/APPLY.md`, `tools/verify_backend.py`

- [ ] **Step 1: `APPLY.md`** — paste order, and the one setting to change: *Authentication → Sign In / Providers → Email → Confirm email* off, so verification can create throwaway users.
- [ ] **Step 2:** User applies the migrations.
- [ ] **Step 3: `verify_backend.py`** — checks, in order:
  1. all ten tables reachable
  2. reference data counts match the generator
  3. **anonymous requests return no rows** from user tables
  4. two users created; user A's inventory invisible to user B — the RLS test that matters
  5. reference tables reject writes
  6. `products` accepts an insert but rejects an update
  7. `match_recipes` returns sensible ranking for a seeded inventory, and includes `missing_names`
  8. `kitchen_stats` returns every key the dashboard needs
  9. `notifications` unique constraint rejects a duplicate level
- [ ] **Step 4:** Run it. Fix anything it catches.
- [ ] **Step 5: Commit.**

---

## Self-Review

**Spec coverage.** Spec §4's ten tables → Task 1. §3's canonical-identity pair → Task 5. §5.2's scorer → Task 4 Step 1. §9's RLS criterion ("two real users, asserting A cannot read B's rows") → Task 6 Step 3.4. Decisions D1, D5, D6, D7, D8 each appear as a Global Constraint and in the task that implements them.

**Deliberately out of scope.** The expiry estimator (§5.1) and receipt parser (§5.3) are **on-device Dart**, not SQL — they must run offline, which a database function cannot. They belong to Plan 3. The Hive sync queue is likewise client-side.

**Type consistency.** `food_category` values match the app's five categories plus `other`. `storage_location` matches the four chips on screen 23. `expiry_source` matches spec §5.1's four-level precedence. `consumption_kind` is `used | removed`, matching the delete-confirm copy *"this won't count as rescued"*.

**Known risk, stated.** `products` being client-writable is D1's explicit consequence. Mitigations: insert-only, `contributed_by` recorded, and a `verified` flag distinguishing seeded rows from user contributions. If the catalogue is ever abused, the fix is moderation on `verified`, not a schema change.
