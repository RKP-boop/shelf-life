// Enum values mirror the Postgres enums exactly. A mismatch here surfaces as a
// PostgREST 400 at runtime, so the names are deliberately identical to
// supabase/migrations/001_schema.sql.

enum FoodCategory { dairy, fruits, vegetables, pantry, frozen, other }

enum StorageLocation { fridge, freezer, pantry, counter }

/// Spec §5.1 precedence, highest first.
enum ExpirySource { user, printed, estimated, categoryDefault }

enum ItemStatus { active, consumed }

/// `used` counts as rescued; `removed` does not. Both are recorded because
/// FR-09's "% used before expiry" needs a denominator — but nothing ever
/// surfaces a waste count (Principle 3).
enum ConsumptionKind { used, removed }

enum ShoppingSource { manual, ranOut, recipe }

enum NotificationLevel { threeDay, oneDay, sameDay }

/// Wire names, for the columns whose Dart spelling differs from Postgres.
extension FoodCategoryWire on FoodCategory {
  String get wire => name;
}

extension StorageLocationWire on StorageLocation {
  String get wire => name;
}

extension ExpirySourceWire on ExpirySource {
  String get wire => this == ExpirySource.categoryDefault ? 'category_default' : name;
  static ExpirySource parse(String v) => switch (v) {
        'user' => ExpirySource.user,
        'printed' => ExpirySource.printed,
        'estimated' => ExpirySource.estimated,
        'category_default' => ExpirySource.categoryDefault,
        _ => throw ArgumentError('unknown expiry_source: $v'),
      };
}

extension ShoppingSourceWire on ShoppingSource {
  String get wire => this == ShoppingSource.ranOut ? 'ran_out' : name;
  static ShoppingSource parse(String v) => switch (v) {
        'manual' => ShoppingSource.manual,
        'ran_out' => ShoppingSource.ranOut,
        'recipe' => ShoppingSource.recipe,
        _ => throw ArgumentError('unknown shopping_source: $v'),
      };
}

extension NotificationLevelWire on NotificationLevel {
  String get wire => switch (this) {
        NotificationLevel.threeDay => 'three_day',
        NotificationLevel.oneDay => 'one_day',
        NotificationLevel.sameDay => 'same_day',
      };
}
