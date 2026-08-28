// Recipe scoring — FR-07, spec §5.2.
//
// Deliberately mirrors supabase/migrations/004_functions.sql. The app ranks
// offline from Hive; the server ranks the same recipes over PostgREST. If the
// two drift, the Recipes tab changes order when connectivity changes, which
// looks like a bug to the user. The shared fixture in the tests is what keeps
// them honest.

class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientId,
    required this.canonicalName,
    this.optional = false,
  });

  final String ingredientId;
  final String canonicalName;
  final bool optional;
}

class RecipeCandidate {
  const RecipeCandidate({
    required this.id,
    required this.name,
    required this.prepMinutes,
    required this.ingredients,
    this.imageKey,
  });

  final String id;
  final String name;
  final int prepMinutes;
  final List<RecipeIngredient> ingredients;
  final String? imageKey;
}

/// A scored match, carrying everything the UI needs.
///
/// `score` orders the list and is NEVER rendered. Screens show
/// `matchLabel` ("7 of 9 ingredients") and name the urgent items, because
/// "78% match" tells the user nothing actionable.
class RecipeMatch {
  const RecipeMatch({
    required this.id,
    required this.name,
    required this.prepMinutes,
    required this.imageKey,
    required this.totalRequired,
    required this.haveCount,
    required this.haveNames,
    required this.missingNames,
    required this.urgentNames,
    required this.score,
  });

  final String id;
  final String name;
  final int prepMinutes;
  final String? imageKey;
  final int totalRequired;
  final int haveCount;
  final List<String> haveNames;
  final List<String> missingNames;

  /// Held ingredients that are due today or overdue. Screen 33 turns these into
  /// "Uses your spinach and paneer, both best used today."
  final List<String> urgentNames;

  final double score;

  String get matchLabel => '$haveCount of $totalRequired ingredients';

  /// The urgency line, or null when nothing in this recipe is pressing.
  String? get urgencyLine {
    if (urgentNames.isEmpty) return null;
    final names = urgentNames.length == 1
        ? urgentNames.single
        : '${urgentNames.sublist(0, urgentNames.length - 1).join(', ')} '
            'and ${urgentNames.last}';
    final tail = urgentNames.length == 1
        ? 'best used today'
        : 'both best used today';
    return 'Uses your $names, $tail.';
  }
}

class RecipeScorer {
  const RecipeScorer();

  static const double _availabilityWeight = 0.6;
  static const double _urgencyWeight = 0.3;
  static const double _speedWeight = 0.1;

  /// Urgency reaches 1.0 on the day and decays to 0 over three days, matching
  /// the amber band. Speed decays over an hour.
  static const int _urgencyWindowDays = 3;
  static const int _speedWindowMinutes = 60;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Score one recipe against what the user holds.
  ///
  /// [held] maps ingredient id to the soonest expiry among duplicates.
  /// Returns null when nothing in the recipe is available — such a recipe is
  /// noise on the Recipes tab, so it is dropped rather than ranked last.
  RecipeMatch? score(
    RecipeCandidate recipe,
    Map<String, DateTime> held, {
    DateTime? today,
  }) {
    final now = _dateOnly(today ?? DateTime.now());

    final required = recipe.ingredients.where((i) => !i.optional).toList();
    if (required.isEmpty) return null;

    final have = <String>[];
    final missing = <String>[];
    final urgent = <String>[];
    var peakUrgency = 0.0;

    for (final ing in required) {
      final expiry = held[ing.ingredientId];
      if (expiry == null) {
        missing.add(ing.canonicalName);
        continue;
      }
      have.add(ing.canonicalName);

      final days = _dateOnly(expiry).difference(now).inDays;
      if (days <= 0) urgent.add(ing.canonicalName);

      final u = (1 - days / _urgencyWindowDays).clamp(0.0, 1.0).toDouble();
      if (u > peakUrgency) peakUrgency = u;
    }

    if (have.isEmpty) return null;

    final availability = have.length / required.length;
    final speed =
        (1 - recipe.prepMinutes / _speedWindowMinutes).clamp(0.0, 1.0).toDouble();

    final score = _availabilityWeight * availability +
        _urgencyWeight * peakUrgency +
        _speedWeight * speed;

    have.sort();
    missing.sort();
    urgent.sort();

    return RecipeMatch(
      id: recipe.id,
      name: recipe.name,
      prepMinutes: recipe.prepMinutes,
      imageKey: recipe.imageKey,
      totalRequired: required.length,
      haveCount: have.length,
      haveNames: have,
      missingNames: missing,
      urgentNames: urgent,
      score: score,
    );
  }

  /// Rank a set of recipes, best first.
  ///
  /// Ties break on availability, then speed, then name — so the order is
  /// deterministic. A list that reshuffles between identical runs reads as
  /// broken even when the scores are correct.
  List<RecipeMatch> rank(
    List<RecipeCandidate> recipes,
    Map<String, DateTime> held, {
    DateTime? today,
    int limit = 20,
  }) {
    final matches = <RecipeMatch>[];
    for (final r in recipes) {
      final m = score(r, held, today: today);
      if (m != null) matches.add(m);
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byHave = b.haveCount.compareTo(a.haveCount);
      if (byHave != 0) return byHave;
      final bySpeed = a.prepMinutes.compareTo(b.prepMinutes);
      if (bySpeed != 0) return bySpeed;
      return a.name.compareTo(b.name);
    });
    return matches.take(limit).toList();
  }
}
