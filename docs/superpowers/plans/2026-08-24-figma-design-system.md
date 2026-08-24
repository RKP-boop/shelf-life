# ShelfLife Figma Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the ShelfLife design system in a new Figma design file — variables, text styles, and the six reusable components — and export the token values to `design/tokens.json` as the single source of truth that the Flutter theme will later be generated from.

**Architecture:** One Figma design file with two pages: `Design System` (tokens + component sheet) and `Screens` (populated by the follow-on plan). All colour, spacing and radius values live as Figma variables with explicit scopes; components bind to those variables rather than hardcoding hex. The final task reads the variables back out of Figma and writes `design/tokens.json`, so Figma and code cannot drift — code is generated from the file, never hand-copied.

**Tech Stack:** Figma Plugin API via the `use_figma` MCP tool; Inter typeface; Node/Python for the token export and contrast assertions.

**Spec:** `docs/superpowers/specs/2026-08-24-shelflife-mvp-design.md`

## Global Constraints

- **Figma plan:** `team::1662104991471686217` (`rakeshpathak.pgp25's team`, student tier). **Single mode only** — do not create additional variable modes.
- **Do not modify** the existing FigJam flow board `VtBS3Rn1WMO9kUvXWkVdV1`. All work goes in a new design file.
- **Screen size:** 412 × 915 dp. Spacing on an 8 dp grid. Every tap target ≥ 48 × 48 dp.
- **Typeface:** Inter. Figma style names are `"Light"`, `"Regular"`, `"Medium"`, `"Semi Bold"`, `"Bold"` — note the space in `"Semi Bold"`.
- **Freshness rule (D4):** exactly two chips exist. Fresh state renders **no chip**. Never create a green "Fresh" chip.
- **Amber chip text is `#9E5D00`, not `#B26A00`** (D11 — the original fails WCAG AA at 3.86:1).
- **`colour/text-on-deep-tertiary` (`#A8B885`) is for `#2E3D0A` surfaces only** (D12 — it measures 3.91:1 on the canvas colour).
- **Contrast floor:** WCAG AA — 4.5:1 for text below 24 px regular / 18.66 px bold; 3.0:1 above.
- **`use_figma` rules:** colours are 0–1 range; `return` is the only output channel; every script returns created/mutated node IDs; at most ~10 logical operations per call; never call `figma.notify()`; never use the sync `figma.currentPage` setter; always set `variable.scopes` explicitly.

---

## File Structure

| File | Responsibility |
|---|---|
| `design/figma.md` | Records the Figma file key, page IDs and component node IDs. Human-readable registry so later plans can address nodes without re-discovery. |
| `design/tokens.json` | Generated from Figma in Task 9. The contract between design and code. Consumed by the Flutter theme in Plan 3. |
| `tools/check_contrast.py` | Asserts WCAG AA over every foreground/background pair declared in `tokens.json`. Run in CI and in Task 9. |
| `tools/token_pairs.json` | Declares which foreground/background combinations are legal, so the checker knows what to test. |

---

### Task 1: Create the design file and page structure

**Files:**
- Create: `design/figma.md`

**Interfaces:**
- Produces: `FILE_KEY` (string) — the design file key, used by every subsequent task. `PAGE_DS_ID`, `PAGE_SCREENS_ID` (strings).

- [ ] **Step 1: Create the file**

Call `create_new_file` with:
```
fileName:   "ShelfLife — MVP Screens"
planKey:    "team::1662104991471686217"
editorType: "design"
```
Record the returned `fileKey` and URL.

- [ ] **Step 2: Create the two pages and rename the default**

Call `use_figma` with `skillNames: "resource:figma-use"`:
```js
// The default page is named "Page 1" — rename it rather than adding a third.
const ds = figma.root.children[0];
ds.name = "Design System";
const screens = figma.createPage();
screens.name = "Screens";
return {
  mutatedNodeIds: [ds.id],
  createdNodeIds: [screens.id],
  pages: figma.root.children.map(p => ({ name: p.name, id: p.id }))
};
```

- [ ] **Step 3: Verify the structure**

Call `get_metadata` with the `fileKey` and no `nodeId`. Expected: two top-level pages, `Design System` and `Screens`.

- [ ] **Step 4: Record the registry**

Write `design/figma.md` containing the file key, file URL, both page IDs, and a note that the FigJam flow board `VtBS3Rn1WMO9kUvXWkVdV1` is a separate file that must not be modified.

- [ ] **Step 5: Commit**

```bash
git add design/figma.md
git commit -m "design: create Figma design file and page structure"
```

---

### Task 2: Verify Inter font styles resolve

**Files:** none (verification only)

**Interfaces:**
- Produces: confirmation that the five style strings used by every later task exist.

