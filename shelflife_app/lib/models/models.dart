/// Remaining models. Grouped in one file deliberately: each is a small data
/// holder with the same shape, and splitting them across seven files would add
/// navigation cost without adding clarity.
library;

import 'enums.dart';
import 'inventory_item.dart' show InventoryItem;

// ---------------------------------------------------------------- profile

class Profile {
  const Profile({required this.id, this.displayName, required this.createdAt});

  final String id;
  final String? displayName;
  final DateTime createdAt;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        displayName: j['display_name'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'created_at': createdAt.toIso8601String(),
      };
}

// ------------------------------------------------------- consumption event

/// Append-only history. FR-09's "meals rescued", "money saved", the streak and
/// "% used in time" are not computable from a mutable inventory row, because
/// the row is gone once the item is consumed.
///
/// `removed` is recorded because that percentage needs a denominator. Nothing
/// in the app ever surfaces a waste count (Principle 3).
class ConsumptionEvent {
  const ConsumptionEvent({
    required this.id,
    required this.userId,
    required this.productName,
    required this.kind,
    required this.occurredAt,
    this.ingredientId,
    this.quantity,
    this.unit,
    this.expiryDate,
    this.estValueInr,
    this.recipeId,
  });

  final String id;
  final String userId;
  final String? ingredientId;
  final String productName;
  final ConsumptionKind kind;
  final double? quantity;
  final String? unit;

  /// The item's expiry at the moment of the event, so "used in time" stays
  /// answerable without keeping the inventory row.
  final DateTime? expiryDate;

  final double? estValueInr;
  final String? recipeId;
  final DateTime occurredAt;

  bool get countsAsRescued => kind == ConsumptionKind.used;

  factory ConsumptionEvent.fromJson(Map<String, dynamic> j) => ConsumptionEvent(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        ingredientId: j['ingredient_id'] as String?,
        productName: j['product_name'] as String,
        kind: ConsumptionKind.values.byName(j['kind'] as String),
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        expiryDate: j['expiry_date'] == null
            ? null
            : DateTime.parse(j['expiry_date'] as String),
        estValueInr: (j['est_value_inr'] as num?)?.toDouble(),
        recipeId: j['recipe_id'] as String?,
        occurredAt: DateTime.parse(j['occurred_at'] as String),
      );

  Map<String, dynamic> toJson({bool forWire = false}) => {
        'id': id,
        if (!forWire) 'user_id': userId,
        'ingredient_id': ingredientId,
        'product_name': productName,
        'kind': kind.name,
        'quantity': quantity,
        'unit': unit,
        'expiry_date':
            expiryDate == null ? null : InventoryItem.ymd(expiryDate!),
        'est_value_inr': estValueInr,
        'recipe_id': recipeId,
        'occurred_at': occurredAt.toIso8601String(),
      };
}

// ------------------------------------------------------ shopping list item

/// BR-06: independent of inventory until the user confirms a purchase.
/// Nothing here writes to inventory implicitly.
class ShoppingListItem {
  const ShoppingListItem({
    required this.id,
    required this.userId,
    required this.productName,
    required this.source,
    required this.createdAt,
    this.ingredientId,
    this.quantity = 1,
    this.unit,
    this.sourceRecipeId,
    this.sourceRecipeName,
    this.purchased = false,
  });

  final String id;
  final String userId;
  final String? ingredientId;
  final String productName;
  final double quantity;
  final String? unit;
  final ShoppingSource source;
  final String? sourceRecipeId;

  /// Denormalised for display, so the caption reads "Added from Palak Paneer"
  /// without a join while offline.
  final String? sourceRecipeName;

  final bool purchased;
  final DateTime createdAt;

  /// The caption screen 39 renders beneath the name. The enum IS the caption.
  String? get caption => switch (source) {
        ShoppingSource.recipe =>
          sourceRecipeName == null ? 'Added from a recipe' : 'Added from $sourceRecipeName',
        ShoppingSource.ranOut => 'You have run out',
        ShoppingSource.manual => null,
      };

