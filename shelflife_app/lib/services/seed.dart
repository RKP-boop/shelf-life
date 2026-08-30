// First-run seeding.
//
// The catalogue, aliases, recipes and barcode cache ship inside the APK rather
// than being fetched. Two reasons, both from the spec:
//
//  - Principle 6. A first-run user with no connection has to get a working
//    product, not an empty one.
//  - D1. The barcode cache is the *only* lookup path — there is no external
//    product API — so it cannot be something the app might not have.
//
// Reference rows carry ids derived from their natural key (migration 006), so
// an `inventory_items` row written on a phone that has never reached the
// server still satisfies its foreign key when it finally syncs.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../database/local_store.dart';

abstract final class Seed {
  static const asset = 'assets/seed/reference.json';

  /// Bumped when `reference.json` changes. A store seeded by an older build is
  /// re-seeded rather than left with a stale catalogue.
  static const version = 1;

  static const _versionKey = 'seed_version';

  /// Seeds if this store has never been seeded, or was seeded by an older
  /// build. Cheap no-op otherwise, so it is safe on every launch.
  static Future<void> ensure(LocalStore store) async {
    final current = store.meta.get(_versionKey) as int?;
    if (current == version) return;

    final raw = await rootBundle.loadString(asset);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    await _seedIngredients(store, json['ingredients'] as List<dynamic>);
    await _seedAliases(store, json['aliases'] as List<dynamic>);
    await _seedRecipes(store, json['recipes'] as List<dynamic>);
    await _seedProducts(store, json['products'] as List<dynamic>);

    await store.meta.put(_versionKey, version);
  }

  static Future<void> _seedIngredients(
      LocalStore store, List<dynamic> rows) async {
    await store.ingredients.clear();
    await store.ingredients.putAll({
      for (final row in rows.cast<Map<String, dynamic>>())
        row['id'] as String: row,
    });
  }

  /// Keyed by the alias itself: the receipt parser looks up alias -> canonical,
  /// never the reverse.
  static Future<void> _seedAliases(
      LocalStore store, List<dynamic> rows) async {
    await store.aliases.clear();
    await store.aliases.putAll({
      for (final row in rows.cast<Map<String, dynamic>>())
        row['alias'] as String: row,
    });
  }

  static Future<void> _seedRecipes(
      LocalStore store, List<dynamic> rows) async {
    await store.recipes.clear();
    await store.recipes.putAll({
      for (final row in rows.cast<Map<String, dynamic>>())
        row['id'] as String: row,
    });
  }

  /// Barcode is the key, because that is the only way this table is ever read.
  ///
  /// Seeded rows are not cleared on re-seed the way the others are: a barcode
  /// the user taught the app (screen 22, "we will remember it for next time")
  /// lives in this same box, and wiping it would break that promise. Seeded
  /// rows overwrite by key; user rows are left alone.
  static Future<void> _seedProducts(
      LocalStore store, List<dynamic> rows) async {
    await store.products.putAll({
      for (final row in rows.cast<Map<String, dynamic>>())
        row['barcode'] as String: row,
    });
  }
}
