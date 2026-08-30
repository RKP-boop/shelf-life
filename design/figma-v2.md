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

## Tier 2 replaced with individual renders — 2026-08-27

The `tier2-raw/` folder was replaced with **14 individually generated files** rather than sheet crops. All were swapped into the existing components in place.

### Why this mattered — the sheet approach produced soft assets

| | sheet crop | individual render | gain |
|---|---|---|---|
| typical subject size | ~280 px | ~1,220 px | **~4.3×** |
| scaling applied to reach 778 px | **2.4–3.0× upscale** | 0.6× downscale | — |

A 1536×1024 sheet split 13 ways gives each item only ~280 px, so every Tier 2 asset was being upscaled 2.4–3.0× and rendering visibly soft — worst at the 238 dp item-detail hero. **A single sheet is fine for identifying and cropping, but not for final asset resolution.** Individual files at ~1,200 px are now downscaled rather than upscaled.

### Despeckle removed for individual files

The despeckle pass — needed for sheet crops, where a neighbour's artwork can bleed into a crop — actively destroyed content here:

- **peas lost 66,816 px**: the render has loose peas scattered outside the pile, and "keep the largest connected mass" deleted them
- **rice lost 8,192 px**: same, for its scattered loose grains

Individual files have no neighbours to bleed in, and 12 of 14 reported zero drops. The pass is unnecessary and harmful for them, so it is now skipped: crop to alpha bbox → scale to 76% → centre. `tools/segment_sheet.py` retains despeckle, correctly, for sheet input.

### Two prior issues resolved by the new renders

1. **`cream` is now a carton, not a bowl.** This closes the curd/cream ambiguity flagged earlier — they had been near-identical white swirls in differently-toned blue bowls, indistinguishable at 34–46 dp. Different silhouettes now.
2. **`peas-frozen` is loose scattered peas**, no bowl — so it no longer reads like `rice`.

Bowl-based items are down from four to two (`curd`, `rice`), and those two differ in both bowl colour and contents.

### Upload method

The reconnected Figma MCP supports a `nodeIds` array on `upload_assets`, so each image was set as a fill directly on its target component — **14/14 confirmed landing on the intended node**, with no temporary placement frames to create or clean up.

### Verification

| Check | Result |
|---|---|
| Produce components | 23 |
| Exactly one image fill per component, no leftover children, all 120×120 | ✅ |
| Produce instances across 52 screens | 83, **0 broken** |
| Library-only components (available, not yet placed) | 12 — `capsicum` `carrot` `cauliflower` `cream` `cucumber` `curd` `garlic` `ginger` `lemon` `peas-frozen` `potato` `rice` |

`banana` (Tier 1) was also regenerated as a bunch rather than a single fruit, and replaced.

## Dish photographs integrated — 2026-08-27

Five dishes supplied as individual files in `design/3D Assets/Dish assets/`, normalised into `normalized-dishes/`.

`Dish/aloo-gobi` `67:1179` · `Dish/avocado-toast` `67:1181` · `Dish/palak-paneer` `67:1183` · `Dish/paneer-bhurji` `67:1185` · `Dish/vegetable-pulao` `67:1187`

### Better than specified

The prompt sheet said dishes needn't be transparent, since they sit inside a tinted panel. All five arrived **transparent at 1254×1254**, which is better: they now take the panel's tint rather than carrying a competing background, so they sit consistently with the produce.

Normalised at an **88% inset** rather than the produce 76%. Dishes are the hero of their panel and all five are already near-square, so they can carry more presence.

### Placement — 11 swaps, audited by hand

A context-walk found 15 produce instances near recipe names, but **4 were false positives** and were deliberately left alone:

| Left as produce | Why |
|---|---|
| `15:265` Item detail hero | This is the *Fresh Spinach* item hero. The walker caught "Palak Paneer" from the recipe row further down the screen. Swapping it would have replaced the item with a dish. |
| `35:1410` Shopping list "Cream" | An ingredient row, not a dish. Separately corrected from the `milk` render to the new `cream` component. |
| `35:1423` Shopping list "Kasuri methi" | Ingredient row; `coriander` was already right. |
| `34:1223` Recipe detail hero, second item | Hidden rather than swapped — with the real dish present, a second ingredient in the hero is clutter. |

Swapped: Home hub "Cook tonight", Item detail "Cook it tonight", Recipes list ×3, Recipe detail hero, Saved recipes ×4, and the Notifications "Tonight's dinner" card, which now correctly shows **paneer bhurji** — the dish its copy names.

### Defect: swapComponent rescales by component-size ratio

Dish components were built at 160×160 while Produce are 120×120. `swapComponent` preserves an instance's scale *relative to its main component*, so every 92 px produce instance became 92 × (160/120) = **123 px** — overflowing the 100 px recipe panel by 21.3 px. Resizing before the swap does not prevent it.

Fixed in two parts:

