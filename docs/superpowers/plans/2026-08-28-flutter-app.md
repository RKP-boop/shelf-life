# ShelfLife Flutter App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Android app covering all 52 designed screens, wired to the live Supabase backend, offline-first, delivered as an installable `.apk`.

**Architecture:** Feature-first Flutter (PRD §5.4). Three pure Dart engines with no I/O, built test-first, so the logic that decides expiry, ranks recipes and parses receipts is verifiable without a device. Hive is the source of truth; Supabase is a backup and sync channel. Every native capability sits behind an interface with a fake, so all 52 screens compile and render on desktop and the real plugins slot in for the Android build.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1 (installed, verified). Hive, `supabase_flutter`, `google_mlkit_text_recognition`, `mobile_scanner`, `flutter_local_notifications`. JDK 17 + Android SDK.

**Spec:** `docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md`
**Design:** Figma `COwU4NcifaHygTqCHUliS8` — 52 screens, 33 asset components
**Backend:** `iodzysmxzjfqbrvktzgc` — 10 tables, verified 33/33

## Global Constraints

- **Theme is generated from `design/tokens.json`**, never hand-typed. Figma and code cannot drift if code is derived.
- **Never render a recipe match score.** Show "N of M ingredients" and name the urgent items (spec §5.2).
- **Fresh items show no badge.** Only two exist: amber "Use in N days", red "Best used today" (D4).
- **Forbidden words** (PRD 4.10): `Error`, `Expired`, `Failed`, `Warning`, `Delete`. Use the substitutions. A test enforces this over every string in the app.
- **Positive framing (Principle 3):** count rescues, never waste.
- **Explainable intelligence (Principle 4):** every expiry estimate carries a plain-English reason, stored not reconstructed.
- **Offline first (Principle 6):** every read serves from Hive. No screen blocks on the network. Sync status is a subtle indicator, never a blocking spinner.
- **Hard delete** with an explicit confirmation (D7 / BR-02).
- **Anon key only** in the app. The service-role key must never appear in the repo or the APK.
- **Tap targets ≥ 48 dp**, WCAG AA contrast, no colour-only meaning (PRD 4.11).
- **Interaction states need a non-zero transition** — instant state changes are an anti-pattern.

---

## Phase 0 — Toolchain and skeleton

### Task 0.1: Android toolchain
- [ ] JDK 17 via winget; Android SDK command-line tools to `C:\src\android-sdk`
- [ ] `sdkmanager` install: `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`
- [ ] `flutter config --android-sdk`, accept licences, `flutter doctor -v` clean for the Android toolchain
- [ ] Create an emulator (`system-images;android-35;google_apis;x86_64`) — `HypervisorPresent: True` confirmed, so WHPX acceleration is available
- [ ] **Verify:** `flutter devices` lists both `windows` and the emulator

### Task 0.2: Project skeleton
- [ ] `flutter create --org com.shelflife --platforms=android,windows shelflife_app`
- [ ] Feature-first directories exactly per PRD §5.4
- [ ] `.gitignore`: `key.properties`, `*.jks`, `.env`
- [ ] **Verify:** `flutter analyze` clean, `flutter run -d windows` shows the default app

### Task 0.3: Generated theme
- [ ] `tools/gen_theme.py` reads `design/tokens.json` → `lib/core/theme/tokens.g.dart`
- [ ] Every colour, radius, spacing value and the 13 text styles, as `const`
- [ ] A header comment marking it generated, plus a test asserting it matches `tokens.json` — so a hand-edit fails CI
- [ ] **Verify:** the generated file contains `#0A7A55`, not `#0E9E6E` (D14), and `#9E5D00` (D11)

---

## Phase 1 — The three engines (TDD, no device)

Written test-first. These are the highest-value tests in the project: they encode business rules and run in milliseconds with no emulator.

### Task 1.1: Expiry estimator
- [ ] **Test first:** precedence order — user override beats printed beats per-item estimate beats category fallback (spec §5.1, BR-01)
- [ ] **Test:** returns a reason string. `Spinach` bought 5 days ago with a 6-day fridge life → *"You bought this five days ago, and fresh greens keep about six."*
- [ ] **Test:** freshness banding — red on or before today, amber within 3 days, **none** beyond (D4)
- [ ] **Test:** an ingredient with no shelf life for the chosen storage falls back to its category
- [ ] Implement `ExpiryEstimator.estimate(...) → ExpiryEstimate(date, source, reason)`
- [ ] **Verify:** `dart test test/engines/expiry_estimator_test.dart` green

### Task 1.2: Recipe scorer
- [ ] **Test first:** `0.6·(have/total) + 0.3·urgency + 0.1·speed`, with the exact fixtures the SQL function was verified against, so client and server agree
- [ ] **Test:** optional ingredients excluded from have/total
- [ ] **Test:** returns `missingNames` and `urgentNames`, never a bare score
- [ ] **Test:** a recipe with zero available ingredients is excluded
- [ ] Implement `RecipeScorer`
- [ ] **Verify:** for a spinach+paneer+onion+tomato kitchen, ranking matches the live SQL result recorded in `supabase/VERIFIED.md`