This task exists because a wrong style string throws `Cannot write to node with unloaded font` on first use, and the failure surfaces deep inside a screen build where it is expensive to diagnose. Verifying up front is two minutes.

- [ ] **Step 1: Query available Inter styles**

```js
const fonts = await figma.listAvailableFontsAsync();
const inter = fonts
  .filter(f => f.fontName.family === "Inter")
  .map(f => f.fontName.style);
const needed = ["Light", "Regular", "Medium", "Semi Bold", "Bold"];
return {
  available: inter,
  missing: needed.filter(s => !inter.includes(s))
};
```

- [ ] **Step 2: Confirm the result**

Expected: `missing` is an empty array. If any style is missing, stop and report — do not substitute a different weight, because the two-weight 30sp title treatment depends on the Light/Bold contrast being genuine.

---

### Task 3: Create the colour variable collection

**Files:** none (Figma state)

**Interfaces:**
- Produces: variable collection `ShelfLife/Colour` with a single mode, and 20 COLOR variables addressable by the names below. Later tasks bind by name via a `varByName` lookup.

- [ ] **Step 1: Create the collection and the surface + text colours**

```js
const c = figma.variables.createVariableCollection("ShelfLife/Colour");
c.renameMode(c.modes[0].modeId, "Default");
const mode = c.modes[0].modeId;

const hex = h => {
  h = h.replace('#','');
  return {
    r: parseInt(h.slice(0,2),16)/255,
    g: parseInt(h.slice(2,4),16)/255,
    b: parseInt(h.slice(4,6),16)/255,
    a: 1
  };
};

// [name, hex, scopes]
const defs = [
  ["surface/canvas",             "#44540E", ["FRAME_FILL","SHAPE_FILL"]],
  ["surface/deep",               "#2E3D0A", ["FRAME_FILL","SHAPE_FILL"]],
  ["surface/accent",             "#5A6B1A", ["FRAME_FILL","SHAPE_FILL"]],
  ["surface/frosted",            "#FFFFFF", ["FRAME_FILL","SHAPE_FILL"]],
  ["surface/opaque",             "#E8EFE0", ["FRAME_FILL","SHAPE_FILL"]],
  ["surface/field",              "#F2F5EA", ["FRAME_FILL","SHAPE_FILL"]],
  ["text/on-light-primary",      "#1A2408", ["TEXT_FILL"]],
  ["text/on-light-secondary",    "#5F6B45", ["TEXT_FILL"]],
  ["text/on-olive-primary",      "#F2F5EA", ["TEXT_FILL"]],
  ["text/on-olive-secondary",    "#C9D6A8", ["TEXT_FILL"]],
  ["text/on-deep-tertiary",      "#A8B885", ["TEXT_FILL"]],
];

const created = [];
for (const [name, h, scopes] of defs) {
  const v = figma.variables.createVariable(name, c, "COLOR");
  v.setValueForMode(mode, hex(h));
  v.scopes = scopes;
  created.push({ name, id: v.id });
}
return { collectionId: c.id, modeId: mode, created };
```

Note `text/on-deep-tertiary` is deliberately named for the surface it is legal on (D12).

- [ ] **Step 2: Add the state, info and structural colours**

```js
const c = (await figma.variables.getLocalVariableCollectionsAsync())
  .find(x => x.name === "ShelfLife/Colour");
const mode = c.modes[0].modeId;
const hex = h => { h = h.replace('#',''); return {
  r: parseInt(h.slice(0,2),16)/255, g: parseInt(h.slice(2,4),16)/255,
  b: parseInt(h.slice(4,6),16)/255, a: 1 }; };

const defs = [
  ["state/amber-text",  "#9E5D00", ["TEXT_FILL"]],       // D11 — NOT #B26A00
  ["state/amber-bg",    "#FFF3E0", ["FRAME_FILL","SHAPE_FILL"]],
  ["state/red-text",    "#C62828", ["TEXT_FILL"]],
  ["state/red-bg",      "#FDECEA", ["FRAME_FILL","SHAPE_FILL"]],
  ["info/text",         "#1565C0", ["TEXT_FILL"]],
  ["info/bg",           "#E8F1FB", ["FRAME_FILL","SHAPE_FILL"]],
  ["structure/divider", "#E4E8DC", ["FRAME_FILL","SHAPE_FILL","STROKE_COLOR"]],
  ["glyph/dark",        "#2E3D0A", ["SHAPE_FILL"]],
  ["glyph/mid",         "#5A6B1A", ["SHAPE_FILL"]],
  ["glyph/light",       "#C9D6A8", ["SHAPE_FILL"]],
];

const created = [];
for (const [name, h, scopes] of defs) {
  const v = figma.variables.createVariable(name, c, "COLOR");
  v.setValueForMode(mode, hex(h));
  v.scopes = scopes;
  created.push({ name, id: v.id });
}
return { created, total: c.variableIds.length };
```

