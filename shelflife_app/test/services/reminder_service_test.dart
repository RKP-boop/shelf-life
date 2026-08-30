// The reminder ladder and its dedup ledger.
//
// These matter disproportionately because the failure mode is invisible during
// development: reminders are scheduled days ahead, so a wrong rule here only
// shows up as a user getting five identical notifications about spinach, or
// none at all, long after the build shipped.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/services/capabilities.dart';
import 'package:shelflife_app/database/local_store.dart';
import 'package:shelflife_app/models/enums.dart';
import 'package:shelflife_app/services/reminder_service.dart';

import '../hive_harness.dart';

void main() {
  late FakeNotificationScheduler scheduler;
  late LocalStore store;
  late ReminderService reminders;

  final today = DateTime(2026, 8, 28);

  setUp(() async {
    scheduler = FakeNotificationScheduler();
    store = await openTestStore();
    reminders = ReminderService(scheduler: scheduler, store: store);
  });

  tearDown(closeTestStore);

  Future<void> schedule(
    DateTime expiry, {
    Set<NotificationLevel>? levels,
    String itemId = 'item-1',
  }) =>
      reminders.scheduleFor(
        itemId: itemId,
        itemName: 'Spinach',
        expiry: expiry,
        levels: levels ??
            {
              NotificationLevel.threeDay,
              NotificationLevel.oneDay,
              NotificationLevel.sameDay,
            },
        now: today,
      );

  group('the ladder', () {
    test('an item a week out gets all three stages', () async {
      await schedule(today.add(const Duration(days: 7)));
      expect(scheduler.scheduled, hasLength(3));
    });

    test('stages fire three days, one day, and zero days before expiry',
        () async {
      await schedule(DateTime(2026, 9, 4));
      final days = scheduler.scheduled.values
          .map((r) => DateTime(r.when.year, r.when.month, r.when.day))
          .toList()
        ..sort();
      expect(days, [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 3),
        DateTime(2026, 9, 4),
      ]);
    });

    test('reminders land at 9am, not at whatever time the item was added',
        () async {
      await schedule(today.add(const Duration(days: 7)));
      for (final reminder in scheduler.scheduled.values) {
        expect(reminder.when.hour, 9,
            reason: 'a 3am notification about spinach is nobody’s idea of '
                'helpful');
      }
    });

    test('a stage whose day has already passed is not scheduled', () async {
      // Bought something with two days left: the three-day stage is in the
      // past. Scheduling it would either fire immediately or be dropped, and
      // both are wrong.
      await schedule(today.add(const Duration(days: 2)));
      expect(scheduler.scheduled, hasLength(2));
      final ids = scheduler.scheduled.keys.toSet();
      expect(
        ids,
        isNot(contains(ReminderService.notificationId(
            'item-1', NotificationLevel.threeDay))),
      );
    });

    test('an item already past its date gets nothing', () async {
      await schedule(today.subtract(const Duration(days: 1)));
      expect(scheduler.scheduled, isEmpty);
    });

    test('only the stages the user has switched on are scheduled', () async {
      await schedule(
        today.add(const Duration(days: 7)),
        levels: {NotificationLevel.sameDay},
      );
      expect(scheduler.scheduled, hasLength(1));
    });
  });

  group('the dedup ledger (D8)', () {
    test('re-scheduling the same item does not add a second reminder',
        () async {
      final expiry = today.add(const Duration(days: 7));
      await schedule(expiry);
      final first = scheduler.scheduled.length;

      // Editing an item's quantity re-schedules it. Five edits must not mean
      // five notifications.
      for (var i = 0; i < 5; i++) {
        await schedule(expiry);
      }
      expect(scheduler.scheduled, hasLength(first));
    });

    test('the ledger records one row per item per stage', () async {
      await schedule(today.add(const Duration(days: 7)));
      await schedule(today.add(const Duration(days: 7)));
      expect(store.notifications.length, 3);
    });

    test('two different items each get their own ladder', () async {
      await schedule(today.add(const Duration(days: 7)), itemId: 'a');
      await schedule(today.add(const Duration(days: 7)), itemId: 'b');
      expect(scheduler.scheduled, hasLength(6));
    });
  });

  group('notification ids', () {
    test('are stable across calls, so a re-schedule replaces', () {
      final first =
          ReminderService.notificationId('abc', NotificationLevel.oneDay);
      final second =
          ReminderService.notificationId('abc', NotificationLevel.oneDay);
      expect(first, second);
    });

    test('differ per stage and per item', () {
      final ids = {
        ReminderService.notificationId('abc', NotificationLevel.threeDay),
        ReminderService.notificationId('abc', NotificationLevel.oneDay),
        ReminderService.notificationId('abc', NotificationLevel.sameDay),
        ReminderService.notificationId('xyz', NotificationLevel.threeDay),
      };
      expect(ids, hasLength(4));
    });

    test('fit in a signed 32-bit int, which is what Android accepts', () {
      // A uuid is 36 characters, so this is the realistic input.
      for (final id in [
        '76aba95c-ba4e-d128-0a1e-567b178f58a2',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '00000000-0000-0000-0000-000000000000',
      ]) {
        for (final level in NotificationLevel.values) {
          final value = ReminderService.notificationId(id, level);
          expect(value, greaterThanOrEqualTo(0));
          expect(value, lessThan(2147483647));
        }
      }
    });
  });

  group('cancelling', () {
    test('cancelFor clears both the schedule and the ledger', () async {
      await schedule(today.add(const Duration(days: 7)));
      await reminders.cancelFor('item-1');
      expect(scheduler.scheduled, isEmpty);
      expect(store.notifications.length, 0);
    });

    test('an item removed and added again can be reminded about afresh',
        () async {
      // The ledger must not permanently blacklist an item, or buying spinach
      // again next week would produce no reminders at all.
      final expiry = today.add(const Duration(days: 7));
      await schedule(expiry);
      await reminders.cancelFor('item-1');
      await schedule(expiry);
      expect(scheduler.scheduled, hasLength(3));
    });

    test('cancelAll empties everything', () async {
      await schedule(today.add(const Duration(days: 7)), itemId: 'a');
      await schedule(today.add(const Duration(days: 7)), itemId: 'b');
      await reminders.cancelAll();
      expect(scheduler.scheduled, isEmpty);
      expect(store.notifications.length, 0);
    });
  });

  group('the copy', () {
    test('never uses a forbidden word and never mentions waste', () async {
      await schedule(today.add(const Duration(days: 7)));
      const forbidden = ['error', 'expired', 'failed', 'warning', 'wasted'];
      for (final reminder in scheduler.scheduled.values) {
        final text = '${reminder.title} ${reminder.body}'.toLowerCase();
        for (final word in forbidden) {
          expect(text, isNot(contains(word)),
              reason: 'reminder copy contains "$word"');
        }
      }
    });

    test('names the item, so the notification is actionable', () async {
      await schedule(today.add(const Duration(days: 7)));
      for (final reminder in scheduler.scheduled.values) {
        expect(reminder.body.toLowerCase(), contains('spinach'));
      }
    });

    test('carries the item id as payload, so tapping it opens the item',
        () async {
      await schedule(today.add(const Duration(days: 7)));
      for (final reminder in scheduler.scheduled.values) {
        expect(reminder.payload, 'item-1');
      }
    });
  });

  test('nothing is scheduled when permission was refused', () async {
    scheduler.granted = false;
    await schedule(today.add(const Duration(days: 7)));
    expect(scheduler.scheduled, isEmpty);
  });
}
