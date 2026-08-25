# Figma registry — v2 (Premium)

**This supersedes v1.** The v1 deep-olive file is retained only for comparison.

| File | Key | Status |
|---|---|---|
| ShelfLife — Premium UI v2 | `COwU4NcifaHygTqCHUliS8` | **Active** |
| ShelfLife — MVP Screens (v1, olive) | `tHUZoQJZ7mnx7ibEcxrPZD` | Superseded |
| ShelfLife — MVP User Flows (FigJam) | `VtBS3Rn1WMO9kUvXWkVdV1` | Read-only source of the 9 flows |

URL: https://www.figma.com/design/COwU4NcifaHygTqCHUliS8

## Design system

- **Typeface:** Plus Jakarta Sans. Chosen over Poppins deliberately — Poppins is among the most overused UI faces and reads as templated.
- **13 text styles**, `Chip/SemiBold-11` → `Numeral/Bold-34`.
- **33 colour variables**, **14 scale variables**, single `Default` mode, no `ALL_SCOPES` leaks.
- **Canvas:** three-stop pastel gradient — `page/mint #E9F6F0` → `page/cream #FDF4EC` → `page/blush #FDEDE6`.
- **Accent:** `accent/primary #0A7A55`. `accent/bright #12B981` is decorative only and never sits behind text.

## Components (48)

**Chrome:** `StatusBar`, `Nav/Bottom` (elevated emerald Scan overhanging the bar by 18 dp)
**Actions:** `Button/Primary` (trailing arrow chip), `Button/Primary-plain`, `Button/Secondary`, `Button/Add`, `Stepper`
**Surfaces:** `TextField`, `SearchField`, `ListRow`, `ItemRow`
**State:** `Badge/Use-in-days`, `Badge/Best-used-today`, `Chip/Discount`, `Chip/Rating`
**Icons (29):** home, grid, scan, bowl, user, arrow-left, arrow-right, chevron-right, search, plus, minus, bell, pin, sliders, heart, check, close, pencil, calendar, receipt, camera, barcode, sort, lock, lightbulb, star-filled, torch, trash, users
**Produce (7):** tomato, orange, banana, milk, avocado, broccoli, spinach — each built from a vertical gradient body, a blurred specular highlight, and a soft contact shadow

## 52 screens

Flow 1 auth/onboarding (12) · Flow 2 receipt OCR (7) · Flow 3 barcode (3) · Flow 4 manual (1) · Flow 5 inventory (9) · Flow 6 expiry/notifications (2) · Flow 7 recipes (6) · Flow 8 shopping (3) · Flow 9 profile/stats (6) · cross-cutting states (3)

Laid out on a 6-column grid, 520 dp × 1030 dp pitch. Every frame exactly 412 × 915 with a 42 dp radius.

## Verification gate

| Check | Result |
|---|---|
| 52 frames at exactly 412 × 915, all populated | ✅ |
| Green "Fresh" pill anywhere | ✅ none — fresh is silence |
| Visible unbound solid fills (token bypass) | ✅ **0** |
| Forbidden copy (`Error` / `Expired` / `Failed` / `Warning`) | ✅ none — PRD 4.10 substitutions hold |
| Guilt framing (`wasted`, `you threw`) | ✅ none — Principle 3 holds |
| WCAG AA across the palette | ✅ 16/16 pairs |

262 gradient paints are expected: Figma cannot bind colour variables to gradients.

## Defects caught by rendering or auditing

1. **The reference's emerald fails AA.** `#0E9E6E` with white button text is **3.42:1**. Every primary CTA would have been non-compliant. Replaced with `#0A7A55` at 5.35:1.
2. **`#63726B` secondary text failed on the peach tint** (4.35:1). Darkened to `#5C6B64`, which passes on all seven surfaces (worst 4.83).
3. **Produce artwork overflowed its containers** — resizing a Figma frame does not scale its children. Fixed by using `rescale()` throughout.
4. **`₹1,240` clipped** in a three-column `FILL` stat row (v1). Fixed with `HUG` + `SPACE_BETWEEN`.
5. **Status bar was dark-on-dark** on both camera screens — invisible. Inverted per-instance.
6. **Torch button rendered a star icon**; no torch glyph existed in the file.
7. **115 unbound literal fills** (speculars, scrims, inverted whites). Tokenised via new `produce/specular` and `overlay/scrim` variables; now zero.
8. **Spinach rendered as scattered leaves** — Figma rotation moves the node origin. Re-authored as a single deterministic SVG fan.
9. **Notification action button overlapped its wrapped body**; detail rows on Review wrapped to two lines. Both fixed, the latter with disclosed ellipsis truncation.

## Outstanding

- **True 3D renders.** Produce is gradient-vector approximating dimension, per your decision. Each is a swappable component, so real renders drop in without touching layouts.
- **Interaction states.** Pressed/focus are Flutter concerns; they need a non-zero transition duration.

---

## 3D render assets — integrated 2026-08-25

Source: `design/3D Assets/` (originals) → `design/3D Assets/normalized/` (processed).

### Normalisation applied

Originals were high quality but not to spec, so each was processed before upload:

