// The reminder ladder — FR-06, Flow 6, D8.
//
// Sits above [NotificationScheduler] and owns two things the scheduler cannot:
//
//  1. The ladder itself — three days out, one day out, on the day — derived
//     from the item's expiry date rather than stored per item.
//  2. The dedup ledger. D8: `notifications` is a ledger with a unique
//     constraint on (inventory_item_id, level), so an item can produce at most
//     one reminder per stage no matter how many times it is edited or how
//     often the app re-schedules. Without it, editing an item's quantity five
//     times sends five identical reminders.
//
// Notification ids are derived from (itemId, level) deterministically, so a
// re-schedule replaces rather than duplicates even if the ledger is lost.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/services/capabilities.dart';
import '../database/local_store.dart';
import '../models/enums.dart';
import '../models/models.dart';

class ReminderService {
  ReminderService({required this.scheduler, required this.store});

  final NotificationScheduler scheduler;
  final LocalStore store;

  /// Days before expiry for each stage. Taken from the board, not invented.
  static const _daysBefore = {
    NotificationLevel.threeDay: 3,
    NotificationLevel.oneDay: 1,
    NotificationLevel.sameDay: 0,
  };

  /// Quiet hours: a reminder due inside them is pushed to 9am. Nobody wants to
  /// be told about spinach at 3am.
  static const _hour = 9;

  Future<bool> requestPermission() => scheduler.requestPermission();

  /// Schedules every stage in [levels] that is still in the future.
  ///
  /// Stages already in the ledger are skipped, and stages whose moment has
  /// passed are skipped — scheduling a notification for last Tuesday either
  /// fires immediately or is silently dropped, and both are wrong.
  Future<void> scheduleFor({
    required String itemId,
    required String itemName,
    required DateTime expiry,
    required Set<NotificationLevel> levels,
    DateTime? now,
  }) async {
    final today = _dateOnly(now ?? DateTime.now());

    for (final level in levels) {
      final fireDate =
          _dateOnly(expiry).subtract(Duration(days: _daysBefore[level]!));
      final fireAt = DateTime(fireDate.year, fireDate.month, fireDate.day, _hour);

      if (fireDate.isBefore(today)) continue;
      if (_alreadySent(itemId, level)) continue;

      await scheduler.schedule(PendingReminder(
        id: notificationId(itemId, level),
        title: _title(level, itemName),
        body: _body(level, itemName, expiry),
        when: fireAt,
        payload: itemId,
      ));
      await _record(itemId, level, fireAt);
    }
  }

  /// Cancels every stage for one item and clears its ledger rows, so the same
  /// item added again later can be reminded about afresh.
  Future<void> cancelFor(String itemId) async {
    for (final level in NotificationLevel.values) {
      await scheduler.cancel(notificationId(itemId, level));
      await store.notifications.delete(_key(itemId, level));
    }
  }

  Future<void> cancelAll() async {
    for (final reminder in await scheduler.pending()) {
      await scheduler.cancel(reminder.id);
    }
    await store.notifications.clear();
  }

  /// Deterministic and stable: the same item and stage always produce the same
  /// id, so re-scheduling replaces the pending notification instead of adding a
  /// second one. Masked to 31 bits because Android ids are signed 32-bit.
  static int notificationId(String itemId, NotificationLevel level) {
    var hash = 17;
    for (final unit in itemId.codeUnits) {
      hash = (hash * 31 + unit) & 0x1FFFFFFF;
    }
    return (hash * 3 + level.index) & 0x7FFFFFFF;
  }

  // ----------------------------------------------------------- the ledger

  static String _key(String itemId, NotificationLevel level) =>
      '$itemId:${level.name}';

  bool _alreadySent(String itemId, NotificationLevel level) =>
      store.notifications.containsKey(_key(itemId, level));

  /// Writes the row through [ScheduledNotification.toJson] rather than
  /// hand-building a map.
  ///
  /// This box has two readers — here, and InventoryRepository when it cancels
  /// an item's reminders. An earlier version wrote a hand-rolled map with
  /// `level: "threeDay"` and no `id`, which parsed fine going out and threw a
  /// cast error coming back in. Constructing the model makes the two shapes
  /// the same by definition.
  Future<void> _record(
      String itemId, NotificationLevel level, DateTime when) async {
    final row = ScheduledNotification(
      // Deterministic, so re-recording the same stage cannot produce a second
      // row with a different id — and so the delete queued on cancellation
      // names the row the insert created.
      id: _rowId(itemId, level),
      userId: store.currentUserId ?? 'guest',
      inventoryItemId: itemId,
      level: level,
      scheduledFor: when,
    );
    await store.notifications.put(_key(itemId, level), row.toJson());
  }

  /// A uuid derived from the item id and stage, so Postgres gets a valid uuid
  /// primary key without the client having to invent a random one it would
  /// then have to remember.
  static String _rowId(String itemId, NotificationLevel level) {
    final digest = md5.convert(utf8.encode('$itemId:${level.wire}')).toString();
    return '${digest.substring(0, 8)}-${digest.substring(8, 12)}-'
        '${digest.substring(12, 16)}-${digest.substring(16, 20)}-'
        '${digest.substring(20, 32)}';
  }

  // -------------------------------------------------------------- the copy

  static String _title(NotificationLevel level, String name) =>
      switch (level) {
        NotificationLevel.threeDay => 'Three days left',
        NotificationLevel.oneDay => 'Tomorrow is the day',
        NotificationLevel.sameDay => 'Best used today',
      };

  static String _body(NotificationLevel level, String name, DateTime expiry) =>
      switch (level) {
        NotificationLevel.threeDay =>
          'Your $name has about three days in it. Worth planning a meal '
              'around.',
        NotificationLevel.oneDay =>
          'Your $name is best used by tomorrow. Have a look at what you can '
              'cook.',
        NotificationLevel.sameDay =>
          'Your $name is at its best today. There is probably a recipe for it.',
      };

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
