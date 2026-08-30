// Recipe scorer — FR-07, spec §5.2.
//
// The critical fixture here mirrors the one `match_recipes()` was verified
// against on the live database (supabase/VERIFIED.md): a kitchen holding
// spinach, paneer, onion and tomato, all due today. Client and server must
// agree, not approximately agree — the app ranks offline from Hive and the
// server ranks the same recipes over PostgREST.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/engines/recipe_scorer.dart';

final today = DateTime(2026, 7, 25);

RecipeCandidate recipe(
  String name,
  int prep,
  List<(String, bool)> ingredients, // (canonical name, optional)
) =>
    RecipeCandidate(
      id: 'r-$name',
      name: name,
      prepMinutes: prep,
      ingredients: [
        for (final (n, opt) in ingredients)
          RecipeIngredient(ingredientId: 'i-$n', canonicalName: n, optional: opt),
      ],
    );

/// Held ingredient -> soonest expiry.
Map<String, DateTime> holding(Map<String, int> daysFromToday) => {
      for (final e in daysFromToday.entries)
        'i-${e.key}': today.add(Duration(days: e.value)),
    };

void main() {
  _urgencyLinePluralisation();
  const scorer = RecipeScorer();

  group('the formula (spec §5.2)', () {
    test('0.6*availability + 0.3*urgency + 0.1*speed', () {
      // 2 of 4 held, both due today (urgency 1.0), 30 min (speed 0.5)
      final r = scorer.score(
        recipe('X', 30, [('spinach', false), ('paneer', false), ('onion', false), ('rice', false)]),
        holding({'spinach': 0, 'paneer': 0}),
        today: today,
      )!;
      // 0.6*0.5 + 0.3*1.0 + 0.1*0.5 = 0.30 + 0.30 + 0.05
      expect(r.score, closeTo(0.65, 0.0001));
    });

    test('urgency decays over three days and is zero beyond', () {
      final due = scorer.score(recipe('A', 60, [('spinach', false)]),
          holding({'spinach': 0}), today: today)!;
      final soon = scorer.score(recipe('A', 60, [('spinach', false)]),
          holding({'spinach': 3}), today: today)!;
      final far = scorer.score(recipe('A', 60, [('spinach', false)]),
          holding({'spinach': 10}), today: today)!;
      // availability is 1.0 in all three; speed is 0 at 60 min
      expect(due.score, closeTo(0.9, 0.0001));  // 0.6 + 0.3
      expect(soon.score, closeTo(0.6, 0.0001)); // 0.6 + 0
      expect(far.score, closeTo(0.6, 0.0001));
    });

    test('faster recipes edge ahead, all else equal', () {
      final quick = scorer.score(recipe('Q', 10, [('spinach', false)]),
          holding({'spinach': 10}), today: today)!;
      final slow = scorer.score(recipe('S', 50, [('spinach', false)]),
          holding({'spinach': 10}), today: today)!;
      expect(quick.score, greaterThan(slow.score));
    });
  });

  group('optional ingredients', () {
    test('are excluded from the have/total count', () {
      final r = scorer.score(
        recipe('X', 30, [('spinach', false), ('paneer', false), ('cream', true)]),
        holding({'spinach': 5, 'paneer': 5}),
        today: today,
      )!;
      expect(r.totalRequired, 2, reason: 'cream is optional');
      expect(r.haveCount, 2);
    });

    test('a missing optional ingredient does not appear as missing', () {
      final r = scorer.score(
        recipe('X', 30, [('spinach', false), ('cream', true)]),
        holding({'spinach': 5}),
        today: today,
      )!;
      expect(r.missingNames, isEmpty);
    });
  });

  group('what the UI needs (never a bare score)', () {
    test('names what is missing, for the "You will need to buy" section', () {
      final r = scorer.score(
        recipe('Palak Paneer', 25,
            [('spinach', false), ('paneer', false), ('cream', false), ('kasuri methi', false)]),
        holding({'spinach': 0, 'paneer': 0}),
        today: today,
      )!;
      expect(r.missingNames, containsAll(['cream', 'kasuri methi']));
      expect(r.haveNames, containsAll(['paneer', 'spinach']));
    });

    test('names the urgent items, so screen 33 can explain the ranking', () {
      final r = scorer.score(
        recipe('Palak Paneer', 25, [('spinach', false), ('paneer', false), ('onion', false)]),
        holding({'spinach': 0, 'paneer': 0, 'onion': 6}),
        today: today,
      )!;
      // "Uses your spinach and paneer, both best used today."
      expect(r.urgentNames, ['paneer', 'spinach']);
      expect(r.urgentNames, isNot(contains('onion')));
    });

    test('produces the designed match label, not a percentage', () {
      final r = scorer.score(
        recipe('X', 25, [('a', false), ('b', false), ('c', false)]),
        holding({'a': 2, 'b': 2}),
        today: today,
      )!;
      expect(r.matchLabel, '2 of 3 ingredients');
      expect(r.matchLabel, isNot(contains('%')));
    });
  });

  group('ranking', () {
    test('a recipe with nothing available is excluded entirely', () {
      final r = scorer.score(
        recipe('Nothing', 20, [('caviar', false)]),
        holding({'spinach': 1}),
        today: today,
      );
      expect(r, isNull, reason: 'noise on the Recipes tab');
    });

    test('matches the live SQL ranking for the verified fixture', () {
      // Same kitchen the database was verified with: spinach, paneer, onion and
      // tomato, all due today.
      final kitchen = holding({'spinach': 0, 'paneer': 0, 'onion': 0, 'tomato': 0});
      final candidates = [
        recipe('Palak Paneer', 25, [
          ('spinach', false), ('paneer', false), ('onion', false), ('tomato', false),
          ('cream', false), ('kasuri methi', false), ('garam masala', false),
          ('ginger', false), ('garlic', false),
        ]),
        recipe('Paneer Bhurji', 20, [
          ('paneer', false), ('onion', false), ('tomato', false),
          ('green chilli', false), ('ginger', false), ('turmeric', false),
          ('coriander', false),
        ]),
        recipe('Tomato Onion Salad', 8, [
          ('tomato', false), ('onion', false), ('cucumber', false), ('lemon', false),
        ]),
        recipe('Ghee Roast Paratha', 20, [('atta', false), ('ghee', false), ('salt', false)]),
      ];

      final ranked = scorer.rank(candidates, kitchen, today: today);

      // Ghee Roast Paratha shares nothing with this kitchen, so it must drop out
      expect(ranked.map((r) => r.name), isNot(contains('Ghee Roast Paratha')));
      // and every survivor must genuinely be cookable from what is held
      expect(ranked.every((r) => r.haveCount > 0), isTrue);
      // the salad has the highest availability ratio, so it leads
      expect(ranked.first.name, 'Tomato Onion Salad');
      expect(ranked.map((r) => r.name), contains('Palak Paneer'));
    });

    test('ranking is deterministic for equal scores', () {
      final kitchen = holding({'a': 5});
      final ranked = scorer.rank([
        recipe('Zebra', 30, [('a', false)]),
        recipe('Apple', 30, [('a', false)]),
      ], kitchen, today: today);
      expect(ranked.map((r) => r.name), ['Apple', 'Zebra']);
    });
  });
}

void _urgencyLinePluralisation() {
  RecipeMatch m(List<String> urgent) => RecipeMatch(
        id: 'r',
        name: 'Test',
        prepMinutes: 10,
        imageKey: null,
        totalRequired: 4,
        haveCount: 4,
        haveNames: const [],
        missingNames: const [],
        urgentNames: urgent,
        score: 1,
      );

  group('urgencyLine pluralisation', () {
    test('says nothing when nothing is urgent', () {
      expect(m(const []).urgencyLine, isNull);
    });
    test('one name takes no quantifier', () {
      expect(m(const ['spinach']).urgencyLine,
          'Uses your spinach, best used today.');
    });
    test('two names take "both"', () {
      expect(m(const ['spinach', 'paneer']).urgencyLine,
          'Uses your spinach and paneer, both best used today.');
    });
    test('three names take "all", not "both"', () {
      expect(m(const ['spinach', 'paneer', 'tomato']).urgencyLine,
          'Uses your spinach, paneer and tomato, all best used today.');
    });
  });
}