- [ ] **Step 3: Verify the collection**

```js
const cols = await figma.variables.getLocalVariableCollectionsAsync();
const c = cols.find(x => x.name === "ShelfLife/Colour");
const vars = await Promise.all(
  c.variableIds.map(id => figma.variables.getVariableByIdAsync(id))
);
return {
  modes: c.modes.map(m => m.name),
  count: vars.length,
  anyAllScopes: vars.filter(v => v.scopes.includes("ALL_SCOPES")).map(v => v.name)
};
```

Expected: `modes` is `["Default"]`, `count` is 21, `anyAllScopes` is empty. A non-empty `anyAllScopes` means a scope assignment was missed — fix before continuing.

---

### Task 4: Create the spacing, radius and size variables

**Files:** none (Figma state)

**Interfaces:**
- Produces: collection `ShelfLife/Scale` with FLOAT variables `space/4` … `space/32`, `radius/card`, `radius/sheet`, `radius/pill`, `size/tap-min`, `size/screen-w`, `size/screen-h`.

- [ ] **Step 1: Create the collection and variables**

```js
const c = figma.variables.createVariableCollection("ShelfLife/Scale");
c.renameMode(c.modes[0].modeId, "Default");
const mode = c.modes[0].modeId;

const defs = [
  ["space/4",  4,  ["GAP","WIDTH_HEIGHT"]],
  ["space/8",  8,  ["GAP","WIDTH_HEIGHT"]],
  ["space/12", 12, ["GAP","WIDTH_HEIGHT"]],
  ["space/16", 16, ["GAP","WIDTH_HEIGHT"]],
  ["space/20", 20, ["GAP","WIDTH_HEIGHT"]],
  ["space/24", 24, ["GAP","WIDTH_HEIGHT"]],
  ["space/32", 32, ["GAP","WIDTH_HEIGHT"]],
  ["radius/card",  24,  ["CORNER_RADIUS"]],
  ["radius/sheet", 28,  ["CORNER_RADIUS"]],
  ["radius/pill",  999, ["CORNER_RADIUS"]],
  ["size/tap-min",  48, ["WIDTH_HEIGHT"]],
  ["size/screen-w", 412,["WIDTH_HEIGHT"]],
  ["size/screen-h", 915,["WIDTH_HEIGHT"]],
];

const created = [];
for (const [name, val, scopes] of defs) {
  const v = figma.variables.createVariable(name, c, "FLOAT");
  v.setValueForMode(mode, val);
  v.scopes = scopes;
  created.push({ name, id: v.id, value: val });
}
return { collectionId: c.id, created };
```

- [ ] **Step 2: Verify**

Expected: 13 variables, single mode named `Default`, no `ALL_SCOPES`. Reuse the verification script from Task 3 Step 3 with the collection name `ShelfLife/Scale` and expected count 13.

---

### Task 5: Create the text styles

**Files:** none (Figma state)

**Interfaces:**
- Produces: named text styles addressable by `figma.getLocalTextStylesAsync()`: `Display/Light-30`, `Display/Bold-30`, `Wordmark/Light-34`, `Wordmark/Bold-34`, `Numeral/Light-48`, `Numeral/Light-72`, `Section/SemiBold-20`, `Card/SemiBold-16`, `Body/Regular-16`, `Secondary/Regular-14`, `Chip/Medium-12`, `Label/Medium-12`.

- [ ] **Step 1: Load the fonts, then create the styles**

Font loading must complete before any style creation, per the canonical recipe.

```js
const styles = [
  ["Display/Light-30",    "Light",     30, 36],
  ["Display/Bold-30",     "Bold",      30, 36],
  ["Wordmark/Light-34",   "Light",     34, 38],
  ["Wordmark/Bold-34",    "Bold",      34, 38],
  ["Numeral/Light-48",    "Light",     48, 52],
  ["Numeral/Light-72",    "Light",     72, 76],
  ["Section/SemiBold-20", "Semi Bold", 20, 28],
  ["Card/SemiBold-16",    "Semi Bold", 16, 24],
  ["Body/Regular-16",     "Regular",   16, 24],
  ["Secondary/Regular-14","Regular",   14, 20],
  ["Chip/Medium-12",      "Medium",    12, 16],
  ["Label/Medium-12",     "Medium",    12, 16],
];

// Load every distinct style once, and await all of them, before mutating.
const distinct = [...new Set(styles.map(s => s[1]))];
await Promise.all(distinct.map(st =>
  figma.loadFontAsync({ family: "Inter", style: st })
));

const created = [];
for (const [name, style, size, lh] of styles) {
  const ts = figma.createTextStyle();
  ts.name = name;
  ts.fontName = { family: "Inter", style };
  ts.fontSize = size;
  ts.lineHeight = { unit: "PIXELS", value: lh };
  created.push({ name, id: ts.id });
}
return { created };
```

