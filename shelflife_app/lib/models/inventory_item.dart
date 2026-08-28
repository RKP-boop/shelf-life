import 'enums.dart';

/// A single thing in the user's kitchen.
///
/// Hard delete only (D7 / BR-02): there is no `deletedAt` and no restore path.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.userId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.storage,
    required this.purchaseDate,
    required this.expiryDate,
    required this.expirySource,
    required this.createdAt,
    required this.updatedAt,
    this.ingredientId,
    this.expiryReason,
    this.barcode,
    this.status = ItemStatus.active,
  });

  final String id;
  final String userId;

  /// Null when the user typed something outside the catalogue — the board
  /// explicitly allows free text, saved locally for next time.
  final String? ingredientId;

  /// What the user sees. May differ from the canonical name: "Amul Taaza",
  /// not "milk".
  final String productName;

  final FoodCategory category;
  final double quantity;
  final String unit;
  final StorageLocation storage;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final ExpirySource expirySource;

  /// The plain-English justification from the estimator. Stored rather than
  /// recomputed, so the explanation the user saw is the one that persists.
  final String? expiryReason;

  final String? barcode;
  final ItemStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryItem copyWith({
    String? productName,
    FoodCategory? category,
    double? quantity,
    String? unit,
    StorageLocation? storage,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    ExpirySource? expirySource,
    String? expiryReason,
    ItemStatus? status,
    DateTime? updatedAt,
  }) =>
      InventoryItem(
        id: id,
        userId: userId,
        ingredientId: ingredientId,
        productName: productName ?? this.productName,
        category: category ?? this.category,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        storage: storage ?? this.storage,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        expiryDate: expiryDate ?? this.expiryDate,
        expirySource: expirySource ?? this.expirySource,
        expiryReason: expiryReason ?? this.expiryReason,
        barcode: barcode,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        ingredientId: j['ingredient_id'] as String?,
        productName: j['product_name'] as String,
        category: FoodCategory.values.byName(j['category'] as String),
        quantity: (j['quantity'] as num).toDouble(),
        unit: j['unit'] as String,
        storage: StorageLocation.values.byName(j['storage'] as String),
        purchaseDate: DateTime.parse(j['purchase_date'] as String),
        expiryDate: DateTime.parse(j['expiry_date'] as String),
        expirySource: ExpirySourceWire.parse(j['expiry_source'] as String),
        expiryReason: j['expiry_reason'] as String?,
        barcode: j['barcode'] as String?,
        status: ItemStatus.values.byName(j['status'] as String? ?? 'active'),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  /// [forWire] omits `user_id`: the column defaults to auth.uid()
  /// (migration 005), so the client never has to know its own id and cannot
  /// get it wrong.
  Map<String, dynamic> toJson({bool forWire = false}) => {
        'id': id,
        if (!forWire) 'user_id': userId,
        'ingredient_id': ingredientId,
        'product_name': productName,
        'category': category.wire,
        'quantity': quantity,
        'unit': unit,
        'storage': storage.wire,
        'purchase_date': ymd(purchaseDate),
        'expiry_date': ymd(expiryDate),
        'expiry_source': expirySource.wire,
        'expiry_reason': expiryReason,
        'barcode': barcode,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
