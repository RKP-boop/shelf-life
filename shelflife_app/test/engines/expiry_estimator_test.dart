// Expiry estimator — spec §5.1.
//
// Written before the implementation. These tests encode FR-05 and BR-01, and
// they run in milliseconds with no emulator, which is why the engines are built
// before any screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:shelflife_app/core/engines/expiry_estimator.dart';
import 'package:shelflife_app/models/ingredient.dart';
import 'package:shelflife_app/models/enums.dart';

/// Fresh greens: six days in the fridge, two on the counter, ninety frozen.
const spinach = Ingredient(
  id: 'i-spinach',
  canonicalName: 'spinach',
  category: FoodCategory.vegetables,
  defaultUnit: 'g',
  glyphKey: 'spinach',
  shelfLifeFridgeDays: 6,
  shelfLifeFreezerDays: 90,
  shelfLifePantryDays: null,
  shelfLifeCounterDays: 2,
  estPriceInr: 40,
);

/// Deliberately has no fridge figure, to exercise the category fallback.
const oddity = Ingredient(
  id: 'i-oddity',
  canonicalName: 'mystery pantry thing',
  category: FoodCategory.pantry,
  defaultUnit: 'g',
  glyphKey: 'cat-pantry',
  shelfLifeFridgeDays: null,
  shelfLifeFreezerDays: null,
  shelfLifePantryDays: 120,
  shelfLifeCounterDays: null,
  estPriceInr: 50,
);

final bought = DateTime(2026, 7, 20);

void main() {
  const est = ExpiryEstimator();

  group('precedence (spec §5.1, BR-01)', () {
    test('a user override beats everything else', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
        printedExpiry: DateTime(2026, 7, 30),
        userOverride: DateTime(2026, 8, 5),
      );
      expect(r.date, DateTime(2026, 8, 5));
      expect(r.source, ExpirySource.user);
    });

    test('a printed date beats an estimate', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
        printedExpiry: DateTime(2026, 7, 30),
      );
      expect(r.date, DateTime(2026, 7, 30));
      expect(r.source, ExpirySource.printed);
    });

    test('per-item shelf life is used when nothing better exists', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
      );
      expect(r.date, DateTime(2026, 7, 26)); // 20 Jul + 6
      expect(r.source, ExpirySource.estimated);
    });

    test('storage changes the estimate', () {
      final counter = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.counter,
        purchaseDate: bought,
      );
      expect(counter.date, DateTime(2026, 7, 22)); // 2 days on the counter

      final freezer = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.freezer,
        purchaseDate: bought,
      );
      expect(freezer.date, DateTime(2026, 10, 18)); // 90 days frozen
    });

    test('falls back to the category when the item has no figure for that storage', () {
      final r = est.estimate(
        ingredient: oddity,
        storage: StorageLocation.fridge, // oddity has no fridge value
        purchaseDate: bought,
      );
      expect(r.source, ExpirySource.categoryDefault);
      // pantry category default, not a crash and not "today"
      expect(r.date.isAfter(bought), isTrue);
    });

    test('an unknown ingredient still yields a date (board: never block on this)', () {
      final r = est.estimate(
        ingredient: null,
        category: FoodCategory.vegetables,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
      );
      expect(r.source, ExpirySource.categoryDefault);
      expect(r.date.isAfter(bought), isTrue);
    });
  });

  group('explainable intelligence (Principle 4)', () {
    test('an estimate explains itself in plain English', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
        today: DateTime(2026, 7, 25), // five days later
      );
      // Screen 29 renders this verbatim.
      expect(r.reason, 'You bought this five days ago, and fresh greens keep about six.');
    });

    test('a printed date says so, rather than inventing a rationale', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
        printedExpiry: DateTime(2026, 7, 30),
      );
      expect(r.reason, contains('printed'));
    });

    test('a user override credits the user', () {
      final r = est.estimate(
        ingredient: spinach,
        storage: StorageLocation.fridge,
        purchaseDate: bought,
        userOverride: DateTime(2026, 8, 1),
      );
      expect(r.reason, contains('You set'));
    });

    test('no reason string uses a forbidden word (PRD 4.10)', () {
      final forbidden = RegExp(r'\b(Error|Expired|Failed|Warning)\b');
      for (final storage in StorageLocation.values) {
        final r = est.estimate(
          ingredient: spinach,
          storage: storage,
          purchaseDate: bought,
        );
        expect(forbidden.hasMatch(r.reason), isFalse, reason: r.reason);
      }
    });
  });

  group('freshness banding (D4)', () {
    final today = DateTime(2026, 7, 25);

    test('due today or overdue is the red band', () {
      expect(est.freshness(DateTime(2026, 7, 25), today: today), Freshness.today);
      expect(est.freshness(DateTime(2026, 7, 24), today: today), Freshness.today);
    });

    test('within three days is the amber band', () {
      expect(est.freshness(DateTime(2026, 7, 26), today: today), Freshness.soon);
      expect(est.freshness(DateTime(2026, 7, 28), today: today), Freshness.soon);
    });

    test('beyond three days is fresh, which carries NO badge', () {
      expect(est.freshness(DateTime(2026, 7, 29), today: today), Freshness.fresh);
      expect(est.freshness(DateTime(2026, 12, 1), today: today), Freshness.fresh);
    });

    test('a fresh item produces no badge label at all', () {
      // Silence is the signal: a clean row means nothing needs attention.
      expect(est.badgeLabel(Freshness.fresh, DateTime(2026, 7, 29), today: today), isNull);
    });

    test('badge labels match the designed copy', () {
      expect(est.badgeLabel(Freshness.today, DateTime(2026, 7, 25), today: today),
          'Best used today');
      expect(est.badgeLabel(Freshness.soon, DateTime(2026, 7, 26), today: today),
          'Use tomorrow');
      expect(est.badgeLabel(Freshness.soon, DateTime(2026, 7, 27), today: today),
          'Use in 2 days');
    });
  });
}
