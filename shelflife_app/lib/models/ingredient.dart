import 'enums.dart';

/// The keystone type (spec §3). OCR text, typed names and recipe references all
/// resolve to one of these before anything else works.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.canonicalName,
    required this.category,
    required this.defaultUnit,
    required this.glyphKey,
    this.shelfLifeFridgeDays,
    this.shelfLifeFreezerDays,
    this.shelfLifePantryDays,
    this.shelfLifeCounterDays,
    this.estPriceInr,
  });

  final String id;
  final String canonicalName;
  final FoodCategory category;
  final String defaultUnit;

  /// Names an asset in the Figma library — a real render, or a category
  /// fallback for the 41 ingredients that have no individual image.
  final String glyphKey;

  final int? shelfLifeFridgeDays;
  final int? shelfLifeFreezerDays;
  final int? shelfLifePantryDays;
  final int? shelfLifeCounterDays;

  /// Rough Indian retail rate. Only ever used for the estimated-value stat, and
  /// always labelled as an estimate in the UI.
  final double? estPriceInr;

  /// Shelf life for one storage location, or null when the item is not
  /// sensibly kept that way.
  int? shelfLifeFor(StorageLocation storage) => switch (storage) {
        StorageLocation.fridge => shelfLifeFridgeDays,
        StorageLocation.freezer => shelfLifeFreezerDays,
        StorageLocation.pantry => shelfLifePantryDays,
        StorageLocation.counter => shelfLifeCounterDays,
      };

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        id: j['id'] as String,
        canonicalName: j['canonical_name'] as String,
        category: FoodCategory.values.byName(j['category'] as String),
        defaultUnit: j['default_unit'] as String,
        glyphKey: j['glyph_key'] as String,
        shelfLifeFridgeDays: j['shelf_life_fridge_days'] as int?,
        shelfLifeFreezerDays: j['shelf_life_freezer_days'] as int?,
        shelfLifePantryDays: j['shelf_life_pantry_days'] as int?,
        shelfLifeCounterDays: j['shelf_life_counter_days'] as int?,
        estPriceInr: (j['est_price_inr'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'canonical_name': canonicalName,
        'category': category.wire,
        'default_unit': defaultUnit,
        'glyph_key': glyphKey,
        'shelf_life_fridge_days': shelfLifeFridgeDays,
        'shelf_life_freezer_days': shelfLifeFreezerDays,
        'shelf_life_pantry_days': shelfLifePantryDays,
        'shelf_life_counter_days': shelfLifeCounterDays,
        'est_price_inr': estPriceInr,
      };
}
