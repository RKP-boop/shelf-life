# ShelfLife — image generation prompt sheet

Generate these, drop them in one folder, tell me the path, and I'll upload each into the Figma file and wire it to its component. Layouts won't change — every produce item is already a swappable component.

---

## Non-negotiable technical specs

Get these wrong and the assets won't drop in cleanly:

| Spec | Value | Why |
|---|---|---|
| **Background** | **Transparent PNG (alpha)** | Produce sits directly on white cards. A white or coloured background shows as a visible box. |
| **Aspect** | **1:1 square** | Every tile and card slot in the file is square. |
| **Subject inset** | Subject fills ~**76%** of the frame, centred, ~12% margin all round | Matches the existing component padding so nothing needs re-cropping. |
| **Resolution** | **1024 × 1024** minimum | Renders at up to 238 dp on the item-detail hero; below 1024 it softens. |
| **Shadow** | **Include a soft contact shadow** under the subject, or none at all | Never a hard drop shadow — it will fight the card shadows already in the file. |
| **File naming** | Exactly as listed below | I match files to components by name. Rename freely, but tell me the mapping. |

---

## Shared style preamble

**Paste this before every produce prompt.** It's what makes 23 separate generations read as one set rather than a pile of stock renders.

> Stylized 3D render, soft-matte clay-like finish, gently rounded friendly forms. Single soft light source from the upper left, producing a subtle specular highlight on the upper-left surface and gentle falloff to the lower right. Soft diffuse ambient contact shadow directly beneath the subject. Semi-matte surface with a faint sheen — never wet, glossy, or plastic. Saturated but natural colour, slightly desaturated toward pastel. Clean silhouette, no outlines. Three-quarter view from roughly 20 degrees above the horizon. Fully transparent background. Centred, square 1:1 framing with the subject occupying about 76% of the frame. Consistent scale and lighting across the whole set. No text, no props, no surface or table, no reflections, no photorealism.

**Palette to anchor against** (these are the actual tokens in the file, so renders will sit naturally alongside the UI):

```
greens   #1F7A45  #3FA45F  #7FCB8A
red      #D8452F  #F2705A
orange   #F0912B
yellow   #F5C63C
cream    #FBF3E4
brown    #A9713C
```

**Avoid list** — append if a model drifts:

> no photorealism, no glossy plastic, no wet look, no drop shadow, no background, no table surface, no text or labels, no watermark, no hands, no cutting board, no bowl unless specified

---

## Tier 1 — referenced directly on the screens (10)

These appear by name in the built screens. Highest priority.

| File name | Prompt (after the preamble) |
|---|---|
| `produce-spinach.png` | A small bunch of fresh spinach leaves, four or five broad rounded leaves fanning upward from a short pale stem base, deep and mid green with a lighter leaf catching the highlight. |
| `produce-milk.png` | A one-litre milk carton-bottle, soft rounded rectangular body in warm off-white cream, a short neck and a small blue cap, and a pale mint label band across the middle. |
| `produce-tomato.png` | A single ripe red tomato, plump and round with a slight vertical lobing, topped by a small five-point green calyx and a short stem. |
| `produce-paneer.png` | A rectangular block of fresh paneer, soft matte off-white with very slightly rounded edges and a faint crumbly surface texture, with one small cube resting beside it. |
| `produce-banana.png` | A single ripe yellow banana, gently curved, with a small brown stem tip and a soft faceted surface. |
| `produce-avocado.png` | An avocado cut in half, dark green textured skin, pale yellow-green flesh, and a large round glossy brown pit centred in the visible half. |
| `produce-broccoli.png` | A single head of broccoli, a cluster of rounded deep-green florets on a short pale green stalk. |
| `produce-onion.png` | A single red onion, rounded with a slight teardrop taper, deep purple-red papery skin with subtle vertical striations and a small dry root tip. |
| `produce-atta.png` | A small sealed paper bag of Indian atta wheat flour, soft cream-brown kraft paper, gently rounded and slightly bulging, with a folded and sealed top. |
| `produce-coriander.png` | A small tied bunch of fresh coriander, feathery bright-green serrated leaves on slender pale stems. |

## Tier 2 — category coverage and common items (13)

