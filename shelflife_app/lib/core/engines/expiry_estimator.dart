// Expiry estimation — FR-05, spec §5.1.
//
// Pure: no I/O, no clock reads except the injectable `today`. That is what
// makes it testable without a device, and it must stay that way — this runs
// offline, so it can never depend on the network (Principle 6).

import '../../models/enums.dart';
import '../../models/ingredient.dart';
import '../theme/tokens.g.dart' show Freshness;

export '../theme/tokens.g.dart' show Freshness;

/// A date, where it came from, and why — in plain English.
///
/// The reason is a *return value*, not UI copy, because Principle 4 requires
/// the estimate to explain itself wherever it is shown.
class ExpiryEstimate {
  const ExpiryEstimate({
    required this.date,
    required this.source,
    required this.reason,
  });

  final DateTime date;
  final ExpirySource source;
  final String reason;
}

class ExpiryEstimator {
  const ExpiryEstimator();

  /// Last-resort shelf life per category, used when an ingredient has no figure
  /// for the chosen storage, or when the item is not in the catalogue at all.
  /// The board is explicit that a missing expiry must never block a save.
  static const Map<FoodCategory, int> _categoryDefaultDays = {
    FoodCategory.dairy: 5,
    FoodCategory.fruits: 7,
    FoodCategory.vegetables: 5,
    FoodCategory.pantry: 120,
    FoodCategory.frozen: 90,
    FoodCategory.other: 7,
  };

  /// Words for small numbers, so the reason reads as prose rather than as a
  /// data dump: "five days ago", not "5 days ago".
  static const List<String> _words = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten', 'eleven', 'twelve',
  ];

  static String _spell(int n) => n < _words.length ? _words[n] : '$n';

  /// A short, human description of a category's keeping quality, used in the
  /// explanation. "fresh greens keep about six" reads better than
  /// "vegetables keep about six".
  static String _describe(Ingredient? ing, FoodCategory category) {
    if (ing != null) {
      switch (ing.canonicalName) {
        case 'spinach':
        case 'coriander':
        case 'curry leaves':
        case 'spring onion':
          return 'fresh greens';
        case 'milk':
        case 'curd':
        case 'cream':
        case 'buttermilk':
          return 'opened dairy';
      }
    }
    return switch (category) {
      FoodCategory.dairy => 'dairy',
      FoodCategory.fruits => 'fruit',
      FoodCategory.vegetables => 'fresh vegetables',
      FoodCategory.pantry => 'pantry staples',
      FoodCategory.frozen => 'frozen food',
      FoodCategory.other => 'this',
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Resolve an expiry date, in the precedence order fixed by spec §5.1:
  /// user override, then a printed date, then per-item shelf life, then the
  /// category fallback. BR-01: the user's value always wins.
  ExpiryEstimate estimate({
    required StorageLocation storage,
    required DateTime purchaseDate,
    Ingredient? ingredient,
    FoodCategory? category,
    DateTime? printedExpiry,
    DateTime? userOverride,
    DateTime? today,
  }) {
    final bought = _dateOnly(purchaseDate);
    final now = _dateOnly(today ?? DateTime.now());
    final cat = ingredient?.category ?? category ?? FoodCategory.other;

    if (userOverride != null) {
      return ExpiryEstimate(
        date: _dateOnly(userOverride),
        source: ExpirySource.user,
        reason: 'You set this date yourself, so we leave it alone.',
      );
    }

    if (printedExpiry != null) {
      return ExpiryEstimate(
        date: _dateOnly(printedExpiry),
        source: ExpirySource.printed,
        reason: 'This is the date printed on the pack.',
      );
    }

    final itemDays = ingredient?.shelfLifeFor(storage);
    if (itemDays != null) {
      final daysHeld = now.difference(bought).inDays;
      final what = _describe(ingredient, cat);
      final reason = daysHeld > 0
          ? 'You bought this ${_spell(daysHeld)} days ago, '
              'and $what keep about ${_spell(itemDays)}.'
          : 'Fresh in today, and $what keep about ${_spell(itemDays)} days.';
      return ExpiryEstimate(
        date: bought.add(Duration(days: itemDays)),
        source: ExpirySource.estimated,
        reason: reason,
      );
    }

    final fallback = _categoryDefaultDays[cat]!;
    return ExpiryEstimate(
      date: bought.add(Duration(days: fallback)),
      source: ExpirySource.categoryDefault,
      reason: 'We estimated this from how long ${_describe(null, cat)} usually keep. '
          'Change it any time.',
    );
  }

  /// Which band an item falls into. Amber at three days out, red on the day —
  /// the thresholds from the flow board.
  Freshness freshness(DateTime expiry, {DateTime? today}) {
    final now = _dateOnly(today ?? DateTime.now());
    final days = _dateOnly(expiry).difference(now).inDays;
    if (days <= 0) return Freshness.today;
    if (days <= 3) return Freshness.soon;
    return Freshness.fresh;
  }

  /// The badge text, or null for fresh items.
  ///
  /// Returning null is the whole point of D4: green is the brand colour here,
  /// so a green "Fresh" chip reads as decoration rather than information.
  /// Marking only the exceptions is quieter and more useful — a clean row means
  /// nothing needs attention.
  String? badgeLabel(Freshness f, DateTime expiry, {DateTime? today}) {
    if (f == Freshness.fresh) return null;
    if (f == Freshness.today) return 'Best used today';
    final now = _dateOnly(today ?? DateTime.now());
    final days = _dateOnly(expiry).difference(now).inDays;
    return days == 1 ? 'Use tomorrow' : 'Use in $days days';
  }
}
