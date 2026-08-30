/// Resolves an ingredient's `glyph_key` to an asset.
///
/// 24 of the 65 seeded ingredients have an individual render; the other 41 fall
/// back to one of five category glyphs. `tools/check_asset_coverage.py` asserts
/// every key in the database resolves to something that exists, so a blank tile
/// cannot reach the app unnoticed.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.g.dart';
import '../../models/enums.dart';

class ProduceImage extends StatelessWidget {
  const ProduceImage({
    super.key,
    required this.glyphKey,
    this.size = 48,
    this.category,
  });

  /// Comes from `ingredients.glyph_key`.
  final String glyphKey;

  final double size;

  /// Used to pick a fallback when the key is missing or unrecognised.
  final FoodCategory? category;

  /// The 23 keys with a real 3D render.
  static const realRenders = {
    'apple', 'atta', 'avocado', 'banana', 'broccoli', 'capsicum', 'carrot',
    'cauliflower', 'coriander', 'cream', 'cucumber', 'curd', 'garlic',
    'ginger', 'lemon', 'milk', 'onion', 'paneer', 'peas-frozen', 'potato',
    'rice', 'spinach', 'tomato',
  };

  static const categoryFallback = {
    FoodCategory.dairy: 'cat-dairy',
    FoodCategory.fruits: 'cat-fruits',
    FoodCategory.vegetables: 'cat-vegetables',
    FoodCategory.pantry: 'cat-pantry',
    FoodCategory.frozen: 'cat-frozen',
    FoodCategory.other: 'cat-pantry',
  };

  /// The asset path, resolving through the fallback when needed.
  String get assetPath {
    if (realRenders.contains(glyphKey)) {
      return 'assets/produce/$glyphKey.png';
    }
    if (glyphKey.startsWith('cat-')) {
      return 'assets/glyph/$glyphKey.png';
    }
    final fallback = categoryFallback[category ?? FoodCategory.other]!;
    return 'assets/glyph/$fallback.png';
  }

  @override
  Widget build(BuildContext context) => Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // A missing asset must not blank the row. The neutral mark keeps the
        // layout intact and stays visibly a placeholder rather than pretending
        // to be food.
        errorBuilder: (_, _, _) => Icon(
          Icons.eco_outlined,
          size: size * 0.5,
          color: T.accentPrimary.withValues(alpha: 0.35),
        ),
      );
}

/// Produce on a tinted tile — the pattern used by category tiles, item rows and
/// review rows.
class ProduceTile extends StatelessWidget {
  const ProduceTile({
    super.key,
    required this.glyphKey,
    this.category,
    this.size = 58,
    this.tint,
    this.radius,
  });

  final String glyphKey;
  final FoodCategory? category;
  final double size;
  final Color? tint;
  final double? radius;

  /// Tint follows the category, so fruit reads warm and greens read cool.
  static Color tintFor(FoodCategory? c) => switch (c) {
        FoodCategory.fruits => T.tintPeach,
        FoodCategory.pantry => T.tintLemon,
        _ => T.tintMint,
      };

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint ?? tintFor(category),
          borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: ProduceImage(
          glyphKey: glyphKey,
          category: category,
          size: size * 0.9,
        ),
      );
}

/// Dish photograph for recipe cards and the recipe hero.
class DishImage extends StatelessWidget {
  const DishImage({super.key, required this.imageKey, this.size = 92});

  final String? imageKey;
  final double size;

  static const known = {
    'aloo-gobi', 'avocado-toast', 'palak-paneer', 'paneer-bhurji',
    'vegetable-pulao',
  };

  @override
  Widget build(BuildContext context) {
    final key = imageKey;
    // Several seeded recipes borrow a produce render where no dish photograph
    // exists — curd raita shown as curd, for instance.
    if (key != null && !known.contains(key)) {
      return ProduceImage(glyphKey: key, size: size);
    }
    return Image.asset(
      'assets/dish/${key ?? 'palak-paneer'}.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(
        Icons.ramen_dining_outlined,
        size: size * 0.5,
        color: T.accentPrimary.withValues(alpha: 0.35),
      ),
    );
  }
}
