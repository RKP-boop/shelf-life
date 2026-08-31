# ShelfLife MVP — Design Specification

**Date:** 2026-08-24
**Status:** Awaiting review
**Target:** MVP v1.0, Android-first, Flutter + Hive + Supabase, offline-first

---

## 1. Source documents

This design reconciles three artefacts. Where they disagree, the resolution and its reasoning are recorded in §2.

| Source | Location | Authority |
|---|---|---|
| PRD v1.0 | `C:\Users\rakes\Downloads\ShelfLife-PRD.docx` | Requirements, business rules, tech stack |
| Screen prompts (visual direction v2) | `…\Documents\Codex\2026-08-10\shelflife-app-user-flow\outputs\ShelfLife-Stitch-Prompts.md` | Visual system, exact copy, 16 screens |
| MVP user-flow board (FigJam) | `figma.com/board/VtBS3Rn1WMO9kUvXWkVdV1` | Flow logic, decisions, edge cases |

The board is the most complete: 9 flows, 218 nodes, 170 connectors, with an explicit `[DECISION]` annotation layer.

---

## 2. Decision log

Each row records what was decided, why, and which source won.

| # | Decision | Resolution | Basis |
|---|---|---|---|
| D1 | Barcode lookup source | **Seeded local cache only, no external API.** Grows when a user names an unknown barcode. | Board `[DECISION]`: *"No paid barcode API… the flow stays fully offline."* Overrides an earlier preference for Open Food Facts. Keeps Flow 3 free of a network failure mode, satisfying Principle 6. |
| D2 | Recipe seed size | **~40 recipes now**, seed format designed so growth to ~100 is appending rows. | Board says ~100; 40 is the reviewable subset. Data-only change to expand — no schema or code impact. |
| D3 | Auth methods | **Email/password + guest mode live. Google button built, activated by config.** *(Superseded by D25: email removed, Google only.)* | PRD FR-01 says email. Board says email + password. Screen 02 makes Google primary. Building all three visually keeps screen 02 honest; Google needs OAuth credentials that do not exist yet, so it cannot be a blocker. |
| D4 | Fresh-state chip | **Fresh items render no chip.** Only two chips exist: amber "Use in N days", red "Best used today". | Screen doc v2 explicitly overrides the board legend's green chip and states the reason: green is the brand colour, so a green chip reads as decoration rather than information. Later document, reasoned override. |
| D5 | Recipe ingredient storage | **Normalised `recipe_ingredients` table.** `method_steps` stays JSON. | Departs from PRD §5.5 (`ingredients JSON`). FR-07 ranks by ingredient availability, which requires joining recipes against inventory; a JSON blob forces a full scan plus client-side parsing on every Recipes tab open, against a <2 s target. Steps are display-only and never queried, so JSON is correct for them. |
| D6 | Household sharing | **Out of scope. No `household_id` column.** | PRD 3.3 "Could Have"; screen 16 shows a "Coming soon" chip; BR-05 states inventory is unique per account. Pre-building it would be speculative schema requiring rework. |
| D7 | Deletion | **Hard delete, no soft-delete column.** | BR-02: *"Deleted inventory cannot be restored."* Board: *"BR-02: deletion is permanent, no undo."* |
| D8 | `notifications` table role | **Dedup ledger, not a delivery queue.** | The PRD chose `flutter_local_notifications` over Firebase, so delivery is device-local. The table exists to satisfy BR-04 and the board's *"One notification per item per level."* |
| D9 | Project location | `C:\src\shelflife` | Short path, no spaces, not OneDrive-synced. Windows Gradle builds hit `MAX_PATH` under deep user directories. |
| D10 | Android toolchain | **Deferred.** Flutter SDK only for now. | Rendering and verifying all 16 screens needs `flutter run -d windows`, not the Android SDK. JDK + Android SDK (~2 GB) are required only to produce an APK. Native plugins sit behind interfaces (§5), so the UI compiles on any target. |
| D11 | Amber chip text colour | **`#B26A00` → `#9E5D00`** | Measured: `#B26A00` on `#FFF3E0` is 3.86:1, failing WCAG AA (4.5 floor) at the 12sp Medium chip size, which does not qualify for the 3.0 large-text exemption. The screen doc's claim that "dark amber over pale amber passes" is incorrect. `#9E5D00` measures 4.76:1 — the smallest change that passes, chosen to preserve the intended hue. Darkening the tint instead was tested and makes the ratio worse. PRD 4.11 mandates AA. |
| D12 | `#A8B885` usage constraint | **Restricted to deep surfaces (`#2E3D0A`) only.** | Measured 5.51:1 on `#2E3D0A` but 3.91:1 on the `#44540E` canvas. Screen 02's 12sp small print is compliant only because it sits on the near-solid base of the gradient. The variable's scope and name encode this restriction so it cannot be misapplied. |
| D13 | Visual direction | **Retired the deep-olive system. Adopted a premium light/pastel direction** — pastel gradient canvas, near-white cards, emerald accent, dimensional produce, Plus Jakarta Sans. | The olive system came from `ShelfLife-Stitch-Prompts.md`, which the user rejected on review as "very green, no taste." A reference image now supersedes that document as the visual authority. Product scope is unchanged: same PRD, same nine-table backend, same tabs. The reference depicts a grocery-eCommerce app; the user confirmed ShelfLife's inventory scope stands, so no cart, checkout or payments were added. |
| D14 | Accent colour | **`#0A7A55`, not the reference's `#0E9E6E`.** | Measured: white text on `#0E9E6E` is 3.42:1, failing WCAG AA. Every primary CTA in the app would have been non-compliant against PRD 4.11. `#0A7A55` measures 5.35:1 with white text and 4.81–4.92:1 as text on the light surfaces, so one token serves both roles. |
| D15 | Screen count | **52 screens, not 16.** | The original 16 were the flow board's spine only — the screen doc admits as much. An audit against all 9 flows found the barcode scanner missing entirely (FR-04 is a Must-Have), Flow 6 with zero screens despite expiry reminders being the product's purpose, no edit-item screen despite BR-01, and no delete confirmation despite BR-02 being irreversible. Also, screen 01's three page dots implied three value props; only one existed. |
| D16 | Produce imagery | **Gradient-vector illustrations approximating 3D**, each a swappable component. | True Blender-style renders cannot be generated here. Layered gradients, blurred speculars and contact shadows carry the dimensional read; layouts are unaffected when real renders replace them. |
| D17 | Typeface | **Plus Jakarta Sans.** | Matches the reference's geometric character. Poppins was the closer literal match but is among the most overused UI faces and reads as templated — an anti-slop consideration. |
| D18 | Reference ids | **`ingredients.id = md5(canonical_name)`, `recipes.id = md5(lower(name))`** (migration 006), replacing `gen_random_uuid()`. | Found while wiring sync. The app is offline-first, so it writes `inventory_items.ingredient_id` on a phone that may never have reached the server. With server-assigned random ids the client cannot know them and every queued insert fails its foreign key on first sync — on a real device, after the user has already added their shopping. Content-addressing the seeded reference data lets Postgres and Dart derive the same value independently. FKs gained `on update cascade` so the ids could be rewritten in place without losing user rows. |
| D19 | APK distribution | **`--split-per-abi`, and `arm64-v8a` is the one to send.** Minification stays off. | The universal APK is 109 MB: three architectures each carrying the Flutter engine (~11 MB), the bundled ML Kit OCR pipeline (~11 MB) and libapp (~7 MB). Splitting cuts that to roughly a third. R8 was left off deliberately — ML Kit resolves model classes reflectively, and the failure mode of a wrong keep-rule is a release build where OCR silently returns nothing, which only shows up after shipping. A few MB is the cheaper side of that trade. |
| D20 | The reminder ledger's row shape | **Built via `ScheduledNotification.toJson()`, never a hand-written map.** | `ReminderService` and `InventoryRepository` both use the `notifications` box. The first version hand-built the map with `level: "threeDay"` and no `id`; it wrote fine and threw a cast error on read. Constructing the model makes the two shapes the same by definition rather than by agreement. Caught by `app_state_test.dart`, which is the only test that exercises both sides of that box. |
| D21 | Launch verification | **Every build is installed and launched on a device before it is called done**, and `tools/audit_apk.py` resolves the manifest's launcher activity against the dex. | The first APK handed over did not open. `applicationId` and `namespace` had been renamed to `com.shelflife.app` while `MainActivity.kt` stayed in `com.shelflife.shelflife_app`, so the manifest's `.MainActivity` pointed at a class that was not in the APK. It compiled, analyzed clean, passed 211 tests, packaged, installed — and died with `ClassNotFoundException` before drawing a frame. Nothing that stops at the Dart layer can see this class of fault, so the guard has to run on the artefact itself. `main()` is now wrapped as well: a throw between `ensureInitialized` and `runApp` shows a screen naming the cause instead of the process vanishing silently. |
| D22 | Barcode lookup | **Open Food Facts, cache-first. Supersedes D1.** | D1 made the seeded 40 barcodes the only lookup path because no API had been chosen. In use that meant scanning anything else asked the user to type it in, every time — which they reported as the feature not working. Open Food Facts is free, needs no key, and is open data. Order is cache, then network, then ask: the local box answers instantly and offline, the network only on a miss, with a 6-second timeout because the user is holding a packet up to a camera. A network hit is cached locally and queued to the shared `products` table, which is what finally makes screen 22's "we will remember it" true for everyone rather than one phone. Looked-up rows are never `verified` — that column exists so contributed data cannot masquerade as seeded. |
| D23 | CI signing | **A release keystore is required for CI, not optional.** | Google sign-in failed on the first CI build. Without a keystore Gradle falls back to a debug key, and a GitHub runner generates its *own* debug keystore — the APK was signed with `65:43:FC:15…`, nothing like the local `18:98:3E:8B…` that was registered with Google. An Android OAuth client is bound to one certificate, so a debug-signed CI build can never pass Google sign-in whichever SHA-1 you register. `tools/upload_signing_secrets.py` pushes the keystore to Actions without the password passing through a transcript. |
| D24 | Email confirmation | **A six-digit code typed into the app, not the default magic link.** | The link flow is not merely less pleasant here, it is broken: tapping it confirms the account in a browser and the app never learns, so it waits on the confirmation screen forever. Closing that loop needs an Android App Link — a domain, a hosted `assetlinks.json`, manifest filters — to return someone to an app they never meant to leave. A code needs one template change and no infrastructure, and matches what people in India already expect. Guest rows are adopted at verification rather than at sign-up: an unconfirmed account may never be confirmed, and moving a kitchen onto it early would strand it. Requires `{{ .Token }}` in the Confirm-signup template. **Superseded by D25: that template cannot be edited on this project.** |
| D25 | Account path | **Google sign-in only. Email sign-up removed entirely. Supersedes D24.** | D24 assumed the Confirm-signup template could be edited to carry `{{ .Token }}`. It cannot: Supabase gates template editing behind custom SMTP, and the default template contains a confirmation link with no token — so the six-digit code the app asked for could never be sent. Checked in the dashboard rather than assumed, and the magic-link template is identical and equally locked. Worse, the project-wide send limit is **2 emails per hour** and that field is locked too, so even the broken link flow would fail for the third person to try it within an hour. Google sign-in sends no email and is unaffected, which makes it the only path that scales to "anyone can download and install this". The alternative was free third-party SMTP (Brevo, 300/day), rejected because it needs the user to hold an account and a credential on another service to fix something Google already solves. Guest mode remains, and is promoted to the primary button on any build without an OAuth client id — a welcome screen whose only action is a text link reads as broken. |