### Task 1.3: Receipt parser
- [ ] **Test first:** strips quantity, unit and price tokens — `AMUL TAAZA TONED MILK 500ML  ₹64.00` → `milk`
- [ ] **Test:** filters non-grocery lines — totals, GST, store name, phone numbers (explicit board requirement)
- [ ] **Test:** resolves through the alias table — `PALAK 250G` → `spinach`
- [ ] **Test:** below the confidence threshold, returns `needsInput` rather than guessing (screen 17's "Needs your input")
- [ ] **Test:** a real fixture — a full receipt in `test/fixtures/receipt_bigbazaar.txt` → expected item list
- [ ] Implement `ReceiptParser`
- [ ] **Verify:** `dart test` green; ≥80% of fixture lines resolved, matching PRD 4.14's "<20% manual edits"

---

## Phase 2 — Data layer

### Task 2.1: Models + Hive
- [ ] Freezed/json models mirroring all ten tables; Hive adapters
- [ ] **Test:** round-trip every model through Hive without loss
- [ ] **Test:** enum values match the Postgres enums exactly — a mismatch here is a runtime 400 from PostgREST

### Task 2.2: Repositories (PRD §5.10)
- [ ] `InventoryRepository`, `RecipeRepository`, `ShoppingRepository`, `StatsRepository`, `ProductRepository`, `IngredientRepository`
- [ ] Every read serves Hive first
- [ ] **Test:** with the network stubbed as unavailable, every repository still returns data

### Task 2.3: Sync queue
- [ ] Hive outbox: append on write, drain FIFO on reconnect, retry with backoff
- [ ] Conflict: last-write-wins, both timestamps retained (PRD 5.8)
- [ ] **Test:** three offline writes drain **in original order**
- [ ] **Test:** a failed op stays queued and does not block the ones behind it
- [ ] **Test:** guest mode never touches the network; upgrade re-keys local rows to the new `user_id` with zero loss

### Task 2.4: Native capabilities behind interfaces
- [ ] `OcrService`, `BarcodeScanner`, `NotificationScheduler`, `CameraService` — each an interface with a real and a fake implementation
- [ ] Fakes registered on desktop; real plugins on Android
- [ ] **Verify:** the app compiles and runs on Windows with no Android plugin present

---

## Phase 3 — Screens, all 52

Grouped by flow. Each group: build, run, screenshot, compare against the Figma frame, fix.

| Group | Screens | Count |
|---|---|---|
| 3.1 Onboarding + auth | 01–08 | 8 |
| 3.2 Home + guest | 09–12 | 4 |
| 3.3 Receipt capture | 13–19 | 7 |
| 3.4 Barcode + manual | 20–23 | 4 |
| 3.5 Inventory | 24–28, 32 | 6 |
| 3.6 Item detail + edit | 29–31 | 3 |
| 3.7 Recipes | 33–38 | 6 |
| 3.8 Shopping | 39–41 | 3 |
| 3.9 Profile + settings | 42–47 | 6 |
| 3.10 Notifications + cross-cutting | 48–52 | 5 |

- [ ] Shared widget library first — `AppButton`, `Badge`, `FilterChip`, `ItemRow`, `ProduceImage`, `SearchField`, `BottomNav`, `Sheet` — mirroring the Figma components, so 52 screens compose rather than repeat
- [ ] `ProduceImage` resolves `glyph_key` → asset, with the category fallback for the 41 ingredients that have no individual render
- [ ] **Golden test:** fresh items render no badge (D4)
- [ ] **Test:** no string in the app matches the forbidden-word list
- [ ] **Test:** every declared colour pair passes WCAG AA — reuse `tools/check_contrast.py` logic in Dart
- [ ] **Verify per group:** screenshot each screen on the emulator, compare to its Figma frame

---

## Phase 4 — Integration and delivery

### Task 4.1: Live backend
- [ ] Wire `supabase_flutter` with the anon key from `--dart-define`, never committed
- [ ] **Verify:** sign up, add an item, kill the network, add another, restore, confirm both land in Postgres
- [ ] **Verify:** `match_recipes` and `kitchen_stats` RPCs render on Recipes and Profile

### Task 4.2: Native paths on the emulator
- [ ] OCR against a fixture image pushed to the emulator — deterministic, and a better test than a live camera
- [ ] Barcode against a generated EAN-13 image
- [ ] Schedule a notification 60 s out and confirm delivery
- [ ] **Honest limit:** real-camera quality on a physical phone, and notification behaviour on OEM-modified Android (Xiaomi/Samsung battery killers are a known Flutter issue), cannot be verified here. Both are listed in the handoff as tests only the user can run.

### Task 4.3: Signed APK
- [ ] User generates the keystore; `key.properties` is gitignored and never read into the transcript
- [ ] Release signing config in `build.gradle.kts`
- [ ] `flutter build apk --release --split-per-abi` plus a universal APK for direct sharing
- [ ] **Verify:** install the built APK on the emulator via `adb install`, launch it, navigate the main flows, screenshot
- [ ] Report the real APK size

### Task 4.4: Handoff
- [ ] `INSTALL.md` — how to sideload, the "unknown sources" step, and the Play Protect warning to expect
- [ ] `HANDOFF.md` — what is verified, what is not, and the tests only a physical device can run

---

## Self-Review

**Spec coverage.** §5.1 → 1.1, §5.2 → 1.2, §5.3 → 1.3, §5.10 → 2.2, §6 sync → 2.3, §5 native interfaces → 2.4, §7 module layout → 0.2. All 52 Figma screens → Phase 3. PRD §3.8's eight Definition-of-Done criteria are all covered by Phases 1–4.

**Ordering rationale.** Engines precede screens because they are pure, fast to test, and encode the rules the screens merely display. Building screens first would mean discovering a business-rule error through a UI bug.

**Scope risk, stated plainly.** 52 screens is a large build and will span multiple sessions. The concern I raised — breadth at the cost of depth — was reaffirmed, so this plan targets all 52. The mitigation is the shared widget library in Phase 3: if the components are right, the screens are composition rather than 52 bespoke builds. If quality does start slipping, I will say so at a group boundary rather than at the end.

**What cannot be verified here, restated.** Real-camera capture on a physical phone, real-world OCR accuracy on crumpled receipts, and notification reliability on OEM Android. Every other claim in this plan is backed by a test or a screenshot.
