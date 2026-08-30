// The wiring, end to end, with fakes for anything native.
//
// The golden tests prove each screen renders. They cannot prove that adding an
// item actually reaches Hive, that the outbox queues it, that consuming it
// moves the impact figures, or that guest mode really queues nothing. That is
// what this covers — the seams between the pieces, which is where the bugs
// that survive unit tests live.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/app/app_scope.dart';
import 'package:shelflife_app/core/services/capabilities.dart';
import 'package:shelflife_app/database/local_store.dart';
import 'package:shelflife_app/database/sync_queue.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/services/reminder_service.dart';
import 'package:shelflife_app/services/sync_service.dart';

import 'hive_harness.dart';

void main() {
  late LocalStore store;
  late AppState app;
  late Capabilities capabilities;

  setUp(() async {
    store = await openTestStore();
    capabilities = Capabilities.fakes();
    final queue = SyncQueue(store);
    app = AppState(
      store: store,
      queue: queue,
      // No client: this is the offline case, which is the one that has to be
      // right. Writes queue and nothing is sent.
      sync: SyncService(
        queue: queue,
        store: store,
        connectivity: capabilities.connectivity,
      ),
      capabilities: capabilities,
      reminders: ReminderService(
        scheduler: capabilities.notifications,
        store: store,
      ),
    );

    // A minimal catalogue rather than the full asset: rootBundle is awkward in
    // a plain test, and the wiring under test does not care how many rows there
    // are.
    await store.ingredients.put('ing-spinach', {
      'id': 'ing-spinach',
      'canonical_name': 'spinach',
      'category': 'vegetables',
      'default_unit': 'g',
      'glyph_key': 'spinach',
      'shelf_life_fridge_days': 6,
      'shelf_life_freezer_days': 90,
      'shelf_life_pantry_days': null,
      'shelf_life_counter_days': 2,
      'est_price_inr': 40,
    });
    await store.aliases.put('palak', {'alias': 'palak', 'canonical': 'spinach'});
    await store.meta.put('user_id', 'user-1');
  });

  tearDown(closeTestStore);

  Future<void> addSpinach({String name = 'spinach'}) => app.addItem(
        name: name,
        category: FoodCategory.vegetables,
        quantity: 250,
        unit: 'g',
        storage: StorageLocation.fridge,
      );

  group('adding an item', () {
    test('lands in Hive and is readable straight back', () async {
      await addSpinach();
      expect(app.allItems, hasLength(1));
      expect(app.allItems.single.productName, 'spinach');
    });

    test('resolves through the catalogue and stores the glyph', () async {
      await addSpinach();
      final item = app.allItems.single;
      expect(item.ingredientId, 'ing-spinach');
      expect(item.glyphKey, 'spinach',
          reason: 'the row must be able to render its own image offline');
    });

    test('resolves an alias, so "palak" is spinach', () async {
      await addSpinach(name: 'palak');
      expect(app.allItems.single.ingredientId, 'ing-spinach');
    });

    test('free text is kept, not rejected', () async {
      await app.addItem(
        name: 'leftover rajma',
        category: FoodCategory.other,
        quantity: 1,
        unit: 'pack',
        storage: StorageLocation.fridge,
      );
      final item = app.allItems.single;
      expect(item.productName, 'leftover rajma');
      expect(item.ingredientId, isNull);
      expect(item.glyphKey, isNull,
          reason: 'no catalogue match means the category glyph is used');
    });

    test('carries an expiry reason, so the estimate explains itself', () async {
      await addSpinach();
      expect(app.allItems.single.expiryReason, isNotNull);
      expect(app.allItems.single.expiryReason, isNotEmpty);
    });

    test('schedules its reminder ladder', () async {
      await addSpinach();
      final scheduler =
          capabilities.notifications as FakeNotificationScheduler;
      expect(scheduler.scheduled, isNotEmpty);
    });
  });

  group('the outbox', () {
    test('queues the insert, because there is no connection', () async {
      await addSpinach();
      expect(app.sync.pendingCount, greaterThan(0));
    });

    test('queues nothing at all in guest mode', () async {
      await app.continueAsGuest();
      await addSpinach();
      expect(app.allItems, hasLength(1),
          reason: 'guest mode is fully functional locally');
      expect(app.sync.pendingCount, 0,
          reason: 'a guest has no server rows to sync to');
    });

    test('signing up adopts the guest rows rather than losing them', () async {
      await app.continueAsGuest();
      await addSpinach();
      final id = app.allItems.single.id;

      // What _adopt does, without a network round trip.
      await store.meta.put('user_id', 'real-user');
      await store.meta.put('is_guest', false);
      await app.queue.rekey('real-user');

      expect(app.allItems.single.id, id,
          reason: 'the row keeps its client-generated id');
      expect(app.isGuest, isFalse);
    });
  });

  group('using something up', () {
    test('takes it off the list and counts it as rescued', () async {
      await addSpinach();
      final item = app.allItems.single;

      expect(app.kitchenStats().mealsRescued, 0);
      await app.markUsed(item);

      expect(app.allItems, isEmpty, reason: 'consumed items leave the kitchen');
      expect(app.kitchenStats().mealsRescued, 1);
    });

    test('cancels the reminders for it', () async {
      await addSpinach();
      final scheduler =
          capabilities.notifications as FakeNotificationScheduler;
      expect(scheduler.scheduled, isNotEmpty);

      await app.markUsed(app.allItems.single);
      expect(scheduler.scheduled, isEmpty);
    });

    test('removing something does NOT count as rescued', () async {
      // Principle 3 cuts both ways: the app never shames, and it also never
      // flatters. A thing thrown out is not a rescue.
      await addSpinach();
      await app.removeItem(app.allItems.single);
      expect(app.kitchenStats().mealsRescued, 0);
    });
  });

  group('the shopping list', () {
    test('an added row comes back with its source caption', () async {
      await app.addToShopping(
        name: 'cream',
        quantity: 200,
        unit: 'ml',
        source: ShoppingSource.recipe,
        recipeName: 'Palak paneer',
      );
      final row = app.shoppingItems.single;
      expect(row.caption, 'Added from Palak paneer');
      expect(app.shoppingCount, 1);
    });

    test('ticking something moves it out of the to-get count', () async {
      await app.addToShopping(name: 'cream');
      await app.togglePurchased(app.shoppingItems.single);
      expect(app.shoppingCount, 0);
      expect(app.shoppingItems, hasLength(1),
          reason: 'it is in the basket, not gone');
    });
  });

  group('reminder settings', () {
    test('turning reminders off cancels everything already scheduled',
        () async {
      await addSpinach();
      final scheduler =
          capabilities.notifications as FakeNotificationScheduler;
      expect(scheduler.scheduled, isNotEmpty);

      await app.setReminderSetting('enabled', false);
      expect(scheduler.scheduled, isEmpty);
    });

    test('turning them back on catches up items added while they were off',
        () async {
      await app.setReminderSetting('enabled', false);
      await addSpinach();
      final scheduler =
          capabilities.notifications as FakeNotificationScheduler;
      expect(scheduler.scheduled, isEmpty);

      await app.setReminderSetting('enabled', true);
      expect(scheduler.scheduled, isNotEmpty,
          reason: 'otherwise nothing already in the kitchen is ever '
              'reminded about');
    });
  });

  group('expiry copy', () {
    test('reads as a sentence, not a date, when it is close', () async {
      await addSpinach();
      final item = app.allItems.single;
      final today = DateTime.now();

      expect(
        app.expiryLine(item, today: item.expiryDate),
        'Best used today',
      );
      expect(
        app.expiryLine(item,
            today: item.expiryDate.subtract(const Duration(days: 1))),
        'Best used tomorrow',
      );
      expect(app.expiryLine(item, today: today), startsWith('Best used'));
    });
  });
}
