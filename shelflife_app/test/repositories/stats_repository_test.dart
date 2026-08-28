// Statistics — FR-09.
//
// The streak tests exist because the SQL version of this logic had a real bug:
// for dates ordered descending the gaps-and-islands key is `d + rownum`, not
// `d - rownum`, and with the wrong sign every consecutive day formed its own
// group so the streak always reported 1. Screen 42's "12 days" would have been
// permanently stuck. The Dart implementation is tested against the same cases.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shelflife_app/database/local_store.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/repositories/stats_repository.dart';

void main() {
  late LocalStore store;
  late StatsRepository stats;

  final today = DateTime(2026, 7, 25);

  setUp(() async {
    Hive.init('.dart_tool/test_stats_${DateTime.now().microsecondsSinceEpoch}');
    for (final name in [
      'inventory', 'consumption_events', 'shopping_list', 'recipes',
      'ingredients', 'aliases', 'products', 'notifications',
      'sync_outbox', 'meta',
    ]) {
      await Hive.openBox<dynamic>(name);
    }
    store = LocalStore.instance;
    stats = StatsRepository(store: store);
    await store.clearEverything();
  });

  tearDown(() => Hive.deleteFromDisk());

  Future<void> item(String name, DateTime expiry) => store.inventory.put(name, {
        'id': name,
        'user_id': 'u1',
        'product_name': name,
        'category': 'vegetables',
        'quantity': 1,
        'unit': 'kg',
        'storage': 'fridge',
        'purchase_date': '2026-07-20',
        'expiry_date':
            '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}',
        'expiry_source': 'estimated',
        'status': 'active',
        'created_at': today.toIso8601String(),
        'updated_at': today.toIso8601String(),
      });

  Future<void> event(
    String id,
    DateTime when, {
    ConsumptionKind kind = ConsumptionKind.used,
    double? value,
    DateTime? expiry,
  }) =>
      store.events.put(id, {
        'id': id,
        'user_id': 'u1',
        'product_name': id,
        'kind': kind.name,
        'est_value_inr': value,
        'expiry_date': expiry == null
            ? null
            : '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}',
        'occurred_at': when.toIso8601String(),
      });

  group('inventory counts', () {
    test('counts active items, expiring-soon and due-today', () async {
      await item('due', today);
      await item('soon', today.add(const Duration(days: 2)));
      await item('fresh', today.add(const Duration(days: 30)));

      final s = stats.compute(today: today);
      expect(s.activeItems, 3);
      expect(s.expiringSoon, 2, reason: 'due + soon, within three days');
      expect(s.dueToday, 1);
    });

    test('an empty kitchen returns zeros, not nulls', () {
      final s = stats.compute(today: today);
      expect(s.activeItems, 0);
      expect(s.mealsRescued, 0);
      expect(s.currentStreak, 0);
    });
  });

  group('rescued this month (Principle 3)', () {
    test('counts used events and sums their estimated value', () async {
      await event('a', today, value: 40);
      await event('b', today.subtract(const Duration(days: 2)), value: 90);

      final s = stats.compute(today: today);
      expect(s.mealsRescued, 2);
      expect(s.valueRescuedInr, 130);
    });

    test('removed events never inflate the rescued figure', () async {
      await event('a', today, value: 40);
      await event('b', today, kind: ConsumptionKind.removed, value: 500);

      final s = stats.compute(today: today);
      expect(s.mealsRescued, 1);
      expect(s.valueRescuedInr, 40, reason: 'a removal is not a rescue');
    });

    test('last month is excluded from the monthly figure', () async {
      await event('old', DateTime(2026, 6, 30), value: 100);
      final s = stats.compute(today: today);
      expect(s.mealsRescued, 0);
      expect(s.valueRescuedInr, 0);
    });
  });

  group('streak', () {
    test('three consecutive days ending today gives 3', () async {
      await event('a', today);
      await event('b', today.subtract(const Duration(days: 1)));
      await event('c', today.subtract(const Duration(days: 2)));

      expect(stats.compute(today: today).currentStreak, 3,
          reason: 'the exact case the SQL bug reported as 1');
    });

    test('a gap ends the streak at the gap', () async {
      await event('a', today);
      await event('b', today.subtract(const Duration(days: 1)));
      await event('old', today.subtract(const Duration(days: 5)));

      expect(stats.compute(today: today).currentStreak, 2);
    });

    test('ending yesterday still counts, so it does not read as broken', () async {
      await event('a', today.subtract(const Duration(days: 1)));
      await event('b', today.subtract(const Duration(days: 2)));

      expect(stats.compute(today: today).currentStreak, 2);
    });

    test('a streak that ended two days ago is zero', () async {
      await event('a', today.subtract(const Duration(days: 2)));
      await event('b', today.subtract(const Duration(days: 3)));

      expect(stats.compute(today: today).currentStreak, 0);
    });

    test('several events on one day count once', () async {
      await event('a', DateTime(2026, 7, 25, 9));
      await event('b', DateTime(2026, 7, 25, 19));

      expect(stats.compute(today: today).currentStreak, 1);
    });

    test('removals do not extend a streak', () async {
      await event('a', today);
      await event('r', today.subtract(const Duration(days: 1)),
          kind: ConsumptionKind.removed);
      await event('b', today.subtract(const Duration(days: 2)));

      expect(stats.compute(today: today).currentStreak, 1,
          reason: 'the gap at day-1 is real: only removals happened');
    });

    test('a twelve-day streak reports 12, matching screen 42', () async {
      for (var i = 0; i < 12; i++) {
        await event('d$i', today.subtract(Duration(days: i)));
      }
      expect(stats.compute(today: today).currentStreak, 12);
    });
  });

  group('percent used in time', () {
    test('null with no history, rather than a discouraging zero', () {
      expect(stats.compute(today: today).pctUsedInTime, isNull);
    });

    test('used on or before expiry counts as in time', () async {
      await event('a', today, expiry: today);
      await event('b', today, expiry: today.add(const Duration(days: 2)));

      expect(stats.compute(today: today).pctUsedInTime, 100);
    });

    test('used after expiry does not count', () async {
      await event('late', today, expiry: today.subtract(const Duration(days: 3)));
      await event('ok', today, expiry: today);

      expect(stats.compute(today: today).pctUsedInTime, 50);
    });

    test('a removal counts in the denominator but never the numerator', () async {
      await event('ok', today, expiry: today);
      await event('gone', today,
          kind: ConsumptionKind.removed, expiry: today);

      expect(stats.compute(today: today).pctUsedInTime, 50,
          reason: 'this is exactly why removed events are recorded');
    });

    test('reaches the 94% figure screen 43 shows', () async {
      for (var i = 0; i < 47; i++) {
        await event('good$i', today, expiry: today);
      }
      for (var i = 0; i < 3; i++) {
        await event('bad$i', today, kind: ConsumptionKind.removed, expiry: today);
      }
      expect(stats.compute(today: today).pctUsedInTime, 94);
    });
  });
}