| Issue found | Fix |
|---|---|
| Subjects filled **96–100%** of frame, not the specified 76% | Auto-cropped to the alpha bounding box, rescaled so the longest edge is 76% of a 1024 canvas, re-centred on transparent ground. Gives every item a **matching apparent scale** in equal-sized tiles. |
| `avocado` was 1536×1024, `coriander` 1355×1161 | Re-squared to 1024×1024 |
| `produce-spinach.png.png` double extension | Renamed |
| `produce-avacado.png` misspelled | Renamed |
| **`produce-brocolli.png` was actually the coriander render** | Renamed to `coriander.png`. Nothing was missing — all 10 Tier 1 items were present, two just misnamed. |

All 10 verified as genuinely transparent (corner alpha 0–1, not merely an RGBA channel).

### Integration method

The image fill sits **on the component frame itself**, not on a child node. This matters: ~80 instances had been `rescale`d to sizes from 34 dp to 238 dp, and swapping child artwork would have left every one of them overflowing. A frame fill scales with the frame, so all instances updated correctly at their existing sizes.

### Components

| Component | Node | Instances |
|---|---|---|
| `Produce/spinach` | `15:63` | 23 |
| `Produce/milk` | `5:24` | 20 |
| `Produce/tomato` | `3:8` | 14 |
| `Produce/avocado` | `5:31` | 8 |
| `Produce/banana` | `3:22` | 7 |
| `Produce/broccoli` | `5:42` | 3 |
| `Produce/onion` | `49:67` | 3 |
| `Produce/atta` | `49:63` | 2 |
| `Produce/coriander` | `49:65` | 2 |
| `Produce/paneer` | `49:69` | 1 |

`Produce/orange` was **retired** — it was the last vector item and would have looked out of place among renders. All 6 of its usages were reassigned first, then it was deleted at zero instances.

### Semantic corrections

Ten instances had been using stand-in produce because the correct render didn't exist when the screen was built:

- Home hub: Fruits tile → banana, Pantry tile → atta
- Mark-used confirm: "Onion" row → onion (was orange)
- Shopping list: "Atta" → atta, "Kasuri methi" → coriander, "Coriander" → coriander
- Add by hand: "Spinach (frozen)" → broccoli
- Value prop 2 / 3, Auth landing: decorative cluster items → onion / paneer for palette variety

### Still outstanding

- **Dish photographs (5)** — recipe cards and the recipe-detail hero currently use produce as stand-ins. Prompts are in `ASSET-PROMPTS.md`.
- **Tier 2 produce (13)** — prompts ready; not blocking, since every item any built screen names now has a real render.
- **Hero flat-lay (1)** — auth landing still uses the abstract botanical composition.

## Tier 2 assets — segmented from a single sheet, 2026-08-25

Supplied as **one 1536×1024 sheet** containing 13 items in a 5/5/3 grid, then split programmatically by `tools/segment_sheet.py`.

### How the split works

Projection-profile splitting, not connected-component labelling. It cuts on empty gutters, which keeps a subject's separate parts together — the garlic bulb and its three loose cloves stay one item, where blob labelling would have emitted four.

Rows are split first, then columns *within each row*. A row's own column profile is far cleaner than the whole sheet's, where a tall item in one row bridges a gutter in another.

### What tuning was needed

| Finding | Resolution |
|---|---|
| The sheet **looked** to have a mottled multi-colour background in chat | It was genuinely transparent — 56% zero-alpha. The mottling is leftover RGB *beneath* the alpha, which chat renderers composite. Analysing the file rather than the preview was the difference between "unusable" and "clean". |
| First pass found **3 items, not 13** | It found the three rows. Items within a row were bridged by faint shadow glow, so no column was exactly empty. |
| Threshold sweep | `--split-alpha 90 --floor 0.07` yields `[5, 5, 3]` = 13. The floor treats a column below 7% of the row's peak as empty. |
| Reading order was scrambled | My final y-bucket sort reordered items, since items in a row rarely share a top edge. Removed it — the loops already produce reading order. |
| **Lemon carried a stray orange speck** bled from the neighbouring carrot | Added a despeckle pass: grow from the densest seed, keep the reachable mass, drop islands. Dropped 674 px from the lemon and **zero** from the other twelve, so it was surgical rather than destructive. |

The splitting mask uses a firm alpha threshold while the output keeps the file's original soft alpha — otherwise the despeckling would have hardened every shadow edge.

### Self-test

Before running it on real input, the tool was validated by recomposing the 10 Tier 1 assets into a synthetic sheet: **10/10 recovered on a transparent sheet and 10/10 on a flat-white one.**

### Produce library — 23 components

`apple` `atta` `avocado` `banana` `broccoli` `capsicum` `carrot` `cauliflower` `coriander` `cream` `cucumber` `curd` `garlic` `ginger` `lemon` `milk` `onion` `paneer` `peas-frozen` `potato` `rice` `spinach` `tomato`

Home's Fruits category tile now uses `apple` rather than `banana` — more canonical for the category.

### Known UX consideration

Four items are **bowl-based** — `curd`, `cream`, `rice`, `peas-frozen` — and `curd` and `cream` are near-identical white swirls in differently-toned blue bowls. At the 34–46 dp thumbnail sizes used in inventory rows and shopping lists these are not distinguishable from one another.

This is acceptable rather than broken: the item name always sits adjacent, so the render is reinforcement, not the sole identifier. But if bowl items ever need to be told apart at a glance, they need distinguishing silhouettes rather than distinguishing colours.