- [ ] **Step 2: Verify**

```js
const ts = await figma.getLocalTextStylesAsync();
return ts.map(s => ({
  name: s.name,
  family: s.fontName.family,
  style: s.fontName.style,
  size: s.fontSize
}));
```

Expected: 12 styles, all family `Inter`, sizes matching the table above.

---

### Task 6: Build the freshness chip components

**Files:**
- Modify: `design/figma.md` (append component IDs)

**Interfaces:**
- Produces: two components, `Chip/Use-in-days` and `Chip/Best-used-today`, each an auto-layout pill containing a dot ellipse and a text node. No third "fresh" variant exists by design (D4).

- [ ] **Step 1: Build both chips**

`appendChild` happens before any `HUG`/`FILL` assignment, per the sizing rules.

```js
await figma.loadFontAsync({ family: "Inter", style: "Medium" });
const vars = {};
for (const v of await figma.variables.getLocalVariablesAsync()) vars[v.name] = v;

const bindFill = (node, name) => {
  const p = figma.variables.setBoundVariableForPaint(
    { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[name]
  );
  node.fills = [p];
};

function chip(name, label, textVar, bgVar, x, y) {
  const row = figma.createAutoLayout('HORIZONTAL', {
    name, itemSpacing: 6, paddingLeft: 10, paddingRight: 12,
    paddingTop: 5, paddingBottom: 5, counterAxisAlignItems: 'CENTER'
  });
  row.cornerRadius = 999;
  bindFill(row, bgVar);

  const dot = figma.createEllipse();
  dot.resize(6, 6);
  bindFill(dot, textVar);
  row.appendChild(dot);

  const t = figma.createText();
  t.fontName = { family: "Inter", style: "Medium" };
  t.fontSize = 12;
  t.lineHeight = { unit: "PIXELS", value: 16 };
  t.characters = label;
  bindFill(t, textVar);
  row.appendChild(t);
  t.layoutSizingHorizontal = 'HUG';

  figma.currentPage.appendChild(row);
  row.x = x; row.y = y;
  const comp = figma.createComponent();
  comp.resize(row.width, row.height);
  comp.x = x; comp.y = y;
  comp.name = name;
  comp.appendChild(row);
  comp.layoutMode = 'HORIZONTAL';
  comp.primaryAxisSizingMode = 'AUTO';
  comp.counterAxisSizingMode = 'AUTO';
  return comp;
}

const a = chip("Chip/Use-in-days",      "Use in 2 days",    "state/amber-text", "state/amber-bg", 200, 200);
const b = chip("Chip/Best-used-today",  "Best used today",  "state/red-text",   "state/red-bg",   200, 260);
a.description = "Amber freshness chip. Shown when an item is 1-3 days from its expiry estimate. Text colour is #9E5D00 for WCAG AA at 12sp; do not revert to #B26A00.";
b.description = "Red freshness chip. Shown on the expiry day. Carries a dot glyph so urgency is never conveyed by colour alone (PRD 4.11).";
return { createdNodeIds: [a.id, b.id] };
```

- [ ] **Step 2: Screenshot to verify**

```js
const ids = ["<A_ID>", "<B_ID>"];
const nodes = await Promise.all(ids.map(i => figma.getNodeByIdAsync(i)));
await nodes[0].screenshot();
await nodes[1].screenshot();
return { checked: ids };
```

Verify visually: pill fully rounded, dot present on both, text not clipped, no green chip anywhere.

- [ ] **Step 3: Record and commit**

Append both component IDs to `design/figma.md`.

```bash
git add design/figma.md
git commit -m "design: add freshness chip components"
```

---

### Task 7: Build the button components

**Files:**
- Modify: `design/figma.md`

**Interfaces:**
- Produces: `Button/Cream-pill`, `Button/Outlined-cream`, `Button/Deep-olive` — each 56 dp tall, fully rounded, auto-layout with a centred text child.

- [ ] **Step 1: Build the three buttons**

