#!/usr/bin/env python3
"""Assert every database glyph_key and image_key resolves to a Figma component.

This guards a real contract. `ingredients.glyph_key` and `recipes.image_key` are
plain text in Postgres with nothing enforcing that the named asset exists — so a
typo, or an ingredient added without a matching render, shows up as a blank tile
in the running app rather than as an error anywhere.

The component inventory below is exported from the Figma file. Regenerate it by
listing COMPONENT nodes matching ^(Produce|Glyph|Dish)/ and updating ASSETS.

Usage:  python tools/check_asset_coverage.py
Exit:   0 every key resolves, 1 otherwise
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "supabase" / "seed"))
import data  # noqa: E402

# Exported from Figma file COwU4NcifaHygTqCHUliS8, 2026-08-27. 33 components.
ASSETS = {
    "Produce": {
        "apple", "atta", "avocado", "banana", "broccoli", "capsicum", "carrot",
        "cauliflower", "coriander", "cream", "cucumber", "curd", "garlic",
        "ginger", "lemon", "milk", "onion", "paneer", "peas-frozen", "potato",
        "rice", "spinach", "tomato",
    },
    "Glyph": {
        "cat-dairy", "cat-frozen", "cat-fruits", "cat-pantry", "cat-vegetables",
    },
    "Dish": {
        "aloo-gobi", "avocado-toast", "palak-paneer", "paneer-bhurji",
        "vegetable-pulao",
    },
}

CATEGORY_FALLBACK = {
    "dairy": "cat-dairy", "fruits": "cat-fruits", "vegetables": "cat-vegetables",
    "pantry": "cat-pantry", "frozen": "cat-frozen", "other": "cat-pantry",
}


def main() -> int:
    produce = ASSETS["Produce"]
    glyphs = ASSETS["Glyph"]
    dishes = ASSETS["Dish"]
    resolvable = produce | glyphs

    errors: list[str] = []

    # ---- every ingredient's glyph_key must exist -------------------------
    used_produce: set[str] = set()
    used_glyph: set[str] = set()
    for name, category, _unit, glyph, *_ in data.INGREDIENTS:
        if glyph not in resolvable:
            errors.append(f"ingredient '{name}': glyph_key '{glyph}' has no component")
            continue
        (used_produce if glyph in produce else used_glyph).add(glyph)
        # a fallback must be the one matching the ingredient's own category,
        # otherwise a pantry item could show a vegetable marker
        if glyph in glyphs and glyph != CATEGORY_FALLBACK[category]:
            errors.append(
                f"ingredient '{name}' ({category}): uses '{glyph}' but its "
                f"category maps to '{CATEGORY_FALLBACK[category]}'")

    # ---- every recipe's image_key must exist ------------------------------
    used_dish: set[str] = set()
    for name, *rest in data.RECIPES:
        image = rest[4]
        if image is None:
            errors.append(f"recipe '{name}': no image_key")
        elif image in dishes:
            used_dish.add(image)
        elif image in produce:
            # a recipe may legitimately borrow a produce render (e.g. a raita
            # shown as curd) when no dish photograph exists for it
            used_produce.add(image)
        else:
            errors.append(f"recipe '{name}': image_key '{image}' has no component")

    # ---- every category needs a fallback ---------------------------------
    for category, fallback in CATEGORY_FALLBACK.items():
        if fallback not in glyphs:
            errors.append(f"category '{category}' maps to missing fallback '{fallback}'")

    # ---- report ----------------------------------------------------------
    print("asset coverage")
    print(f"  ingredients            {len(data.INGREDIENTS)}")
    print(f"    on a real render     {sum(1 for r in data.INGREDIENTS if r[3] in produce)}")
    print(f"    on a category glyph  {sum(1 for r in data.INGREDIENTS if r[3] in glyphs)}")
    print(f"  recipes                {len(data.RECIPES)}")
    print(f"  components available   {len(produce)} produce, {len(glyphs)} fallback, {len(dishes)} dish")
    print()

    unused = (produce - used_produce) | (glyphs - used_glyph) | (dishes - used_dish)
    if unused:
        print(f"  note: {len(unused)} component(s) not referenced by any row: "
              f"{', '.join(sorted(unused))}")
        print("        (not an error — available for items added later)")
        print()

    if errors:
        print(f"{len(errors)} unresolved reference(s):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print("every glyph_key and image_key resolves to a Figma component")
    return 0


if __name__ == "__main__":
    sys.exit(main())
