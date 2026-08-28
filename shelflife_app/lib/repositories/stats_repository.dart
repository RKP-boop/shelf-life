// Statistics — FR-09.
//
// Computes the same figures as `kitchen_stats()` in
// supabase/migrations/004_functions.sql, offline from Hive. The two must agree:
// the dashboard reads this while offline and the RPC when online, and a
// discrepancy would make the numbers appear to change with connectivity.
//
// Principle 3 governs the output. `removed` events are read here because
// "% used in time" needs a denominator, but nothing returned is a waste count.

import '../core/engines/expiry_estimator.dart';
import '../database/local_store.dart';
import '../models/enums.dart';
import '../models/inventory_item.dart';
import '../models/models.dart';

class StatsRepository {
  const StatsRepository({
    required this.store,
    this.estimator = const ExpiryEstimator(),
  });

  final LocalStore store;
  final ExpiryEstimator estimator;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  KitchenStats compute({DateTime? today}) {
    final now = _dateOnly(today ?? DateTime.now());
    final monthStart = DateTime(now.year, now.month, 1);

    final items = store
        .readAll(store.inventory)
        .map(InventoryItem.fromJson)
        .where((i) => i.status == ItemStatus.active)
        .toList();

    final events = store
        .readAll(store.events)
        .map(ConsumptionEvent.fromJson)
        .toList();

    final activeItems = items.length;
    final expiringSoon = items
        .where((i) => !_dateOnly(i.expiryDate).isAfter(now.add(const Duration(days: 3))))
        .length;
    final dueToday =
        items.where((i) => !_dateOnly(i.expiryDate).isAfter(now)).length;

    final thisMonth = events
        .where((e) => !e.occurredAt.isBefore(monthStart))
        .toList();
    final rescued = thisMonth.where((e) => e.countsAsRescued).toList();
    final valueRescued =
        rescued.fold<double>(0, (sum, e) => sum + (e.estValueInr ?? 0));

    return KitchenStats(
      activeItems: activeItems,
      expiringSoon: expiringSoon,
      dueToday: dueToday,
      mealsRescued: rescued.length,
      valueRescuedInr: valueRescued,
      currentStreak: _streak(events, now),
      pctUsedInTime: _pctUsedInTime(events),
    );
  }

  /// Percent used on or before the expiry date, all time.
  ///
  /// Null rather than 0 when there is no history — "0% used in time" for a new
  /// user would be both wrong and discouraging, which Principle 3 forbids.
  int? _pctUsedInTime(List<ConsumptionEvent> events) {
    if (events.isEmpty) return null;
    final good = events.where((e) {
      if (!e.countsAsRescued) return false;
      final expiry = e.expiryDate;
      if (expiry == null) return true;
      return !_dateOnly(e.occurredAt).isAfter(_dateOnly(expiry));
    }).length;
    return ((100 * good) / events.length).round();
  }

  /// Consecutive days, ending today or yesterday, on which at least one item
  /// was used.
  ///
  /// Yesterday counts so the streak does not read as broken before the user has
  /// cooked today. This mirrors the SQL gaps-and-islands query — where an
  /// earlier version used `d - rownum` instead of `d + rownum` and therefore
  /// always returned 1.
  int _streak(List<ConsumptionEvent> events, DateTime now) {
    final days = events
        .where((e) => e.countsAsRescued)
        .map((e) => _dateOnly(e.occurredAt))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

    if (days.isEmpty) return 0;

    final latest = days.first;
    final gapFromToday = now.difference(latest).inDays;
    if (gapFromToday > 1) return 0; // streak already broken

    var length = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i - 1].difference(days[i]).inDays == 1) {
        length++;
      } else {
        break;
      }
    }
    return length;
  }
}