```js
await figma.loadFontAsync({ family: "Inter", style: "Medium" });
const vars = {};
for (const v of await figma.variables.getLocalVariablesAsync()) vars[v.name] = v;
const bindFill = (n, name) => {
  n.fills = [figma.variables.setBoundVariableForPaint(
    { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[name])];
};
const bindStroke = (n, name) => {
  n.strokes = [figma.variables.setBoundVariableForPaint(
    { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[name])];
};

function button(name, label, fillVar, textVar, strokeVar, y) {
  const f = figma.createAutoLayout('HORIZONTAL', {
    name, primaryAxisAlignItems: 'CENTER', counterAxisAlignItems: 'CENTER',
    paddingLeft: 24, paddingRight: 24
  });
  f.cornerRadius = 999;
  if (fillVar) bindFill(f, fillVar); else f.fills = [];
  if (strokeVar) { bindStroke(f, strokeVar); f.strokeWeight = 1.5; }

  const t = figma.createText();
  t.fontName = { family: "Inter", style: "Medium" };
  t.fontSize = 16;
  t.lineHeight = { unit: "PIXELS", value: 24 };
  t.characters = label;
  bindFill(t, textVar);
  f.appendChild(t);
  t.layoutSizingHorizontal = 'HUG';

  figma.currentPage.appendChild(f);
  f.resize(364, 56);           // resize BEFORE sizing modes
  f.primaryAxisSizingMode = 'FIXED';
  f.counterAxisSizingMode = 'FIXED';
  f.x = 200; f.y = y;

  const comp = figma.createComponent();
  comp.name = name;
  comp.resize(364, 56);
  comp.x = 600; comp.y = y;
  comp.appendChild(f);
  return comp;
}

const b1 = button("Button/Cream-pill",     "Continue with Google", "surface/field",  "text/on-light-primary", null, 360);
const b2 = button("Button/Outlined-cream", "Use email instead",    null,             "text/on-olive-primary", "surface/opaque", 440);
const b3 = button("Button/Deep-olive",     "Scan a receipt",       "surface/deep",   "text/on-olive-primary", null, 520);
b1.description = "Primary action. Solid cream fill — must remain the brightest element on any screen it appears on (screen 02 hierarchy).";
b2.description = "Secondary action. Transparent with a 1.5dp cream border. Deliberately quieter than the cream pill.";
b3.description = "Primary action on light/frosted surfaces, where cream would have no contrast.";
return { createdNodeIds: [b1.id, b2.id, b3.id] };
```

- [ ] **Step 2: Screenshot all three together and verify hierarchy**

Screenshot the three components. The cream pill must read as visibly brightest, the outlined button clearly quieter. If they read as equal weight, the screen 02 hierarchy is broken — the screen doc names this as the single most likely miss.

- [ ] **Step 3: Record and commit**

```bash
git add design/figma.md
git commit -m "design: add button components"
```

---

### Task 8: Build the frosted card, info strip and bottom navigation

**Files:**
- Modify: `design/figma.md`

**Interfaces:**
- Produces: `Card/Frosted` (24 dp radius, white at 92% opacity), `Strip/Info` (blue informational row), `Nav/Bottom` (floating rounded bar, five items, raised centre Scan button).

- [ ] **Step 1: Build the frosted card and info strip**

Opacity is set at the **paint** level, not inside the colour object.

```js
await figma.loadFontAsync({ family: "Inter", style: "Regular" });
const vars = {};
for (const v of await figma.variables.getLocalVariablesAsync()) vars[v.name] = v;
const bind = (n, name, opacity) => {
  const p = figma.variables.setBoundVariableForPaint(
    { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[name]);
  n.fills = [opacity == null ? p : Object.assign({}, p, { opacity })];
};

// Frosted card — 92% is the minimum opacity that keeps body text at AA
const card = figma.createAutoLayout('VERTICAL', {
  name: 'Card/Frosted', itemSpacing: 16,
  paddingTop: 24, paddingBottom: 24, paddingLeft: 20, paddingRight: 20
});
card.cornerRadius = 24;
bind(card, 'surface/frosted', 0.92);
figma.currentPage.appendChild(card);
card.resize(364, 200);
card.primaryAxisSizingMode = 'FIXED';
card.counterAxisSizingMode = 'FIXED';
card.x = 200; card.y = 640;
const cardComp = figma.createComponent();
cardComp.name = 'Card/Frosted';
cardComp.resize(364, 200);
cardComp.x = 600; cardComp.y = 640;
cardComp.appendChild(card);
cardComp.description = "Frosted surface. Opacity must stay at or above 92% — below that, body text fails WCAG AA over the olive canvas.";

// Info strip
const strip = figma.createAutoLayout('HORIZONTAL', {
  name: 'Strip/Info', itemSpacing: 10, paddingTop: 12, paddingBottom: 12,
  paddingLeft: 14, paddingRight: 14, counterAxisAlignItems: 'CENTER'
});
strip.cornerRadius = 12;
bind(strip, 'info/bg');
const dot = figma.createEllipse();
dot.resize(16, 16);
bind(dot, 'info/text');
strip.appendChild(dot);
const st = figma.createText();
st.fontName = { family: "Inter", style: "Regular" };
st.fontSize = 14;
st.lineHeight = { unit: "PIXELS", value: 20 };
st.characters = "Tap anything to change it before saving.";
st.fills = [figma.variables.setBoundVariableForPaint(
  { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars['info/text'])];
strip.appendChild(st);
st.layoutSizingHorizontal = 'FILL';
st.textAutoResize = 'HEIGHT';
figma.currentPage.appendChild(strip);
strip.resize(324, strip.height);
strip.counterAxisSizingMode = 'AUTO';
strip.x = 200; strip.y = 880;
const stripComp = figma.createComponent();
stripComp.name = 'Strip/Info';
stripComp.resize(324, strip.height);
stripComp.x = 600; stripComp.y = 880;
stripComp.appendChild(strip);
stripComp.description = "Informational row. Blue is informational only and never indicates urgency (PRD 4.12).";

return { createdNodeIds: [cardComp.id, stripComp.id], stripTextWidth: st.width };
```