---

## 3. Keystone: canonical ingredient identity

Three input paths must resolve to one identity before anything else works:

- OCR emits `AMUL TAAZA TONED MILK 500ML`
- the user types `Spinach`
- a recipe references `palak`

Two seeded tables provide that resolution:

- **`ingredients`** — canonical catalogue: `canonical_name`, `category`, `default_unit`, `glyph_key`, per-storage `shelf_life_days`, `est_price_inr`
- **`ingredient_aliases`** — `palak → spinach`, `toned milk → milk`, `amul taaza → milk`

This single pair drives six features: receipt parsing, barcode categorisation, expiry estimation, glyph selection, recipe matching, and the shopping-list suppression on screen 15 (*"You already have onions and rice — we've left them off"*). Without it each of those needs its own fuzzy-match implementation, and they drift apart.

`est_price_inr` is required because screen 04 shows "₹1,240 Saved this month" and screen 16 says *"about ₹1,240 you didn't throw away"*. Seeded with approximate Indian market rates, overridden by a receipt-captured price when OCR provides one. **Always labelled as an estimate in the UI** — never presented as a measured figure.

---

## 4. Data model

Ten tables. PRD §5.5 specifies five; the additions and their justifications are below.

| Table | Origin | Purpose |
|---|---|---|
| `profiles` | PRD `Users` | Mirrors `auth.users` |
| `ingredients` | **new** (§3) | Canonical catalogue, seeded, globally readable |
| `ingredient_aliases` | **new** (§3) | Alias → canonical resolution, seeded |
| `products` | **new** | Barcode cache. Screen 09 promises *"we'll remember it for next time"*; D1 makes this the sole lookup path |
| `inventory_items` | PRD `Inventory` | Adds `ingredient_id` FK, `expiry_source` enum (`user` / `printed` / `estimated` / `category_default`), `expiry_reason` text, `status` (`active` / `consumed`) |
| `consumption_events` | **new** | Required by FR-09. "Money saved", "food rescued", "current streak" and screen 16's "94% used before expiry" are not computable from a mutable inventory row, because the row is gone once consumed |
| `recipes` | PRD `Recipes` | `method_steps` JSON; ingredients normalised out (D5) |
| `recipe_ingredients` | **new** (D5) | `recipe_id`, `ingredient_id`, `qty`, `unit`, `optional` |
| `shopping_list_items` | PRD `Shopping List` | Adds `source` enum (`manual` / `ran_out` / `recipe`) + `source_recipe_id` — screen 15 renders "Added from Palak Paneer" vs "You've run out", so the caption *is* the enum |
| `notifications` | PRD `Notifications` | Dedup ledger (D8) |

