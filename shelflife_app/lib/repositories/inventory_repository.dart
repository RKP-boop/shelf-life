// Inventory repository — PRD 5.10.
//
// Every read serves Hive. Nothing here awaits the network before returning, so
// no screen can block on connectivity (Principle 6). Writes land locally and
// append to the sync queue; the queue drains later.

import 'dart:math';

import '../core/engines/expiry_estimator.dart';
import '../database/local_store.dart';
import '../database/sync_queue.dart';
import '../models/enums.dart';
import '../models/ingredient.dart';
import '../models/inventory_item.dart';
import '../models/models.dart';

class InventoryRepository {
  const InventoryRepository({
    required this.store,
    required this.queue,
    this.estimator = const ExpiryEstimator(),
  });

  final LocalStore store;
  final SyncQueue queue;
  final ExpiryEstimator estimator;

  static final _rand = Random();

  /// Client-generated ids, so an offline insert has a stable identity before
  /// it ever reaches Postgres. A server-assigned id would make the queued
  /// update-after-insert case unresolvable.
  static String newId() {
    const hex = '0123456789abcdef';
    String block(int n) =>
        List.generate(n, (_) => hex[_rand.nextInt(16)]).join();
    return '${block(8)}-${block(4)}-4${block(3)}-'
        '${'89ab'[_rand.nextInt(4)]}${block(3)}-${block(12)}';
  }

  // ------------------------------------------------------------------ reads

  List<InventoryItem> all({bool includeConsumed = false}) {
    final items = store
        .readAll(store.inventory)
        .map(InventoryItem.fromJson)
        .where((i) => includeConsumed || i.status == ItemStatus.active)
        .toList();
    items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return items;
  }

  InventoryItem? byId(String id) {
    final raw = store.inventory.get(id);
    return raw == null ? null : InventoryItem.fromJson(LocalStore.cast(raw));
  }

  /// The Home "use these first" row and the urgency-sorted inventory list.
  List<InventoryItem> needsUsing({DateTime? today, int limit = 10}) {
    final now = today ?? DateTime.now();
    return all()
        .where((i) => estimator.freshness(i.expiryDate, today: now) !=
            Freshness.fresh)
        .take(limit)
        .toList();
  }

  /// FR-02 search. Substring, case-insensitive, matching the trigram index
  /// used server-side so local and remote results agree.
  List<InventoryItem> search(String term) {
    final q = term.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return all().where((i) => i.productName.toLowerCase().contains(q)).toList();
  }

  List<InventoryItem> byCategory(FoodCategory category) =>
      all().where((i) => i.category == category).toList();

  /// Ingredient ids currently held, with the soonest expiry among duplicates.
  /// Feeds the recipe scorer and the shopping-list suppression.
  Map<String, DateTime> heldIngredients() {
    final held = <String, DateTime>{};
    for (final item in all()) {
      final id = item.ingredientId;
      if (id == null) continue;
      final existing = held[id];
      if (existing == null || item.expiryDate.isBefore(existing)) {
        held[id] = item.expiryDate;
      }
    }
    return held;
  }

  /// True when the user already has this ingredient — screen 39's
  /// "You already have onions and rice, we've left them off".
  bool alreadyHave(String ingredientId) =>
      heldIngredients().containsKey(ingredientId);

  // ----------------------------------------------------------------- writes