Check `stripTextWidth > 0` in the return value. A near-zero width means the wrapping-text trap was hit and `textAutoResize` needs revisiting.

- [ ] **Step 2: Build the bottom navigation**

```js
await figma.loadFontAsync({ family: "Inter", style: "Medium" });
const vars = {};
for (const v of await figma.variables.getLocalVariablesAsync()) vars[v.name] = v;
const bind = (n, name, op) => {
  const p = figma.variables.setBoundVariableForPaint(
    { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars[name]);
  n.fills = [op == null ? p : Object.assign({}, p, { opacity: op })];
};

const bar = figma.createAutoLayout('HORIZONTAL', {
  name: 'Nav/Bottom', itemSpacing: 0, paddingTop: 10, paddingBottom: 10,
  paddingLeft: 8, paddingRight: 8,
  primaryAxisAlignItems: 'CENTER', counterAxisAlignItems: 'CENTER'
});
bar.cornerRadius = 999;
bind(bar, 'surface/frosted', 0.92);

for (const label of ["Home", "Inventory", "Scan", "Recipes", "Profile"]) {
  const cell = figma.createAutoLayout('VERTICAL', {
    name: `Nav/${label}`, itemSpacing: 4,
    primaryAxisAlignItems: 'CENTER', counterAxisAlignItems: 'CENTER'
  });
  const icon = figma.createEllipse();
  icon.resize(22, 22);
  bind(icon, label === "Scan" ? 'text/on-olive-primary' : 'glyph/dark');
  cell.appendChild(icon);
  const t = figma.createText();
  t.fontName = { family: "Inter", style: "Medium" };
  t.fontSize = 12;
  t.characters = label;
  bind(t, 'text/on-light-primary');
  cell.appendChild(t);
  t.layoutSizingHorizontal = 'HUG';
  bar.appendChild(cell);
  cell.resize(72, 48);                  // 48dp min tap target
  cell.primaryAxisSizingMode = 'FIXED';
  cell.counterAxisSizingMode = 'FIXED';
  if (label === "Scan") bind(cell, 'surface/deep');
  cell.cornerRadius = 999;
}

figma.currentPage.appendChild(bar);
bar.resize(380, 68);
bar.primaryAxisSizingMode = 'FIXED';
bar.counterAxisSizingMode = 'FIXED';
bar.x = 200; bar.y = 1000;
const navComp = figma.createComponent();
navComp.name = 'Nav/Bottom';
navComp.resize(380, 68);
navComp.x = 600; navComp.y = 1000;
navComp.appendChild(bar);
navComp.description = "Floating bottom navigation, inset 16dp from the screen edge — never edge-to-edge. Scan sits centre and elevated so the primary action is reachable one-handed (PRD 4.2). Each cell is 72x48dp to meet the 48dp tap-target minimum.";
await navComp.screenshot();
return { createdNodeIds: [navComp.id] };
```

- [ ] **Step 3: Verify all five labels are visible and no text is clipped**

Inspect the screenshot from Step 2. All five labels legible, Scan visually raised and darker, bar fully rounded.

- [ ] **Step 4: Record and commit**

```bash
git add design/figma.md
git commit -m "design: add frosted card, info strip and bottom navigation"
```

---

### Task 9: Export tokens and assert contrast

**Files:**
- Create: `design/tokens.json` (generated)
- Create: `tools/token_pairs.json`
- Create: `tools/check_contrast.py`

**Interfaces:**
- Consumes: the two variable collections from Tasks 3 and 4.
- Produces: `design/tokens.json` — the design/code contract. Plan 3 generates the Flutter theme from this file, so no hex value is ever hand-copied.

- [ ] **Step 1: Read every variable back out of Figma**