*(Earlier drafts of this section said "nine"; the list has always had ten rows.)*

**Row-level security.** Every user-owned table carries `user_id` with an RLS policy restricting all operations to `auth.uid()`. `ingredients`, `ingredient_aliases` and `recipes` are global read-only reference data. Satisfies BR-05 and the board's *"Row-level security scopes every row to user_id."*

---

## 5. Three pure engines

Isolated, no I/O, unit-testable without a device or emulator. This is what makes the project verifiable in the current environment.

### 5.1 Expiry estimator

`(ingredient, storage, purchaseDate, printedExpiry?) → (date, source, reason)`

Precedence, per FR-05 and the board's Flow 6:

1. User override → `source: user`. BR-01: *"user value always wins."*
2. Printed date from pack or receipt → `source: printed`
3. Per-item shelf life for the storage location → `source: estimated`
4. Category fallback → `source: category_default`

Returns a **reason string**, which is what lets screen 12 render *"You bought this five days ago, and fresh greens keep about six."* Principle 4 requires the estimate to explain itself, so the explanation is a return value rather than UI copy. The board states this as *"Freshness status computed — Green · Amber · Red, plus a plain-English reason."*

Thresholds from the board: amber at 3 days out, red on the day. Per D4, fresh returns no chip at all.

### 5.2 Recipe scorer

