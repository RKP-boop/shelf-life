# ShelfLife — handoff

A kitchen inventory app that tells you what needs using before it goes off.
Flutter, offline-first, with a Supabase backend it never blocks on.

- **Remaining setup (start here):** [`docs/FINISH-SETUP.md`](docs/FINISH-SETUP.md)
- **Install and build:** [`INSTALL.md`](INSTALL.md)
- **Google sign-in setup:** [`docs/google-sign-in-setup.md`](docs/google-sign-in-setup.md)
- **Email verification setup:** [`docs/email-verification-setup.md`](docs/email-verification-setup.md)
- **Every decision and its reasoning:** [`docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md`](docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md) — the decision log D1–D21 is the thing to read first
- **Design system registry:** [`design/figma-v2.md`](design/figma-v2.md)

---

## Where things are

```
shelflife_app/
  lib/
    app/            AppScope (state), shell (tabs), flows (all navigation)
    core/
      engines/      expiry estimator, recipe scorer, receipt parser — pure, no I/O
      services/     capability interfaces + fakes; platform_capabilities = the plugins
      theme/        tokens.g.dart, GENERATED from design/tokens.json
      widgets/      the shared library the 52 screens are composed from
    database/       Hive store, sync outbox
    features/       one directory per area, screens only
    models/         plain data classes, JSON in and out
    repositories/   reads and writes, Hive-backed
    services/       seed, reminders, sync transport
  assets/           produce/dish/glyph renders, fonts, seed/reference.json
  test/
    screens/goldens/  52 committed screen renders

supabase/
  migrations/     001–006, run in order
  seed/           data.py is the single source; generate.py -> SQL, emit_app_seed.py -> JSON

tools/            the guards (see below)
design/           Figma registry, token export, 3D render sources
```

## The rules the code actually enforces

These are not style preferences. Each is checked by something that fails.

| Rule | Where it comes from | What enforces it |
|---|---|---|
| Fresh items carry **no** badge | D4 | `FreshnessBadge` returns an empty box; `copy_rules_test.dart` |
| The match **score** is never rendered | spec §5.2 | `copy_rules_test.dart` scans for interpolated scores |
| No `Error` / `Expired` / `Failed` / `Warning` / `Delete` | PRD 4.10 | `copy_rules_test.dart`, over every string in `lib/` |
| Count rescues, never waste | Principle 3 | `copy_rules_test.dart` guilt-phrase scan |
| Every estimate explains itself | Principle 4 | `expiry_estimator` returns a reason; it is stored, not recomputed |
| Nothing blocks on the network | Principle 6 | every read is a synchronous Hive call; `SyncService` only pushes |
| Theme is generated, never typed | — | `tools/gen_theme.py` asserts on token values |
| The APK actually launches | learned the hard way | `tools/audit_apk.py` resolves the manifest's launcher class against the dex |
| WCAG AA across the palette | PRD 4.11 | `tools/check_contrast.py`, 19 pairs |

Each guard was proved by breaking it on purpose and confirming it failed —
that is recorded in the spec rather than assumed.

## Running the guards

```bash
python tools/check_contrast.py          # colour pairs, exits 1 on a failure
python tools/check_asset_coverage.py    # every glyph_key resolves to a file
python tools/verify_backend.py          # 33 checks against the live database
cd shelflife_app && flutter test        # engines, repositories, 52 goldens, copy rules
```

## Regenerating

```bash
python tools/gen_theme.py                     # design/tokens.json -> tokens.g.dart
python supabase/seed/generate.py              # data.py -> SQL
python supabase/seed/emit_app_seed.py         # data.py -> assets/seed/reference.json
cd shelflife_app && flutter test --update-goldens
```

`data.py` is the single source for the catalogue. It produces both the SQL and
the app's bundled JSON, so the two cannot drift.

---

## Things worth knowing before you change anything

**Reference ids are content-addressed.** `ingredients.id` is
`md5(canonical_name)` as a uuid, and `recipes.id` is `md5(lower(name))`
(migration 006). This is what lets a phone that has never reached the server
write `inventory_items.ingredient_id` and have the foreign key hold when it
finally syncs. If you add an ingredient, both the SQL and the JSON have to be
regenerated from `data.py` — `seed_test.dart` will catch it if you do not.