1. **Recipe cards enlarged** — dish panel 100 → 132 px, card 200 → 232 px, with the text block shifted down. The food now leads the card, closer to the reference.
2. **Every dish refitted to its container**, sizing each instance so its visible artwork occupies a fixed fraction of the parent. Two instances needed special handling: on Home hub and Item detail the dish is a *sibling* of its tint tile rather than a child, so measuring the parent gave the whole card — those were aligned to the tile instead.

### Verification

A geometric clipping audit computes each instance's visible artwork box, walks to the nearest clipping ancestor, and measures overflow on all four edges:

**83 instances checked — 0 clipped.**

| | |
|---|---|
| Produce components | 23 |
| Dish components | 5 |
| Total asset components | **28** |
| Screens | 52, all 412 × 915 |

## Category fallback glyphs — 2026-08-27

Five components closing the gap between the seeded catalogue and the asset
library: 41 of 65 ingredients have no individual render and need a category
marker.

`Glyph/cat-vegetables` `81:90` · `Glyph/cat-fruits` `81:96` · `Glyph/cat-dairy` `81:102` · `Glyph/cat-pantry` `81:108` · `Glyph/cat-frozen` `81:116`

| Fallback | Silhouette | Covers |
|---|---|---|
| `cat-vegetables` | leafy sprout | 9 — okra, brinjal, cabbage, beans, curry leaves, green chilli, mushroom, spring onion, bottle gourd |
| `cat-fruits` | round fruit with a leaf | 7 — mango, grapes, guava, orange, papaya, pomegranate, watermelon |
| `cat-dairy` | gable-top carton | 4 — butter, ghee, cheese, buttermilk |
| `cat-pantry` | lidded jar | 18 — dals, spices, oil, sugar, salt, tea, coffee, bread, eggs and more |
| `cat-frozen` | snowflake | 3 — ice cream, frozen paratha, frozen vegetables |

### Why iconographic and not a borrowed render

Reusing a real render — showing the broccoli photograph for okra — would put the
**wrong food** beside the right name. A deliberately iconographic marker reads
honestly as "category: vegetable" instead of asserting something false.
Distinction between the five comes from **silhouette, not colour**, so the set
still works for anyone who cannot separate the tints (PRD 4.11).

### Two sizing bugs, both instructive

1. **`resize()` does not scale a child vector.** The first build placed the
   artwork as a child node, so shrinking an instance to 34 dp left a 91 dp glyph
   inside a 34 dp frame — visible only as a clipped fragment. Produce components
   avoid this because their artwork is an image *fill*, and fills do scale with
   the frame.
2. **Auto-layout padding does not scale either.** The obvious fix — auto-layout
   with a `FILL` child and 12% padding — worked at 120 dp but left **6 dp of
   artwork at 34 dp**, because a 14 dp pad is 14 dp at every frame size.

The working answer is to bake the inset into the SVG viewBox (a `translate` inside
a viewBox enlarged by `1/0.76`) and use zero padding, so the art fills 100% of the
frame. Verified: 58 dp → 58 dp art, 46 → 46, 34 → 34.

All five are **120 × 120**, matching `Produce/*` exactly, so `swapComponent`
never rescales an instance — the defect that overflowed the recipe panels by
21 px when the Dish components were built at 160.

### Refinements from rendering at real size

- **pantry** was a tied sack, too close to the round fruit silhouette. Redrawn as
  a lidded jar with a label band.
- **frozen** first read as tangled sticks. Adding decorative tips made it busier,
  not clearer; the working version is three arms and a solid hub. At 34 dp, fewer
  and larger shapes always win.

### Contract guard

`tools/check_asset_coverage.py` asserts every `ingredients.glyph_key` and
`recipes.image_key` resolves to a real component, and that a fallback matches its
ingredient's own category — so a pantry item can never display a vegetable
marker. Both are plain text in Postgres with nothing enforcing them, so a typo
would otherwise surface as a blank tile in the running app and nowhere else.

**33/33 references resolve.** Proven by injecting two faults (a nonexistent glyph
and a wrong-category fallback) and confirming a non-zero exit, then reverting.

Asset library is now **33 components**: 23 produce renders, 5 category fallbacks,
5 dish photographs.

## Discrepancy found 2026-08-28

`get_metadata` on file `COwU4NcifaHygTqCHUliS8` lists exactly one page, `Design
System` (`0:1`), and that canvas contains **only** the component library —
produce, dish and glyph symbols, icons, chrome, buttons, and the two check
frames. **None of the 52 screen frames appear.**

The component library is intact and is what the Flutter build actually consumes:
tokens came out via `design/tokens.json`, and the produce / dish / glyph art was
exported to PNG and is bundled in the app. So this does not block the build.

What it does mean: the "52 frames at exactly 412 × 915" row in the verification
gate above cannot be re-verified against this file key as written. The screen
content for the Flutter build is therefore taken from the spec and the FigJam
flow board (`VtBS3Rn1WMO9kUvXWkVdV1`), which are the authoritative content
sources in any case. Screen layout is verified instead by committed golden
renders under `shelflife_app/test/screens/goldens/`.
