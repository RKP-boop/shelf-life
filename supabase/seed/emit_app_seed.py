"""Emits the bundled seed asset the Flutter app ships with.

The app is offline-first, so it cannot fetch the catalogue on first run — a
phone with no connection still has to get a working product. It therefore
carries the same reference data Postgres holds.

The point of generating it from `data.py` rather than hand-maintaining a second
copy is that the two cannot drift. One source, two outputs: SQL for Postgres
(generate.py) and JSON for the app (this file).

Ids are `md5(natural_key)` formatted as a uuid, exactly as migration 006 makes
Postgres compute them. That is what lets a queued `inventory_items` insert
written offline satisfy its foreign key when it finally syncs.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

import data

OUT = pathlib.Path(__file__).resolve().parents[2] / "shelflife_app" / "assets" / "seed" / "reference.json"


def det_uuid(natural_key: str) -> str:
    """md5 of the natural key, formatted as a uuid.

    Must stay byte-identical to `md5(...)::uuid` in Postgres and to
    `Seed.deterministicId` in Dart. All three are asserted against each other
    by `tools/check_seed_ids.py`.
    """
    h = hashlib.md5(natural_key.encode("utf-8")).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def build() -> dict:
    ingredients = []
    for (name, category, unit, glyph, fridge, freezer, pantry, counter,
         price) in data.INGREDIENTS:
        ingredients.append({
            "id": det_uuid(name),
            "canonical_name": name,
            "category": category,
            "default_unit": unit,
            "glyph_key": glyph,
            "shelf_life_fridge_days": fridge,
            "shelf_life_freezer_days": freezer,
            "shelf_life_pantry_days": pantry,
            "shelf_life_counter_days": counter,
            "est_price_inr": price,
        })

    known = {i["canonical_name"] for i in ingredients}

    aliases = [
        {"alias": alias, "canonical": target}
        for alias, target in data.ALIASES.items()
    ]

    recipes = []
    for (name, prep, servings, difficulty, category, image, steps,
         ings) in data.RECIPES:
        recipes.append({
            "id": det_uuid(name.lower()),
            "name": name,
            "prep_minutes": prep,
            "servings": servings,
            "difficulty": difficulty,
            "category": category,
            "image_key": image,
            "method_steps": steps,
            "ingredients": [
                {
                    "ingredient_id": det_uuid(iname),
                    "canonical_name": iname,
                    "quantity": qty,
                    "unit": unit,
                    "optional": optional,
                }
                for (iname, qty, unit, optional) in ings
            ],
        })

    products = [
        {
            "barcode": barcode,
            "product_name": pname,
            "brand": brand,
            "ingredient_id": det_uuid(ingredient) if ingredient else None,
            "category": category,
            "pack_size": pack,
            "verified": True,
        }
        for (barcode, pname, brand, ingredient, category, pack) in data.PRODUCTS
    ]

    # The same referential checks generate.py runs. A dangling reference here
    # would surface in the app as a blank tile or a recipe that can never
    # match, which is much harder to trace than a failure at build time.
    errors = []
    for alias in aliases:
        if alias["canonical"] not in known:
            errors.append(f"alias {alias['alias']!r} -> unknown "
                          f"{alias['canonical']!r}")
    for recipe in recipes:
        for row in recipe["ingredients"]:
            if row["canonical_name"] not in known:
                errors.append(f"recipe {recipe['name']!r} references unknown "
                              f"ingredient {row['canonical_name']!r}")
    for product in products:
        if product["ingredient_id"] is None:
            errors.append(f"product {product['barcode']} has no ingredient")
    if errors:
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        raise SystemExit(f"{len(errors)} broken references; nothing written")

    return {
        # Bumped whenever the contents change, so the app knows to re-seed a
        # store written by an older build.
        "version": 1,
        "ingredients": ingredients,
        "aliases": aliases,
        "recipes": recipes,
        "products": products,
    }


def main() -> None:
    payload = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    # Compact: this ships inside the APK, and the newlines are not read by
    # anyone.
    OUT.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    size = OUT.stat().st_size
    print(f"wrote {OUT.relative_to(OUT.parents[3])} ({size / 1024:.0f} KB)")
    print(f"  {len(payload['ingredients'])} ingredients, "
          f"{len(payload['aliases'])} aliases, "
          f"{len(payload['recipes'])} recipes, "
          f"{len(payload['products'])} products")
    print(f"  spinach -> {det_uuid('spinach')}")


if __name__ == "__main__":
    main()
