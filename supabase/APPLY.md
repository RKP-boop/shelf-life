# Applying the ShelfLife backend

**Project:** `iodzysmxzjfqbrvktzgc` → https://supabase.com/dashboard/project/iodzysmxzjfqbrvktzgc

The publishable key cannot run DDL, so migrations go through the dashboard's SQL Editor. Nothing here needs the Supabase CLI or your database password.

---

## Step 1 — one setting first

**Authentication → Sign In / Providers → Email → turn *Confirm email* OFF.**

Without this, verification cannot create throwaway users (I can't click confirmation links), and the RLS isolation test — the one that actually matters — can't run. Standard for a dev project, and reversible in one click before you ship.

Two things I do **not** need, and you should not paste anywhere: the **service-role key** and your **database password**. The service-role key bypasses RLS, which would make the isolation test pass falsely.

---

## Step 2 — run the migrations in order

Open **SQL Editor → New query**, then paste and run each file. Order matters: foreign keys require `ingredients` and `recipes` to exist before the tables that reference them.

| # | File | What it does |
|---|---|---|
| 1 | `migrations/001_schema.sql` | `pg_trgm`, 7 enums, 10 tables, the signup trigger |
| 2 | `migrations/002_rls.sql` | RLS on all 10 tables + 24 policies |
| 3 | `migrations/003_indexes.sql` | 9 indexes |
| 4 | `migrations/004_functions.sql` | `match_recipes()`, `kitchen_stats()` |
| 5 | `migrations/010_seed_ingredients.sql` | 65 ingredients, 153 aliases |
| 6 | `migrations/011_seed_recipes.sql` | 40 recipes, 223 ingredient rows |
| 7 | `migrations/012_seed_products.sql` | 40 barcodes |

Or paste **`migrations/ALL.sql`** once — the same seven files concatenated in order.

Every seed statement is `on conflict do nothing`, so re-running is safe. Ingredient IDs are resolved by name, never hardcoded.

---

## Step 3 — tell me, and I verify

```
python tools/verify_backend.py
```

It checks, in order:

1. all ten tables reachable
2. seeded counts match the generator exactly
3. **anonymous requests return no rows** from user tables
4. two throwaway users created; **user A's inventory invisible to user B**
5. reference tables reject writes
6. `products` accepts an insert, rejects an update
7. `match_recipes` ranks a seeded inventory sensibly and returns `missing_names`
8. `kitchen_stats` returns every key the dashboard reads
9. the `notifications` unique constraint rejects a duplicate level

---

## If a statement fails

Report the error verbatim rather than editing the SQL — the migrations are generated and version-controlled, so a fix belongs in `supabase/seed/data.py` or the migration file, not in the editor.

**To start over:** `drop schema public cascade; create schema public;` then re-run from step 2. This destroys all data in `public` and does not touch `auth.users`, so previously created test users survive.
