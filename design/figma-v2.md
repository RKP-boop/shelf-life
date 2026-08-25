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