| File name | Prompt (after the preamble) |
|---|---|
| `produce-potato.png` | Two small brown-skinned potatoes, rounded and slightly irregular, matte earthy tan with subtle shallow eyes. |
| `produce-cauliflower.png` | A single head of cauliflower, tight creamy-white curd surrounded by a few short pale green leaves at the base. |
| `produce-curd.png` | A small round tub of set curd, soft white with a smooth matte surface, in a shallow pale container with a slight rim. |
| `produce-rice.png` | A small sealed bag of white basmati rice, soft translucent-cream pouch, gently rounded, with a folded sealed top. |
| `produce-ginger.png` | A single knob of fresh ginger, irregular branching form, matte pale tan skin with a faint fibrous texture. |
| `produce-garlic.png` | A single bulb of garlic, rounded with visible clove segmentation under papery off-white skin, and one loose clove beside it. |
| `produce-lemon.png` | A single bright yellow lemon, oval with a small nub at one end, and one small glossy green leaf attached. |
| `produce-carrot.png` | A single orange carrot, tapering, with a short trimmed green top and faint horizontal surface ridges. |
| `produce-capsicum.png` | A single green bell pepper, glossy-matte with three rounded lobes and a short curved green stem. |
| `produce-apple.png` | A single red apple, round with a subtle shoulder, a short brown stem and one small green leaf. |
| `produce-cream.png` | A small carton of fresh cream, upright rounded rectangular pack in soft cream-white with a pale green cap and band. |
| `produce-peas-frozen.png` | A small handful of bright green frozen peas, rounded spheres clustered loosely with a very faint frosted surface. |
| `produce-cucumber.png` | A single green cucumber, long and gently tapered, matte deep green skin with subtle lengthwise ridging. |

**The full set is ~60 items.** Your screen doc lists them by category. Tier 1 and 2 cover every item any built screen currently shows, plus one fallback per PRD category, so the app looks complete. Extend later from that list using the same preamble.

---

## Dish photographs (5)

These are **photographs, not 3D renders** — a different preamble. Use this one instead:

> Overhead food photograph, natural soft daylight from one side, shallow depth of field, shot on a plain warm off-white surface. Appetising and freshly made, generous but tidy portion in a simple neutral ceramic bowl or plate. Muted natural colour grading, gentle shadows, no harsh highlights. Square 1:1 framing, dish centred and filling most of the frame. No text, no cutlery clutter, no hands, no busy props, no watermark.

| File name | Dish |
|---|---|
| `dish-palak-paneer.png` | Palak paneer — creamy dark green spinach gravy with visible soft white paneer cubes, a light swirl of cream on top |
| `dish-aloo-gobi.png` | Aloo gobi — dry turmeric-yellow potato and cauliflower curry, lightly browned edges, scattered coriander |
| `dish-vegetable-pulao.png` | Vegetable pulao — fluffy long-grain basmati with peas, carrot and beans, whole spices visible |
| `dish-paneer-bhurji.png` | Paneer bhurji — crumbled paneer scramble with onion, tomato and green chilli, coriander on top |
| `dish-avocado-toast.png` | Avocado toast — thick sourdough slice with mashed avocado, chilli flakes and a lemon wedge |

Unlike the produce, these **may have their own background** — they sit inside a tinted panel in the recipe cards, so a warm off-white surface reads correctly. Transparency is not required here.

---

## Optional hero (1)

| File name | Prompt |
|---|---|
| `hero-flatlay.png` | Overhead photograph of fresh Indian vegetables and greens arranged on a warm off-white surface — spinach, tomatoes, red onions, green chillies, coriander, a cut lemon. Soft directional daylight, rich natural colour, shallow depth of field, editorial cookbook styling. Landscape 3:2. No text, no hands, no watermark. |

Used behind the auth landing screen, replacing the current abstract botanical composition.

---

## Where each asset lands

Once you hand me the folder, I upload via `upload_assets` and wire them in. The produce components are consumed by these slots, so a swap propagates everywhere at once:

| Asset | Appears in |
|---|---|
| Produce items | Home category tiles, "Use these first" cards, inventory rows, review rows, item-detail hero, shopping-list rows, multi-select rows, notification thumbnails, autocomplete rows, statistics "most rescued" |
| Dish photos | Recipes list card panels, recipe-detail hero, Home "Cook tonight" |
| Hero flat-lay | Auth landing top panel |

**Generation tip:** produce Tier 1 first, hand me those ten, and let me wire them in so you can see the real thing in context before generating the remaining eighteen. If the style needs adjusting, you'll have only spent ten renders finding out.