```js
const out = { colour: {}, scale: {} };
const cols = await figma.variables.getLocalVariableCollectionsAsync();
const toHex = ({ r, g, b }) => '#' + [r, g, b]
  .map(x => Math.round(x * 255).toString(16).padStart(2, '0'))
  .join('').toUpperCase();

for (const c of cols) {
  const vars = await Promise.all(
    c.variableIds.map(id => figma.variables.getVariableByIdAsync(id))
  );
  const mode = c.modes[0].modeId;
  for (const v of vars) {
    const val = v.valuesByMode[mode];
    if (c.name === "ShelfLife/Colour") out.colour[v.name] = toHex(val);
    else out.scale[v.name] = val;
  }
}
return out;
```

- [ ] **Step 2: Write the returned JSON to `design/tokens.json`**

Wrap the returned object as:
```json
{
  "$generated": "from Figma file <FILE_KEY> — do not hand-edit; re-run Task 9 Step 1",
  "colour": { "...": "..." },
  "scale":  { "...": "..." }
}
```

- [ ] **Step 3: Declare the legal colour pairs**

Create `tools/token_pairs.json`. Each entry states a foreground token, a background token, and the smallest px size it is used at — which determines whether the 4.5 or 3.0 threshold applies.

```json
[
  {"fg":"text/on-olive-primary",   "bg":"surface/canvas", "minPx":14, "use":"titles, body on canvas"},
  {"fg":"text/on-olive-secondary", "bg":"surface/canvas", "minPx":14, "use":"secondary body on canvas"},
  {"fg":"text/on-deep-tertiary",   "bg":"surface/deep",   "minPx":12, "use":"small print on deep only (D12)"},
  {"fg":"text/on-olive-secondary", "bg":"surface/deep",   "minPx":12, "use":"stat labels"},
  {"fg":"text/on-olive-primary",   "bg":"surface/deep",   "minPx":14, "use":"bottom bar labels"},
  {"fg":"text/on-light-primary",   "bg":"surface/frosted","minPx":16, "use":"card titles"},
  {"fg":"text/on-light-secondary", "bg":"surface/frosted","minPx":14, "use":"card secondary"},
  {"fg":"text/on-light-primary",   "bg":"surface/opaque", "minPx":16, "use":"opaque frosted"},
  {"fg":"text/on-light-secondary", "bg":"surface/opaque", "minPx":14, "use":"opaque frosted"},
  {"fg":"state/amber-text",        "bg":"state/amber-bg", "minPx":12, "use":"amber chip (D11)"},
  {"fg":"state/red-text",          "bg":"state/red-bg",   "minPx":12, "use":"red chip"},
  {"fg":"info/text",               "bg":"info/bg",        "minPx":14, "use":"info strip"},
  {"fg":"text/on-light-primary",   "bg":"surface/field",  "minPx":16, "use":"cream pill button"}
]
```

**Note:** `text/on-deep-tertiary` on `surface/canvas` is deliberately absent — that pair measures 3.91:1 and is illegal per D12.

- [ ] **Step 4: Write the failing test**

Create `tools/check_contrast.py`:

```python
#!/usr/bin/env python3
"""Assert WCAG AA contrast for every declared token pair.

Exits non-zero on any failure, so this is CI-usable.
Large-text threshold (3.0) applies at >=24px regular; everything else needs 4.5.
"""
import json, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def luminance(hex_colour):
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)

def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)

def main():
    tokens = json.loads((ROOT / "design/tokens.json").read_text(encoding="utf-8"))
    pairs = json.loads((ROOT / "tools/token_pairs.json").read_text(encoding="utf-8"))
    colours = tokens["colour"]

    failures = []
    for p in pairs:
        fg_name, bg_name = p["fg"], p["bg"]
        if fg_name not in colours or bg_name not in colours:
            failures.append(f"missing token: {fg_name} or {bg_name}")
            continue
        fg, bg = colours[fg_name], colours[bg_name]
        need = 3.0 if p["minPx"] >= 24 else 4.5
        got = ratio(fg, bg)
        status = "ok  " if got >= need else "FAIL"
        print(f"{status} {got:5.2f} (need {need}) {fg_name} {fg} on {bg_name} {bg} — {p['use']}")
        if got < need:
            failures.append(f"{fg_name} on {bg_name}: {got:.2f} < {need}")

    if failures:
        print(f"\n{len(failures)} contrast failure(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print(f"\nAll {len(pairs)} pairs pass WCAG AA.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run it and confirm it passes**

Run: `python tools/check_contrast.py`
Expected: every line `ok`, final line `All 13 pairs pass WCAG AA.`, exit code 0.

If `state/amber-text` fails, the D11 fix did not make it into Task 3 Step 2 — the value must be `#9E5D00`, not `#B26A00`.

- [ ] **Step 6: Prove the check actually catches a regression**

Temporarily change `state/amber-text` in `design/tokens.json` to `#B26A00` and re-run. Expected: exit code 1 with `state/amber-text on state/amber-bg: 3.86 < 4.5`. Then revert the file.

