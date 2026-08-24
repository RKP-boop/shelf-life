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
