# Figma registry

Addressable IDs for the ShelfLife design work. Later plans use these instead of re-discovering nodes.

## Files

| File | Key | Type | Notes |
|---|---|---|---|
| ShelfLife — MVP Screens | `tHUZoQJZ7mnx7ibEcxrPZD` | design | Design system + screens. All authoring happens here. |
| ShelfLife — MVP User Flows | `VtBS3Rn1WMO9kUvXWkVdV1` | FigJam board | **Read-only. Do not modify.** Source of the 9 flows and the `[DECISION]` layer. |

File URL: https://www.figma.com/design/tHUZoQJZ7mnx7ibEcxrPZD

Plan: `team::1662104991471686217` (`rakeshpathak.pgp25's team`, student tier — **single variable mode only**).

## Pages

| Page | ID |
|---|---|
| Design System | `0:1` |
| Screens | `1:2` |

## Variable collections

| Collection | ID | Count | Mode |
|---|---|---|---|
| ShelfLife/Colour | `VariableCollectionId:1:3` | 21 | `Default` (`1:0`) |
| ShelfLife/Scale | `VariableCollectionId:1:25` | 13 | `Default` |

No variable uses `ALL_SCOPES` — verified. Values are exported to `design/tokens.json`, which is the contract the Flutter theme is generated from.

## Text styles

12 Inter styles: `Display/Light-30`, `Display/Bold-30`, `Wordmark/Light-34`, `Wordmark/Bold-34`, `Numeral/Light-48`, `Numeral/Light-72`, `Section/SemiBold-20`, `Card/SemiBold-16`, `Body/Regular-16`, `Secondary/Regular-14`, `Chip/Medium-12`, `Label/Medium-12`.

## Components

| Component | Node ID | Size | Notes |
|---|---|---|---|
| `Badge/Use-in-days` | `2:5` | 111 × 28 | State badge, **not interactive**. Amber `#9E5D00` per D11. |
| `Badge/Best-used-today` | `2:9` | — | State badge. Dot glyph so urgency is never colour-only. |
| `Chip/Filter-selected` | `2:12` | — | Interactive filter, selected. |
| `Chip/Filter-default` | `2:15` | — | Interactive filter, unselected. |
| `Button/Cream-pill` | `3:4` | 364 × 56 | Primary. Must stay the brightest element on screen. |
| `Button/Outlined-cream` | `3:7` | 364 × 56 | Secondary. Deliberately quieter. |
| `Button/Deep-olive` | `3:10` | 364 × 56 | Primary on light/frosted surfaces. |
| `Card/Frosted` | `5:3` | 364 × 200 | 92% opacity minimum. Depth shadow. |
| `Strip/Info` | `5:7` | 364 × 44 | Blue = informational only, never urgency. |
| `Nav/Bottom` | `6:23` | 380 × 72 | 5 cells at 68 × 56, 6 dp gaps. Real vector icons. |
| Component sheet | `7:2` | 900 × 1230 | Review surface, on the real olive canvas. |

**There is deliberately no green "Fresh" badge.** Fresh is silence (D4).

## Icon paths

The five nav icons are inline SVG authored in Task 8 — simple geometric primitives, no library dependency. Paths are in the Plan 1a execution history; regenerate from there if the nav is rebuilt.

## Execution deviations from Plan 1a

Recorded so the plan and the file agree:

1. **`createComponentFromNode()` instead of create-then-append.** Converts the frame in place, so the component *is* the pill with no redundant wrapper. Simpler than planned.
2. **Two extra components: `Chip/Filter-selected` and `Chip/Filter-default`.** Added because conflating state badges with interactive chips is a high-severity anti-pattern — badges convey state, chips convey a selectable value. Four screens need the filter family.
3. **`surface/frosted` is `#F8FBF3`, not `#FFFFFF`.** Pure white rendered as a clinical box; the screen doc specifies "white at 92% with a faint green tint". Verified at 15.45:1 / 5.46:1.
4. **Nav labels are 12 px, not 11.** 11 px broke the `Label/Medium-12` token and sat under the 12 px floor. `Inventory` still fits in a 68 dp cell at 12 px.
5. **No translucent glass border.** At 92% opacity a `rgba(white, 0.2)` border is invisible. Depth is carried by the drop shadow instead.
6. **Real SVG vector nav icons** rather than the planned ellipse placeholders.