A test that has never failed is not evidence of anything — this step is what makes the check trustworthy.

- [ ] **Step 7: Commit**

```bash
git add design/tokens.json tools/token_pairs.json tools/check_contrast.py
git commit -m "design: export Figma tokens and add WCAG AA contrast check"
```

---

### Task 10: Assemble the component sheet and verify the whole system

**Files:**
- Modify: `design/figma.md`

- [ ] **Step 1: Lay the components out on a labelled sheet**

Arrange all six components on the `Design System` page in a titled section with a canvas-coloured backing frame, so the frosted surfaces are viewed against the real background rather than Figma's grey.

```js
const vars = {};
for (const v of await figma.variables.getLocalVariablesAsync()) vars[v.name] = v;
await figma.loadFontAsync({ family: "Inter", style: "Semi Bold" });

const board = figma.createFrame();
board.name = "Component sheet";
board.resize(900, 1200);
board.x = 1200; board.y = 100;
board.fills = [figma.variables.setBoundVariableForPaint(
  { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars['surface/canvas'])];

const title = figma.createText();
title.fontName = { family: "Inter", style: "Semi Bold" };
title.fontSize = 20;
title.characters = "ShelfLife — components";
title.fills = [figma.variables.setBoundVariableForPaint(
  { type: 'SOLID', color: { r: 0, g: 0, b: 0 } }, 'color', vars['text/on-olive-primary'])];
board.appendChild(title);
title.x = 40; title.y = 36;

return { createdNodeIds: [board.id, title.id] };
```

Then, in a second call, place one instance of each component inside `board` at 8 dp-grid positions.

- [ ] **Step 2: Screenshot the sheet**

Call `get_screenshot` on the board node with `maxDimension: 2048`.

- [ ] **Step 3: Verify against the checklist**

- [ ] Exactly two freshness chips exist. No green "Fresh" chip anywhere.
- [ ] Both chips carry a dot glyph — urgency is never colour-only.
- [ ] The cream pill is visibly the brightest element; the outlined button is clearly quieter.
- [ ] Every nav cell is at least 48 dp tall, all five labels legible.
- [ ] No clipped or overlapping text anywhere on the sheet.
- [ ] Frosted surfaces read as legible over the olive canvas.

- [ ] **Step 4: Confirm no stray shimmer placeholders remain**

```js
const shimmer = figma.currentPage
  .findAll(n => n.placeholder === true)
  .map(n => ({ id: n.id, name: n.name }));
return { shimmer };
```

Expected: empty array.

- [ ] **Step 5: Commit**

```bash
git add design/figma.md
git commit -m "design: assemble component sheet and verify design system"
```

---

## Self-Review

**Spec coverage.** Spec §8 steps 1–2 (create file, build design system as variables) are covered by Tasks 1, 3, 4, 5. Spec §8 step 4 (derive the Flutter theme from the same token values) is enabled by Task 9's `design/tokens.json`. Spec §9 criterion 3 (automated WCAG AA assertion) is Task 9 Steps 4–6. Spec §9 criterion 4 (fresh renders no chip) is enforced structurally here — no green chip component is ever created — and becomes a golden test in Plan 3. Decisions D4, D11 and D12 each appear as an explicit constraint in the Global Constraints block and in the task that implements them.

**Deliberately out of scope for this plan.** Spec §8 step 3 (author the 16 screens) is the follow-on plan, which consumes the components built here. The 60-glyph illustration set is also deferred: per the screen doc's own "pragmatic path", the five category fallbacks ship first, so glyphs are not a blocker. Ellipse placeholders stand in for glyphs in every component here.

**Placeholder scan.** No `TBD`/`TODO` entries. Every code step contains runnable code. Two intentional `<FILE_KEY>` / `<A_ID>` substitutions exist in Tasks 1 and 6 — these are values produced at runtime by an earlier step in the same task, not unspecified work.

**Type consistency.** Variable names are used identically across tasks: `surface/canvas`, `surface/deep`, `surface/frosted`, `surface/opaque`, `surface/field`, `text/on-light-primary`, `text/on-light-secondary`, `text/on-olive-primary`, `text/on-olive-secondary`, `text/on-deep-tertiary`, `state/amber-text`, `state/amber-bg`, `state/red-text`, `state/red-bg`, `info/text`, `info/bg`, `structure/divider`, `glyph/dark`, `glyph/mid`, `glyph/light`. Task 3 creates 11 + 10 = 21 colour variables, which matches the count asserted in Task 3 Step 3. Task 9's `token_pairs.json` references only names defined in Task 3. The `bindFill` / `bind` helper is redefined locally in each script because `use_figma` calls share no scope — this is intentional, not duplication.
