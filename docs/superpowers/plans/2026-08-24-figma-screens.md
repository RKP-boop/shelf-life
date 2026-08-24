# ShelfLife Figma Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the 16 MVP screens at 412 × 915 dp on the `Screens` page of the ShelfLife design file, composed from the components and tokens built in Plan 1a.

**Architecture:** An icon library is built first, because every screen references glyphs and placeholder circles would make all 16 look unfinished. Screens are then created as a 4 × 4 grid of frames, each populated in its own `use_figma` call so a failure is isolated to one screen. Every colour comes from a variable; no screen hardcodes a hex value.

**Tech Stack:** Figma Plugin API via `use_figma`; inline SVG for glyphs; Inter.

**Spec:** `docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md`
**Source of screen content:** `…/shelflife-app-user-flow/outputs/ShelfLife-Stitch-Prompts.md` — the layout and every user-facing string come from that document verbatim.

## Why this plan is shaped differently from Plan 1a

Plan 1a specified complete code per step because variables, scopes and component structure are interdependent and fail in hard-to-diagnose ways. Screens are not: they are compositions of already-verified components, and each is independently disposable. Writing 16 exhaustive code blocks would transcribe the screen doc a second time and drift from it. So this plan fixes the **manifest, the shared recipe, and the gate**, and treats the screen doc as the content spec it already is.

## Global Constraints

- File `tHUZoQJZ7mnx7ibEcxrPZD`, page `Screens` (`1:2`). Do not touch FigJam board `VtBS3Rn1WMO9kUvXWkVdV1`.
- Frames are exactly **412 × 915**, laid out on a 4 × 4 grid with 512 dp horizontal and 1055 dp vertical pitch.
- **Every** fill and stroke binds to a `ShelfLife/Colour` variable. Zero literal hex in screen code.
- Type comes from the 12 text styles. No ad-hoc font sizes.
- Spacing on the 8 dp grid. Tap targets ≥ 48 dp.
- **Fresh renders no badge** (D4). Amber badge text is `#9E5D00` (D11). `text/on-deep-tertiary` only on `surface/deep` (D12).
- Every user-facing string is verbatim from the screen doc's microcopy bank or PRD 4.6–4.10. Never write "Error", "Expired", "Delete", "Failed", or "Warning" — use the PRD 4.10 substitutions.
- Positive framing only (Principle 3): count rescues, never waste.
- Match scores render as "7 of 9 ingredients", **never** a bare percentage.
- `use_figma` rules from Plan 1a apply unchanged: 0–1 colours, `return` is the only output, return all node IDs, ≤ ~10 logical ops per call, no `figma.notify()`, no sync `currentPage` setter, `appendChild` before `HUG`/`FILL`, `textAutoResize` before `FILL`.

---

## File Structure

| File | Responsibility |
|---|---|
| `design/figma.md` | Extended with icon component IDs and the 16 screen frame IDs. |
| `design/icons.md` | The SVG path source for every glyph, so the library is reproducible without re-deriving paths. |

---

### Task 1: Build the utility icon library

**Interfaces:**
- Produces: components named `Icon/<name>` for: `arrow-left`, `chevron-right`, `search`, `plus`, `minus`, `check`, `close`, `pencil`, `camera`, `barcode`, `basket`, `lock`, `lightbulb`, `calendar`, `sort`, `more-vertical`, `bookmark`, `leaf`, `receipt`, `google-g`.

- [ ] **Step 1:** Author each icon as a 24 × 24 inline SVG with `stroke-width 1.8`, round caps and joins, and no fill. Create via `figma.createNodeFromSvg`, rebind strokes to a variable, convert with `createComponentFromNode`.
- [ ] **Step 2:** Screenshot the icon sheet. Verify every glyph is recognisable at 22 dp and none is a filled blob (a common `createNodeFromSvg` failure when `fill` is not cleared).
- [ ] **Step 3:** Record paths in `design/icons.md` and IDs in `design/figma.md`. Commit.

### Task 2: Build the food category glyphs

Per the screen doc's "pragmatic path", ship the **five category fallbacks** first: `Glyph/greens`, `Glyph/dairy`, `Glyph/fruit`, `Glyph/pantry`, `Glyph/frozen`. The full ~60-glyph set is a separate asset commission and is explicitly **not** a blocker.

- [ ] **Step 1:** Author each as a filled flat shape in the glyph palette (`glyph/dark`, `glyph/mid`, `glyph/light`), on a pale circular tint, sized 56 dp.
- [ ] **Step 2:** Screenshot. Verify each is legible at 40 dp and reads as Indian household produce, not Western (the screen doc names this failure mode: "if illustrations return kale and avocado").
- [ ] **Step 3:** Commit.

### Task 3: Create the 16 screen frames

- [ ] **Step 1:** Switch to page `1:2` with `await figma.setCurrentPageAsync(page)` — once in this call only.
- [ ] **Step 2:** Create 16 frames at 412 × 915, `surface/canvas` fill, `clipsContent = true`, named `01 Value prop` … `16 Profile`, positioned on the grid.
- [ ] **Step 3:** Set `placeholder = true` on each so progress is visible, and verify with `get_metadata` that 16 frames exist at the right sizes.
- [ ] **Step 4:** Record frame IDs in `design/figma.md`. Commit.

### Tasks 4–19: Populate each screen

One task per screen, in the order below. Each: populate, set `placeholder = false`, screenshot, fix observable breakage, commit.