  ShoppingListItem copyWith({bool? purchased, double? quantity}) =>
      ShoppingListItem(
        id: id,
        userId: userId,
        ingredientId: ingredientId,
        productName: productName,
        quantity: quantity ?? this.quantity,
        unit: unit,
        source: source,
        sourceRecipeId: sourceRecipeId,
        sourceRecipeName: sourceRecipeName,
        purchased: purchased ?? this.purchased,
        createdAt: createdAt,
      );

  factory ShoppingListItem.fromJson(Map<String, dynamic> j) => ShoppingListItem(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        ingredientId: j['ingredient_id'] as String?,
        productName: j['product_name'] as String,
        quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
        unit: j['unit'] as String?,
        source: ShoppingSourceWire.parse(j['source'] as String),
        sourceRecipeId: j['source_recipe_id'] as String?,
        sourceRecipeName: j['source_recipe_name'] as String?,
        purchased: j['purchased'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson({bool forWire = false}) => {
        'id': id,
        if (!forWire) 'user_id': userId,
        'ingredient_id': ingredientId,
        'product_name': productName,
        'quantity': quantity,
        'unit': unit,
        'source': source.wire,
        'source_recipe_id': sourceRecipeId,
        // not a Postgres column; local display only
        if (!forWire) 'source_recipe_name': sourceRecipeName,
        'purchased': purchased,
        'created_at': createdAt.toIso8601String(),
      };
}

// ----------------------------------------------------------------- recipe

class RecipeIngredientRow {
  const RecipeIngredientRow({
    required this.ingredientId,
    required this.canonicalName,
    this.quantity,
    this.unit,
    this.optional = false,
  });

  final String ingredientId;
  final String canonicalName;
  final double? quantity;
  final String? unit;
  final bool optional;

  /// "500 g" — or just the name when the seed gave no quantity.
  String get quantityLabel {
    if (quantity == null) return '';
    final q = quantity! % 1 == 0
        ? quantity!.toInt().toString()
        : quantity!.toStringAsFixed(2);
    return unit == null ? q : '$q $unit';
  }

  factory RecipeIngredientRow.fromJson(Map<String, dynamic> j) =>
      RecipeIngredientRow(
        ingredientId: j['ingredient_id'] as String,
        canonicalName: (j['canonical_name'] ??
            (j['ingredients'] as Map?)?['canonical_name'] ??
            '') as String,
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        optional: j['optional'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'ingredient_id': ingredientId,
        'canonical_name': canonicalName,
        'quantity': quantity,
        'unit': unit,
        'optional': optional,
      };
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.prepMinutes,
    required this.servings,
    required this.difficulty,
    required this.methodSteps,
    required this.ingredients,
    this.category,
    this.imageKey,
  });

  final String id;
  final String name;
  final int prepMinutes;
  final int servings;
  final String difficulty;
  final String? category;

  /// Display-only and never queried, which is why it stays JSON (D5).
  final List<String> methodSteps;

  final List<RecipeIngredientRow> ingredients;
  final String? imageKey;

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        name: j['name'] as String,
        prepMinutes: j['prep_minutes'] as int,
        servings: j['servings'] as int? ?? 4,
        difficulty: j['difficulty'] as String? ?? 'Easy',
        category: j['category'] as String?,
        methodSteps: ((j['method_steps'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        ingredients: ((j['recipe_ingredients'] ?? j['ingredients']) as List? ??
                const [])
            .map((e) => RecipeIngredientRow.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
        imageKey: j['image_key'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prep_minutes': prepMinutes,
        'servings': servings,
        'difficulty': difficulty,
        'category': category,
        'method_steps': methodSteps,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'image_key': imageKey,
      };
}

// ---------------------------------------------------------------- product

/// A cached barcode. D1: no external API — this ships seeded and grows every
/// time a user names an unknown pack.
class Product {
  const Product({
    required this.barcode,
    required this.productName,
    this.brand,
    this.ingredientId,
    this.category,
    this.packSize,
    this.verified = false,
  });

  final String barcode;
  final String productName;
  final String? brand;
  final String? ingredientId;
  final FoodCategory? category;
  final String? packSize;

  /// True for seeded reference rows, false for user contributions. The RLS
  /// policy forces false on insert, so a client cannot fake a reference row.
  final bool verified;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        barcode: j['barcode'] as String,
        productName: j['product_name'] as String,
        brand: j['brand'] as String?,
        ingredientId: j['ingredient_id'] as String?,
        category: j['category'] == null
            ? null
            : FoodCategory.values.byName(j['category'] as String),
        packSize: j['pack_size'] as String?,
        verified: j['verified'] as bool? ?? false,
      );

  Map<String, dynamic> toJson({bool forWire = false}) => {
        'barcode': barcode,
        'product_name': productName,
        'brand': brand,
        'ingredient_id': ingredientId,
        'category': category?.wire,
        'pack_size': packSize,
        'verified': verified,
      };
}

// ----------------------------------------------------------- notification

/// D8: a dedup ledger, not a delivery queue. Delivery is device-local via
/// flutter_local_notifications, so this table only records what has already
/// been scheduled — the unique (item, level) constraint in Postgres is what
/// actually enforces BR-04.
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.userId,
    required this.inventoryItemId,
    required this.level,
    required this.scheduledFor,
    this.deliveredAt,
  });

  final String id;
  final String userId;
  final String inventoryItemId;
  final NotificationLevel level;
  final DateTime scheduledFor;
  final DateTime? deliveredAt;

  factory ScheduledNotification.fromJson(Map<String, dynamic> j) =>
      ScheduledNotification(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        inventoryItemId: j['inventory_item_id'] as String,
        level: switch (j['level'] as String) {
          'three_day' => NotificationLevel.threeDay,
          'one_day' => NotificationLevel.oneDay,
          'same_day' => NotificationLevel.sameDay,
          final v => throw ArgumentError('unknown level: $v'),
        },
        scheduledFor: DateTime.parse(j['scheduled_for'] as String),
        deliveredAt: j['delivered_at'] == null
            ? null
            : DateTime.parse(j['delivered_at'] as String),
      );

  Map<String, dynamic> toJson({bool forWire = false}) => {
        'id': id,
        if (!forWire) 'user_id': userId,
        'inventory_item_id': inventoryItemId,
        'level': level.wire,
        'scheduled_for': scheduledFor.toIso8601String(),
        'delivered_at': deliveredAt?.toIso8601String(),
      };
}

// ------------------------------------------------------------------ stats

/// The FR-09 dashboard figures, matching `kitchen_stats()` exactly so the
/// offline computation and the server RPC produce the same shape.
class KitchenStats {
  const KitchenStats({
    required this.activeItems,
    required this.expiringSoon,
    required this.dueToday,
    required this.mealsRescued,
    required this.valueRescuedInr,
    required this.currentStreak,
    this.pctUsedInTime,
  });