`score = 0.6·(have/total) + 0.3·urgency + 0.1·speed`

where, over the recipe's ingredients matched in active inventory:

- `have/total` counts non-optional ingredients only
- `urgency = max(0, 1 − daysToExpiry / 3)` taken over matched items, so an item due today scores 1.0 and anything 3+ days out scores 0
- `speed = max(0, 1 − prepTimeMinutes / 60)`

Weights are ordered to match FR-07's stated priority — availability, then expiry urgency, then preparation time.

Two hard constraints, both from the source documents:

- **The score orders the list and is never rendered.** Screen doc: *"Bare match scores. '78% match' is meaningless."* Board: *"Match score is explained, never a bare number."* The UI shows "7 of 9 ingredients".
- The query must return **which** urgent ingredients matched, so screen 13 can say *"Uses your spinach and paneer, both best used today."*

Quick Meals filter = prep time under 20 minutes (board).

### 5.3 Receipt parser

Line → normalise → strip quantity/unit/price tokens → **filter non-grocery lines** (totals, GST, store name — an explicit board requirement) → fuzzy-match against `ingredient_aliases` → confidence score.

Below the confidence threshold, the row surfaces screen 08's "Needs your input" chip rather than guessing. Testable against fixture receipt text with no camera involved.

---

## 6. Offline behaviour and sync

