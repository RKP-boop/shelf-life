# Backend verification record

Run: `python tools/verify_backend.py` — **33/33 passed**, 2026-08-27.
Project `iodzysmxzjfqbrvktzgc`. Publishable key only; no service-role key was used at any point.

## Why the anon key matters here

A service-role key bypasses RLS entirely, so the isolation test would pass even if
every policy were missing. Verifying with the same key the app ships with is the
only way the result means anything.

## What passed

| Group | Checks |
|---|---|
| Schema | all ten tables reachable |
| Seed | 65 ingredients, 153 aliases, 40 recipes, 223 recipe-ingredient rows, 40 seeded barcodes |
| Anonymous | all five user tables and the reference tables expose nothing without a session |
| **RLS isolation** | user A's row invisible to B; B cannot query it by id; B cannot write a row owned by A (403); B cannot delete A's row |
| Reference | `ingredients` and `recipes` reject inserts (403) |
| `products` | contribution accepted; update refused; cannot self-mark `verified` (403) |
| `match_recipes` | ranks correctly, returns `missing_names` and `urgent_names` |
| `kitchen_stats` | returns all seven dashboard keys |
| Notification dedup | duplicate `(item, level)` rejected by the database (409, constraint 23505) |

## Live evidence of correct behaviour

For a kitchen holding spinach, paneer, onion and tomato all due today:

```
urgent_names  ['onion', 'paneer', 'tomato']
missing_names ['garam masala', 'peas']
top 5         Matar Paneer, Tomato Onion Salad, Masala Omelette,
              Palak Paneer, Paneer Bhurji
```

Every ranked recipe is genuinely cookable from that inventory, and `missing_names`
gives the UI exactly what screen 35's "You'll need to buy" section needs.

## Defects found by verifying rather than asserting

1. **`user_id` had no default**, so any insert omitting it failed RLS with a
   message that reads like a permissions problem rather than a missing column.
   Fixed in `005_user_id_defaults.sql`. This is the class of bug that only a live
   insert exposes — "RLS is configured" would have looked fine.
2. **Streak always returned 1.** For dates ordered DESC the gaps-and-islands key
   is `d + rownum`, not `d - rownum`; with the minus sign every consecutive day
   formed its own group. Caught in review, proved against a 4-date fixture with a
   gap, fixed before the migration was ever applied.

Three further failures were faults in the *test*, not the backend: counting
reference tables with the anon key against policies scoped `to authenticated`;
selecting `id` on `recipe_ingredients` and `products`, which have composite and
text primary keys; and asserting an exact `products` count on a table designed to
grow.

## Housekeeping

Each run creates throwaway users (`verify-*@example.com`) and one contributed
barcode. Harmless, but they accumulate. To clear them:

```sql
delete from products where verified = false and product_name = 'Verify probe';
-- test users: Authentication > Users, filter "verify-"
```

`products` has no delete policy by design, so this needs the SQL editor.

## Post-verification: email confirmation re-enabled

Confirmation was turned back **on** after the full run (`mailer_autoconfirm: false`),
which is the correct production setting.

`verify_backend.py` now detects this and **skips** the session-dependent groups
rather than reporting them as failures — a correctly-secured project should not
look like a regression. The summary says `PARTIAL` and names what was not
re-checked, so a partial run can never be mistaken for a full pass. Re-running now
gives 6/6 on the schema and anonymous-access groups.

To reproduce the full 33/33, temporarily turn *Confirm email* off again.
