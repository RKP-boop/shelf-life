// Inventory repository — PRD 5.10.
//
// The load-bearing assertion here is that every read works with no network
// whatsoever: these tests construct no Supabase client at all, so a repository
// that secretly needed one would fail to even run.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shelflife_app/database/local_store.dart';
import 'package:shelflife_app/database/sync_queue.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/models/ingredient.dart';
import 'package:shelflife_app/repositories/inventory_repository.dart';

const spinach = Ingredient(
  id: 'i-spinach',
  canonicalName: 'spinach',
  category: FoodCategory.vegetables,
  defaultUnit: 'g',
  glyphKey: 'spinach',
  shelfLifeFridgeDays: 6,
  shelfLifeCounterDays: 2,
  estPriceInr: 40,
);

const rice = Ingredient(
  id: 'i-rice',
  canonicalName: 'rice',
  category: FoodCategory.pantry,
  defaultUnit: 'kg',
  glyphKey: 'rice',
  shelfLifePantryDays: 365,
  estPriceInr: 120,
);

void main() {
  late LocalStore store;
  late SyncQueue queue;
  late InventoryRepository repo;

  final today = DateTime(2026, 7, 25);

  setUp(() async {
    Hive.init('.dart_tool/test_inv_${DateTime.now().microsecondsSinceEpoch}');
    for (final name in [
      'inventory', 'consumption_events', 'shopping_list', 'recipes',
      'ingredients', 'aliases', 'products', 'notifications',
      'sync_outbox', 'meta',
    ]) {
      await Hive.openBox<dynamic>(name);
    }
    store = LocalStore.instance;
    queue = SyncQueue(store);
    repo = InventoryRepository(store: store, queue: queue);
    await store.clearEverything();
    store.currentUserId = 'user-1';
  });

  tearDown(() => Hive.deleteFromDisk());

  Future<void> seed() async {
    // due today
    await repo.add(
      productName: 'Spinach',
      category: FoodCategory.vegetables,
      quantity: 500,
      unit: 'g',
      storage: StorageLocation.fridge,
      purchaseDate: DateTime(2026, 7, 19), // +6 = 25 Jul
      ingredient: spinach,
      today: today,
    );
    // far future
    await repo.add(
      productName: 'India Gate Basmati Rice',
      category: FoodCategory.pantry,
      quantity: 5,
      unit: 'kg',
      storage: StorageLocation.pantry,
      purchaseDate: DateTime(2026, 7, 20),
      ingredient: rice,
      today: today,
    );
  }

  group('offline reads (Principle 6)', () {
    test('returns data with no network client constructed at all', () async {
      await seed();
      expect(repo.all(), hasLength(2));
    });

    test('sorted by expiry, soonest first', () async {
      await seed();
      expect(repo.all().first.productName, 'Spinach');
    });

    test('consumed items are excluded by default', () async {
      await seed();
      await repo.markUsed(repo.all().first);
      expect(repo.all(), hasLength(1));
      expect(repo.all(includeConsumed: true), hasLength(2));
    });
  });

  group('add', () {
    test('stores the estimator reason, so the explanation persists', () async {
      await seed();
      final item = repo.all().first;
      expect(item.expiryReason, isNotNull);
      expect(item.expiryReason, contains('keep about'));
      expect(item.expirySource, ExpirySource.estimated);
    });

    test('a printed date overrides the estimate', () async {
      await repo.add(
        productName: 'Amul Taaza',
        category: FoodCategory.dairy,
        quantity: 1,
        unit: 'l',
        storage: StorageLocation.fridge,
        purchaseDate: DateTime(2026, 7, 20),
        printedExpiry: DateTime(2026, 7, 27),
        today: today,
      );
      final item = repo.all().first;
      expect(item.expiryDate, DateTime(2026, 7, 27));
      expect(item.expirySource, ExpirySource.printed);
    });

    test('an item with no catalogue match still saves (board: never block)', () async {
      await repo.add(
        productName: 'Kelloggs Chocos',
        category: FoodCategory.pantry,
        quantity: 1,
        unit: 'pack',
        storage: StorageLocation.pantry,
        purchaseDate: today,
        today: today,
      );
      final item = repo.all().first;
      expect(item.ingredientId, isNull);
      expect(item.expirySource, ExpirySource.categoryDefault);
    });

    test('generates a stable client-side id, usable before any sync', () async {
      await seed();
      final id = repo.all().first.id;
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(repo.byId(id), isNotNull);
    });

    test('queues the insert for later push', () async {
      await seed();
      final ops = queue.pending();
      expect(ops.where((o) => o.table == SyncTable.inventory), hasLength(2));
      expect(ops.first.op, SyncOp.insert);
    });

    test('the queued payload omits user_id, which Postgres defaults', () async {
      await seed();
      final payload = queue.pending().first.payload;
      expect(payload.containsKey('user_id'), isFalse,
          reason: 'migration 005 defaults it to auth.uid()');
    });
  });

  group('needsUsing', () {
    test('includes items in the amber and red bands only', () async {
      await seed();
      final urgent = repo.needsUsing(today: today);
      expect(urgent.map((i) => i.productName), ['Spinach']);
    });

    test('fresh items are excluded, which is what makes the row meaningful', () async {
      await repo.add(
        productName: 'Rice',
        category: FoodCategory.pantry,
        quantity: 5,
        unit: 'kg',
        storage: StorageLocation.pantry,
        purchaseDate: today,
        ingredient: rice,
        today: today,
      );
      expect(repo.needsUsing(today: today), isEmpty);
    });
  });

  group('search (FR-02)', () {
    test('matches a substring, case-insensitively', () async {
      await seed();
      expect(repo.search('pan'), isEmpty);
      expect(repo.search('spin').single.productName, 'Spinach');
      expect(repo.search('BASMATI').single.productName,
          'India Gate Basmati Rice');
    });

    test('an empty term returns nothing rather than everything', () async {
      await seed();
      expect(repo.search('   '), isEmpty);
    });
  });

  group('held ingredients', () {
    test('keeps the soonest expiry among duplicates', () async {
      await repo.add(
        productName: 'Spinach A',
        category: FoodCategory.vegetables,
        quantity: 250,
        unit: 'g',
        storage: StorageLocation.fridge,
        purchaseDate: DateTime(2026, 7, 19),
        ingredient: spinach,
        today: today,
      );
      await repo.add(
        productName: 'Spinach B',
        category: FoodCategory.vegetables,
        quantity: 250,
        unit: 'g',
        storage: StorageLocation.fridge,
        purchaseDate: DateTime(2026, 7, 22),
        ingredient: spinach,
        today: today,
      );
      final held = repo.heldIngredients();
      expect(held['i-spinach'], DateTime(2026, 7, 25),
          reason: 'the earlier of the two');
    });

    test('powers the shopping-list suppression', () async {
      await seed();
      expect(repo.alreadyHave('i-rice'), isTrue);
      expect(repo.alreadyHave('i-paneer'), isFalse);
    });

    test('free-text items are excluded, having no ingredient id', () async {
      await repo.add(
        productName: 'Mystery Snack',
        category: FoodCategory.other,
        quantity: 1,
        unit: 'pack',
        storage: StorageLocation.pantry,
        purchaseDate: today,
        today: today,
      );
      expect(repo.heldIngredients(), isEmpty);
    });
  });

  group('markUsed vs remove (Principle 3)', () {
    test('markUsed records a rescued event', () async {
      await seed();
      await repo.markUsed(repo.all().first, estValueInr: 40);

      final events = store.readAll(store.events);
      expect(events, hasLength(1));
      expect(events.first['kind'], 'used');
      expect(events.first['est_value_inr'], 40);
    });

    test('remove records an event that does NOT count as rescued', () async {
      await seed();
      await repo.remove(repo.all().first);

      final events = store.readAll(store.events);
      expect(events.first['kind'], 'removed',
          reason: 'the delete-confirm screen says it will not count');
    });

    test('remove is permanent — the row is gone, not flagged (BR-02)', () async {
      await seed();
      final id = repo.all().first.id;
      await repo.remove(repo.all().first);

      expect(repo.byId(id), isNull);
      expect(repo.all(includeConsumed: true).map((i) => i.id),
          isNot(contains(id)));
    });

    test('markUsed keeps the row so history and stats stay intact', () async {
      await seed();
      final id = repo.all().first.id;
      await repo.markUsed(repo.all().first);

      expect(repo.byId(id), isNotNull);
      expect(repo.byId(id)!.status, ItemStatus.consumed);
    });
  });

  group('notification cancellation (board requirement)', () {
    test('consuming an item cancels its scheduled reminders', () async {
      await seed();
      final item = repo.all().first;
      await store.notifications.put('n1', {
        'id': 'n1',
        'user_id': 'user-1',
        'inventory_item_id': item.id,
        'level': 'three_day',
        'scheduled_for': DateTime(2026, 7, 22).toIso8601String(),
      });

      await repo.markUsed(item);
      expect(store.notifications.isEmpty, isTrue);
    });

    test('and queues the cancellation for the server too', () async {
      await seed();
      final item = repo.all().first;
      await store.notifications.put('n1', {
        'id': 'n1',
        'user_id': 'user-1',
        'inventory_item_id': item.id,
        'level': 'same_day',
        'scheduled_for': DateTime(2026, 7, 25).toIso8601String(),
      });

      await repo.markUsed(item);
      final deletes = queue
          .pending()
          .where((e) => e.table == SyncTable.notifications && e.op == SyncOp.delete);
      expect(deletes, hasLength(1));
    });

    test('reminders for other items are untouched', () async {
      await seed();
      final items = repo.all();
      await store.notifications.put('n1', {
        'id': 'n1',
        'user_id': 'user-1',
        'inventory_item_id': items[1].id,
        'level': 'three_day',
        'scheduled_for': DateTime(2027, 1, 1).toIso8601String(),
      });

      await repo.markUsed(items[0]);
      expect(store.notifications.length, 1);
    });
  });
}