**The outbox stops at the first failure, it does not skip.** An update queued
after an insert cannot be applied before it. `SyncService.drain` breaks out of
the loop rather than continuing, and `sync_queue_test.dart` proves the ordering
survives a restart.

**Guest mode queues nothing.** `SyncQueue` drops writes while
`meta.is_guest` is true, and `rekey()` moves local rows onto a real user id on
sign-up. That is the whole guest-upgrade path.

**Notification ids are derived, not stored.** `md5`-like hash of
`(itemId, level)`, masked to 31 bits. Re-scheduling replaces rather than
duplicates, and the Hive ledger prevents a second reminder for the same stage
even if the schedule is lost.

**The capture screens take an injected `viewfinder`, and it must be supplied.**
That seam is what lets all 52 screens render in a golden test with no camera —
and it was built and then left empty, so the receipt and barcode screens showed
a flat dark rectangle on a real phone and mobile_scanner never detected
anything, because its preview widget has to be in the tree for the camera to
run at all. The live previews live in
`features/capture/widgets/live_viewfinders.dart`; `flows.dart` supplies them
when the concrete service is the real one rather than a fake.

**Screens take callbacks and know nothing about routing.** That is why all 52
render in a golden test. Navigation lives entirely in `lib/app/flows.dart`. If
you find yourself importing `Navigator` into a screen, the wiring belongs in
flows instead.

**A green test suite says nothing about whether the app launches.** The Dart
tests, the goldens and the analyzer all pass on an APK whose manifest points at
a class that is not in the dex — that shipped once, and the app died before its
first frame. `tools/audit_apk.py` now checks the launcher activity resolves;
run it on any build before sending it anywhere. Bootstrap is also wrapped, so a
failure between `ensureInitialized` and `runApp` shows a screen naming the
cause instead of the process vanishing.

**Rendering a golden is not the same as looking at it.** The bottom nav floated
mid-page on any screen with short content — a Stack sizes to its tallest child,
so it shrank and took the positioned bar with it. That was visible in
`10-home-clear.png` from the moment it was first rendered; it went unnoticed
because 52 images were generated and only a handful were actually inspected. If
you regenerate goldens, budget time to read them, or the suite only tells you
that rendering did not crash.

**Goldens are a review tool as much as an assertion.** They are committed so a
diff shows unintended visual change. The harness asserts the real font loaded —
without that check, text silently falls back to a one-em-per-glyph placeholder
and every golden looks plausible but wrong. That happened once.

---

## What is done

- All 52 screens, rendered and committed as goldens
- Three pure engines with unit tests
- Hive persistence, offline outbox with ordering and backoff
- Supabase: 10 tables, RLS verified with two real users, 6 migrations
- Seeded catalogue: 65 ingredients, 153 aliases, 40 recipes, 40 barcodes
- Real Android capabilities: ML Kit OCR, mobile_scanner, camera, local notifications
- 213 tests
- The release APK installed on an emulator and driven through the whole first
  run: onboarding, guest mode, empty home, add-by-hand with catalogue
  suggestions, saving an item, the reminder-permission prompt, and all four
  tabs. Not just built

## Known environment blocker

**Smart App Control is enforced on the machine this was built on** and
intermittently blocks Flutter's `gen_snapshot.exe`, failing the release build
with "An Application Control policy has blocked this file". It is not a project
problem and it affects any Flutter release build on that machine. Options and
the irreversibility of turning it off are in `INSTALL.md`.

## What is not

- **iOS is unbuilt.** The Dart is platform-agnostic and the capability
  implementations handle iOS, but nothing has been compiled or run there.
- **The v2 Figma file's screen frames are missing.** `get_metadata` returns only
  the component library. The components are intact and are what the app
  consumes; the screen layouts are verified by the committed goldens instead.
  Recorded in `design/figma-v2.md`.
- **OCR is tested against fixture text, not a photographed receipt.** The parser
  has unit tests over real DMart receipt text; ML Kit's recognition quality on
  an actual phone camera has not been measured.
- **No analytics, no crash reporting.** Deliberate for an MVP, but it means a
  failure on someone else's phone is invisible to you.