Hive is the source of truth; Supabase is a backup and sync channel. Board: *"Local storage is the source of truth; the cloud is a backup and a sync channel."*

- Every write goes to Hive first, then appends an operation to a Hive sync queue
- On reconnect the queue **drains in original order** (board), with retry and backoff; operations stay queued on failure
- Conflict resolution: latest edit wins, **both timestamps retained for audit** (board, PRD 5.8)
- Sync status is a subtle header icon, never a blocking spinner (PRD 4.8)
- Guest mode has **no cloud leg at all**. Upgrade re-keys local Hive rows to the new `user_id` and pushes them — zero data loss
- A persistent Home banner ("Save my kitchen") states plainly that uninstall means data loss
- Sign out clears the local cache (BR-05)

Native capabilities — ML Kit OCR, `mobile_scanner`, `flutter_local_notifications` — sit behind interfaces with fake implementations, so all 16 screens compile and render on desktop for verification while the real plugins are used on Android.

---

## 7. Module layout

Feature-first, exactly as PRD §5.4 specifies:

```
lib/
├── core/          constants, themes, utilities, services
├── features/      authentication, inventory, scanner, recipes,
│                  shopping, dashboard, profile
├── models/
├── repositories/
├── database/
└── main.dart
```

---

## 8. Design pipeline

The Figma MCP server exposes write tools, so screens are authored natively in Figma rather than mocked elsewhere.

1. Create a Figma **design** file in `rakeshpathak.pgp25's team`, alongside the existing flow board — the screen doc's "After generation" section asks for flow and screens side by side
2. Build the design system first as Figma variables: the exact palette (`#44540E` canvas, `#2E3D0A` deep surfaces, `#5A6B1A` accent, `#E8EFE0` frosted, `#1A2408` / `#5F6B45` text, amber `#B26A00` on `#FFF3E0`, red `#C62828` on `#FDECEA`), Inter type ramp, 8 dp spacing, 24 dp card radius
3. Author the 16 screens at 412 × 915 dp
4. Derive the Flutter theme from the same token values, so Figma and code cannot drift

Verification order taken from the screen doc's own checklist: field completeness against the flow, empty and error states present as real screens, contrast audit on every frosted surface, one mockup per named screen.

---

## 9. Verification plan

Success criteria, each independently checkable:

1. `dart test` green on all three engines in §5 — written test-first
2. `flutter run -d windows` renders all 16 screens; each screenshotted and compared against the screen doc's stated values
3. **Automated WCAG AA contrast assertion** over every foreground/background pair in the theme. The screen doc warns this direction is *"the most beautiful of the options and the easiest to fail AA with"*, so this is asserted in tests rather than eyeballed
4. **Golden test asserting fresh items render no chip.** The screen doc predicts every generator re-adds them; a golden test makes the regression impossible
5. **RLS verified against the live Supabase project** with two real users, asserting A cannot read B's rows. Asserting isolation is not the same as testing it
6. Offline path: airplane-mode write → queue → reconnect → drain in order

---

## 10. Out of MVP scope

Per PRD 3.2 and the board's "Future state" lane: grocery ordering, payments, AI image recognition, voice input, smart-fridge integration, nutrition tracking, household sharing, carbon-footprint tracking, predictive purchasing, dietary and allergy filters, quick-commerce handoff, per-field merge conflict resolution.

---

## 11. Known risks

| Risk | Mitigation |
|---|---|
| OCR accuracy varies by receipt | Every row editable before saving (screen 08); confidence threshold routes low-certainty rows to explicit user input |
| Seeded barcode cache has low first-scan hit rate (consequence of D1) | Screen 09 is designed as a normal path, not an error; cache grows from user entries |
| `est_price_inr` estimates are approximate | Always labelled as estimates in the UI; receipt-captured prices override |
| Alias coverage gaps break matching | Free text accepted and saved locally for next time (board); alias table is data, extensible without code changes |
| Android toolchain still uninstalled (D10) | Blocks APK production only, not screen verification. ~2 GB install when needed |