| # | Screen | Must contain | Highest-risk detail |
|---|---|---|---|
| 4 | 01 Value prop | Two-weight headline, 3 dots, cream pill "Next", "Skip" link | No bottom nav |
| 5 | 02 Auth | Gradient scrim, wordmark, 3 auth actions, terms line | **Cream Google pill must be the brightest element**; the doc names equal-weight auth buttons as the single most likely miss |
| 6 | 03 Home empty | Greeting, frosted card, empty-state copy, "Scan a receipt" | Copy verbatim: "Your kitchen is empty. Scan your first grocery receipt." |
| 7 | 04 Home hub | "Use these first" row, "Cook tonight", stat card, list card, nav | "Use these first" must be the first thing the eye lands on after the greeting — if the stat card dominates, the screen optimises for vanity metrics |
| 8 | 05 Scan chooser | Bottom sheet, 3 rows, "Recommended" chip | 76 dp rows, hairline dividers |
| 9 | 06 Receipt camera | Viewfinder, guide frame, priming sheet, "Allow camera" | Privacy copy verbatim |
| 10 | 07 Reading receipt | Progress ring, "Reading your receipt...", faded thumbnail | Copy verbatim from PRD 4.8 |
| 11 | 08 Review & confirm | Info strip, editable rows, one "Needs your input" row, bottom bar | Every row must *look* editable |
| 12 | 09 Barcode not found | Barcode + "Scanned" chip, error copy, form, "Save product" | A dead end that must not feel like one |
| 13 | 10 Add by hand | Name field + autocomplete, category chips, stepper, date, storage chips | Ceiling of four taps and a name |
| 14 | 11 Inventory list | Title, filter chips, 5 item cards, mid-swipe reveal, FAB | **Two of five rows carry NO badge** — chipless rows must look calm, not unfinished |
| 15 | 12 Item detail | Hero glyph, two-weight name, red badge, info strip, detail grid, recipe row | Storage location must be present — the usual omission |
| 16 | 13 Recipes list | Title, filter chips, 3 recipe cards | "7 of 9 ingredients", never a bare score |
| 17 | 14 Recipe detail | Hero, stat row, "In your kitchen", "You'll need to buy", method | The available/missing split is the screen's whole job |
| 18 | 15 Shopping list | Info strip, "To buy · 4", "In the basket · 2", bottom bar + caption | BR-06 caption: "Nothing moves into your kitchen until you tap this." |
| 19 | 16 Profile | Avatar, hero numeral "08", two stat cards, settings list | "meals rescued", never "items wasted" (Principle 3) |

### Task 20: Verification gate

- [ ] **Step 1:** Screenshot all 16 frames and inspect for clipping, overlap, and text collapse.
- [ ] **Step 2:** Assert no green "Fresh" badge exists anywhere:
```js
const page = await figma.getNodeByIdAsync("1:2");
await figma.setCurrentPageAsync(page);
const suspects = page.findAll(n => n.type === 'TEXT' &&
  /fresh/i.test(n.characters) && n.parent && n.parent.cornerRadius === 999);
return { suspects: suspects.map(n => ({ id: n.id, txt: n.characters })) };
```
Expected: empty.
- [ ] **Step 3:** Assert no literal hex leaked into screen fills — every solid fill on a screen frame subtree must carry a `boundVariables.color` entry:
```js
const page = await figma.getNodeByIdAsync("1:2");
await figma.setCurrentPageAsync(page);
const unbound = [];
for (const f of page.children) {
  for (const n of f.findAll(x => 'fills' in x && Array.isArray(x.fills))) {
    for (const p of n.fills) {
      if (p.type === 'SOLID' && !(p.boundVariables && p.boundVariables.color)) {
        unbound.push({ screen: f.name, node: n.name, id: n.id });
      }
    }
  }
}
return { unboundCount: unbound.length, unbound: unbound.slice(0, 40) };
```
Expected: only deliberate exceptions (gradient scrim on screen 02, camera viewfinder on 06). Anything else is a token bypass.
- [ ] **Step 4:** Assert every screen frame is exactly 412 × 915 and there are 16 of them.
- [ ] **Step 5:** Confirm no `placeholder = true` shimmer remains.
- [ ] **Step 6:** Re-run `python tools/check_contrast.py` — must still exit 0.
- [ ] **Step 7:** Cross-check against the screen doc's own "After generation" list: every field the flow specifies is present; empty and error states exist as real screens; contrast checked on every frosted surface; one mockup per named screen.
- [ ] **Step 8:** Commit.

---

## Self-Review

**Spec coverage.** Spec §8 step 3 (author the 16 screens at 412 × 915) is Tasks 3–19. Spec §9 criterion 4 (fresh renders no badge) is Task 20 Step 2. The screen doc's four required empty states and four error states are covered by screens 03, 07, 09 and the empty/error copy carried into 11, 13, 15 — Task 20 Step 7 verifies this explicitly.

**Known gaps, stated rather than hidden.**
1. **Screen 02 needs a photograph I cannot produce.** The doc asks for overhead Indian vegetables under moody side light. I will build the gradient scrim, layout and hierarchy correctly with an illustrated botanical stand-in, and flag the photo as a pending asset. Everything else on the screen is real.
2. **Only 5 of ~60 food glyphs.** Deliberate, per the doc's own pragmatic path.
3. **No interaction states in Figma.** Pressed/focus states are Flutter concerns (Plan 3), where a non-zero transition duration is required — instant state changes are an anti-pattern.

**Placeholder scan.** No `TBD`/`TODO`. Tasks 1–3 and 20 carry complete steps; Tasks 4–19 are specified by the manifest table plus the screen doc, which is the content authority by design.

**Type consistency.** Component names match Plan 1a exactly: `Badge/Use-in-days`, `Badge/Best-used-today`, `Chip/Filter-selected`, `Chip/Filter-default`, `Button/Cream-pill`, `Button/Outlined-cream`, `Button/Deep-olive`, `Card/Frosted`, `Strip/Info`, `Nav/Bottom`. Variable names match `design/tokens.json`.
