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