---

## Screen frames (page `Screens` = `1:2`)

4 × 4 grid, 512 dp horizontal pitch, 1055 dp vertical pitch. Every frame is exactly 412 × 915.

| Screen | Node ID | Screen | Node ID |
|---|---|---|---|
| 01 Value prop | `11:83` | 09 Barcode not found | `11:91` |
| 02 Auth | `11:84` | 10 Add by hand | `11:92` |
| 03 Home empty | `11:85` | 11 Inventory | `11:93` |
| 04 Home hub | `11:86` | 12 Item detail | `11:94` |
| 05 Scan chooser | `11:87` | 13 Recipes | `11:95` |
| 06 Receipt camera | `11:88` | 14 Recipe detail | `11:96` |
| 07 Reading receipt | `11:89` | 15 Shopping list | `11:97` |
| 08 Review confirm | `11:90` | 16 Profile | `11:98` |

## Icon components (21)

`Icon/arrow-left` `9:35` · `chevron-right` `9:38` · `search` `9:41` · `plus` `9:44` · `minus` `9:47` · `check` `9:50` · `close` `9:53` · `pencil` `9:56` · `camera` `9:59` · `barcode` `9:62` · `basket` `9:65` · `lock` `9:68` · `lightbulb` `9:71` · `calendar` `9:74` · `sort` `9:77` · `more-vertical` `9:80` · `bookmark` `9:83` · `leaf` `9:86` · `receipt` `9:89` · `torch` `9:92` · `users` `25:79`

All authored as inline SVG, `stroke-width 1.8`, round caps/joins, strokes bound to colour variables. Simple geometric primitives — no icon-library dependency.

## Glyph components (6)

`Glyph/greens` `10:39` · `Glyph/dairy` `10:45` · `Glyph/fruit` `10:51` · `Glyph/pantry` `10:57` · `Glyph/frozen` `10:64` · `Glyph/dish` `13:101`

Five category fallbacks plus a dish glyph, per the screen doc's pragmatic path. The full ~60-glyph set remains an asset commission and is **not** a build blocker.

## Verification gate results

| Check | Result |
|---|---|
| 16 frames at exactly 412 × 915, all populated | ✅ |
| No green "Fresh" badge anywhere | ✅ (2 text matches are the words "Fresh Spinach" and "fresh greens" in prose, both `insidePill: false`) |
| Visible unbound solid fills (token bypass) | ✅ 0 |
| Non-solid paints | 2, both declared exceptions: screen 02 gradient scrim, screen 06 vignette |
| Leftover shimmer placeholders | ✅ 0 |
| WCAG AA contrast gate | ✅ 13/13, exit 0 |

## Defects found by rendering

Each was invisible in code and only surfaced by screenshotting:

1. **`₹1,240` clipped to `₹1,24`** on screen 04 — three equal `FILL` columns gave 111 dp each against a 146 dp numeral. Fixed by switching stat columns to `HUG` with `SPACE_BETWEEN`.
2. **Three nav cells carried unbound default fills** — `createAutoLayout()` applies a default white fill, never cleared on Inventory/Recipes/Profile. Made two tabs look simultaneously active.
3. **`Nav/Scan` cell had the same stray default fill** — white on a light bar, so no render caught it. Only the token-bypass audit found it.
4. **Hero steam strokes rendered hairline-thin** on screen 14 — resizing a 24 px SVG to 210 px scales geometry but not stroke weight. Set to 11.
5. **Two detail lines hard-clipped** on screen 08. Fixed with tighter spacing plus `textTruncation: ENDING` so any overflow discloses itself rather than cutting.
6. **Leaf glyph collided with the wordmark** on screen 02.
7. **`sort` and `leaf` icons rendered malformed** and were redrawn.
8. **Household settings row used an arrow-left icon**; added `Icon/users`.

## Outstanding assets

- **Screen 02 photograph.** The doc specifies overhead Indian vegetables under moody side light. Layout, gradient scrim and button hierarchy are correct; the background is an abstract botanical stand-in built from palette shapes. Swap in a real photograph when available.
- **~55 remaining food glyphs.**
- **Interaction states.** Pressed/focus are Flutter concerns (Plan 3) and require a non-zero transition duration.