  final int activeItems;
  final int expiringSoon;
  final int dueToday;
  final int mealsRescued;

  /// An ESTIMATE from ingredients.est_price_inr. The UI must label it as such —
  /// never present it as a measured figure.
  final double valueRescuedInr;

  final int currentStreak;

  /// Null until there is any history to compute it from.
  final int? pctUsedInTime;

  static const empty = KitchenStats(
    activeItems: 0,
    expiringSoon: 0,
    dueToday: 0,
    mealsRescued: 0,
    valueRescuedInr: 0,
    currentStreak: 0,
  );

  factory KitchenStats.fromJson(Map<String, dynamic> j) => KitchenStats(
        activeItems: (j['active_items'] as num?)?.toInt() ?? 0,
        expiringSoon: (j['expiring_soon'] as num?)?.toInt() ?? 0,
        dueToday: (j['due_today'] as num?)?.toInt() ?? 0,
        mealsRescued: (j['meals_rescued'] as num?)?.toInt() ?? 0,
        valueRescuedInr: (j['value_rescued_inr'] as num?)?.toDouble() ?? 0,
        currentStreak: (j['current_streak'] as num?)?.toInt() ?? 0,
        pctUsedInTime: (j['pct_used_in_time'] as num?)?.toInt(),
      );
}