  Future<InventoryItem> add({
    required String productName,
    required FoodCategory category,
    required double quantity,
    required String unit,
    required StorageLocation storage,
    required DateTime purchaseDate,
    Ingredient? ingredient,
    DateTime? printedExpiry,
    DateTime? userExpiry,
    String? barcode,
    DateTime? today,
  }) async {
    final estimate = estimator.estimate(
      ingredient: ingredient,
      category: category,
      storage: storage,
      purchaseDate: purchaseDate,
      printedExpiry: printedExpiry,
      userOverride: userExpiry,
      today: today,
    );

    final now = DateTime.now();
    final item = InventoryItem(
      id: newId(),
      userId: store.currentUserId ?? 'guest',
      ingredientId: ingredient?.id,
      productName: productName,
      category: category,
      quantity: quantity,
      unit: unit,
      storage: storage,
      purchaseDate: purchaseDate,
      expiryDate: estimate.date,
      expirySource: estimate.source,
      expiryReason: estimate.reason,
      barcode: barcode,
      glyphKey: ingredient?.glyphKey,
      createdAt: now,
      updatedAt: now,
    );

    await store.inventory.put(item.id, item.toJson());
    await queue.enqueue(
      op: SyncOp.insert,
      table: SyncTable.inventory,
      rowId: item.id,
      payload: item.toJson(forWire: true),
    );
    return item;
  }

  Future<void> update(InventoryItem item) async {
    final updated = item.copyWith(updatedAt: DateTime.now());
    await store.inventory.put(updated.id, updated.toJson());
    await queue.enqueue(
      op: SyncOp.update,
      table: SyncTable.inventory,
      rowId: updated.id,
      payload: updated.toJson(forWire: true),
    );
  }

  /// Mark as used. Counts as rescued (Principle 3) and records the event that
  /// FR-09's statistics are computed from.
  Future<void> markUsed(
    InventoryItem item, {
    String? recipeId,
    double? estValueInr,
  }) async {
    await _logEvent(item, ConsumptionKind.used,
        recipeId: recipeId, estValueInr: estValueInr);

    await store.inventory
        .put(item.id, item.copyWith(status: ItemStatus.consumed).toJson());
    await queue.enqueue(
      op: SyncOp.update,
      table: SyncTable.inventory,
      rowId: item.id,
      payload: item.copyWith(status: ItemStatus.consumed).toJson(forWire: true),
    );

    // Board: a scheduled reminder must be cancelled when its item is consumed.
    await _cancelNotifications(item.id);
  }

  /// Remove from inventory. Permanent (D7 / BR-02) and does NOT count as
  /// rescued — the delete-confirm screen says so explicitly.
  Future<void> remove(InventoryItem item) async {
    await _logEvent(item, ConsumptionKind.removed);

    await store.inventory.delete(item.id);
    await queue.enqueue(
      op: SyncOp.delete,
      table: SyncTable.inventory,
      rowId: item.id,
      payload: {'id': item.id},
    );
    await _cancelNotifications(item.id);
  }

  Future<void> _logEvent(
    InventoryItem item,
    ConsumptionKind kind, {
    String? recipeId,
    double? estValueInr,
  }) async {
    final event = ConsumptionEvent(
      id: newId(),
      userId: store.currentUserId ?? 'guest',
      ingredientId: item.ingredientId,
      productName: item.productName,
      kind: kind,
      quantity: item.quantity,
      unit: item.unit,
      expiryDate: item.expiryDate,
      estValueInr: estValueInr,
      recipeId: recipeId,
      occurredAt: DateTime.now(),
    );
    await store.events.put(event.id, event.toJson());
    await queue.enqueue(
      op: SyncOp.insert,
      table: SyncTable.consumption,
      rowId: event.id,
      payload: event.toJson(forWire: true),
    );
  }

  Future<void> _cancelNotifications(String itemId) async {
    for (final key in store.notifications.keys.toList()) {
      final raw = store.notifications.get(key);
      if (raw == null) continue;
      final n = ScheduledNotification.fromJson(LocalStore.cast(raw));
      if (n.inventoryItemId == itemId) {
        await store.notifications.delete(key);
        await queue.enqueue(
          op: SyncOp.delete,
          table: SyncTable.notifications,
          rowId: n.id,
          payload: {'id': n.id},
        );
      }
    }
  }

  /// Bulk add from the review screen, so one receipt is a single user action.
  Future<List<InventoryItem>> addAll(
      List<Future<InventoryItem> Function()> builders) async {
    final added = <InventoryItem>[];
    for (final build in builders) {
      added.add(await build());
    }
    return added;
  }
}
