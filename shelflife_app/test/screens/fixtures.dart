/// Shared preview data.
///
/// Fixed dates, never DateTime.now(): a golden that shifts with the clock is a
/// golden that has stopped meaning anything.
library;

import 'package:shelflife_app/core/engines/recipe_scorer.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/models/inventory_item.dart';
import 'package:shelflife_app/models/models.dart';

final fixedToday = DateTime(2026, 8, 28, 18, 20);

InventoryItem item({
  required String name,
  required String glyph,
  required FoodCategory category,
  required double quantity,
  required String unit,
  required int daysLeft,
  StorageLocation storage = StorageLocation.fridge,
  ExpirySource source = ExpirySource.categoryDefault,
}) {
  final midnight =
      DateTime(fixedToday.year, fixedToday.month, fixedToday.day);
  return InventoryItem(
    id: 'i-${name.toLowerCase().replaceAll(' ', '-')}',
    userId: 'u1',
    ingredientId: glyph,
    productName: name,
    category: category,
    quantity: quantity,
    unit: unit,
    storage: storage,
    purchaseDate: midnight.subtract(const Duration(days: 2)),
    expiryDate: midnight.add(Duration(days: daysLeft)),
    expirySource: source,
    expiryReason: 'Typical for $name kept in the ${storage.name}.',
    glyphKey: glyph,
    createdAt: midnight.subtract(const Duration(days: 2)),
    updatedAt: midnight.subtract(const Duration(days: 2)),
  );
}

final needsUsing = <InventoryItem>[
  item(
    name: 'Spinach',
    glyph: 'spinach',
    category: FoodCategory.vegetables,
    quantity: 250,
    unit: 'g',
    daysLeft: 0,
  ),
  item(
    name: 'Paneer',
    glyph: 'paneer',
    category: FoodCategory.dairy,
    quantity: 200,
    unit: 'g',
    daysLeft: 0,
    source: ExpirySource.printed,
  ),
  item(
    name: 'Coriander',
    glyph: 'coriander',
    category: FoodCategory.vegetables,
    quantity: 1,
    unit: 'bunch',
    daysLeft: 1,
  ),
  item(
    name: 'Amul Taaza',
    glyph: 'milk',
    category: FoodCategory.dairy,
    quantity: 1,
    unit: 'L',
    daysLeft: 2,
    source: ExpirySource.printed,
  ),
];

/// Deliberately mixed: real renders and category fallbacks, every storage
/// location, and one long name that has to ellipsize.
final fullInventory = <InventoryItem>[
  ...needsUsing,
  item(
    name: 'Tomatoes',
    glyph: 'tomato',
    category: FoodCategory.vegetables,
    quantity: 6,
    unit: 'pcs',
    daysLeft: 4,
  ),
  item(
    name: 'Onions',
    glyph: 'onion',
    category: FoodCategory.vegetables,
    quantity: 1,
    unit: 'kg',
    daysLeft: 21,
    storage: StorageLocation.pantry,
  ),
  item(
    name: 'Potatoes',
    glyph: 'potato',
    category: FoodCategory.vegetables,
    quantity: 2,
    unit: 'kg',
    daysLeft: 25,
    storage: StorageLocation.pantry,
  ),
  item(
    name: 'Curd',
    glyph: 'curd',
    category: FoodCategory.dairy,
    quantity: 400,
    unit: 'g',
    daysLeft: 5,
  ),
  item(
    name: 'Bananas',
    glyph: 'banana',
    category: FoodCategory.fruits,
    quantity: 5,
    unit: 'pcs',
    daysLeft: 3,
    storage: StorageLocation.counter,
  ),
  item(
    name: 'Basmati rice',
    glyph: 'rice',
    category: FoodCategory.pantry,
    quantity: 5,
    unit: 'kg',
    daysLeft: 300,
    storage: StorageLocation.pantry,
  ),
  item(
    name: 'Green peas',
    glyph: 'peas-frozen',
    category: FoodCategory.frozen,
    quantity: 500,
    unit: 'g',
    daysLeft: 90,
    storage: StorageLocation.freezer,
  ),
  // No individual render: exercises the category fallback glyph.
  item(
    name: 'Garam masala',
    glyph: 'garam-masala',
    category: FoodCategory.pantry,
    quantity: 100,
    unit: 'g',
    daysLeft: 200,
    storage: StorageLocation.pantry,
  ),
];

final suggestions = <RecipeMatch>[
  const RecipeMatch(
    id: 'palak-paneer',
    name: 'Palak paneer',
    prepMinutes: 30,
    imageKey: 'palak-paneer',
    totalRequired: 7,
    haveCount: 6,
    haveNames: ['spinach', 'paneer', 'onion', 'tomato', 'ginger', 'garlic'],
    missingNames: ['cream'],
    urgentNames: ['spinach', 'paneer'],
    score: 0.87,
  ),
  const RecipeMatch(
    id: 'paneer-bhurji',
    name: 'Paneer bhurji',
    prepMinutes: 20,
    imageKey: 'paneer-bhurji',
    totalRequired: 6,
    haveCount: 6,
    haveNames: ['paneer', 'onion', 'tomato', 'capsicum', 'coriander', 'atta'],
    missingNames: [],
    urgentNames: ['paneer', 'coriander'],
    score: 0.81,
  ),
  const RecipeMatch(
    id: 'aloo-gobi',
    name: 'Aloo gobi',
    prepMinutes: 35,
    imageKey: 'aloo-gobi',
    totalRequired: 6,
    haveCount: 4,
    haveNames: ['potato', 'onion', 'tomato', 'coriander'],
    missingNames: ['cauliflower', 'ginger'],
    urgentNames: ['coriander'],
    score: 0.64,
  ),
];

const stats = KitchenStats(
  activeItems: 12,
  expiringSoon: 4,
  dueToday: 2,
  mealsRescued: 18,
  valueRescuedInr: 1240,
  currentStreak: 6,
  pctUsedInTime: 82,
);
