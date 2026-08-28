// Hive persistence.
//
// Boxes hold plain JSON maps rather than Hive TypeAdapters. That is a
// deliberate choice: adapters need code generation, and a schema change then
// means regenerating and migrating adapters. Storing maps keeps the
// model layer as the single place that knows the shape, and there is no
// build_runner step to break.
//
// PRD 5.7 / Principle 6: Hive is the source of truth. Every read in the app
// comes from here, so no screen ever waits on the network.

import 'package:hive_ce_flutter/hive_flutter.dart';

class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const _inventory = 'inventory';
  static const _events = 'consumption_events';
  static const _shopping = 'shopping_list';
  static const _recipes = 'recipes';
  static const _ingredients = 'ingredients';
  static const _aliases = 'aliases';
  static const _products = 'products';
  static const _notifications = 'notifications';
  static const _outbox = 'sync_outbox';
  static const _meta = 'meta';

  static const _allBoxes = [
    _inventory, _events, _shopping, _recipes, _ingredients,
    _aliases, _products, _notifications, _outbox, _meta,
  ];

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter('shelflife');
    for (final name in _allBoxes) {
      await Hive.openBox<dynamic>(name);
    }
    _ready = true;
  }

  Box<dynamic> _box(String name) => Hive.box<dynamic>(name);

  Box<dynamic> get inventory => _box(_inventory);
  Box<dynamic> get events => _box(_events);
  Box<dynamic> get shopping => _box(_shopping);
  Box<dynamic> get recipes => _box(_recipes);
  Box<dynamic> get ingredients => _box(_ingredients);
  Box<dynamic> get aliases => _box(_aliases);
  Box<dynamic> get products => _box(_products);
  Box<dynamic> get notifications => _box(_notifications);
  Box<dynamic> get outbox => _box(_outbox);
  Box<dynamic> get meta => _box(_meta);

  /// Hive returns `Map<dynamic, dynamic>` for nested maps, which cannot be
  /// passed to a `Map<String, dynamic>` parameter. Every read goes through
  /// here so that conversion happens in exactly one place.
  static Map<String, dynamic> cast(Object? raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return map.map((k, v) => MapEntry(k, _deep(v)));
  }

  static Object? _deep(Object? v) {
    if (v is Map) {
      return v.cast<String, dynamic>().map((k, x) => MapEntry(k, _deep(x)));
    }
    if (v is List) return v.map(_deep).toList();
    return v;
  }

  List<Map<String, dynamic>> readAll(Box<dynamic> box) =>
      box.values.map(cast).toList();

  // ------------------------------------------------------------------ meta

  String? get currentUserId => meta.get('user_id') as String?;
  set currentUserId(String? v) =>
      v == null ? meta.delete('user_id') : meta.put('user_id', v);

  /// True while the user has not signed in. Guest mode has no cloud leg at
  /// all — the board is explicit about that.
  bool get isGuest => (meta.get('is_guest') as bool?) ?? false;
  set isGuest(bool v) => meta.put('is_guest', v);

  DateTime? get lastSyncAt {
    final s = meta.get('last_sync_at') as String?;
    return s == null ? null : DateTime.tryParse(s);
  }

  set lastSyncAt(DateTime? v) =>
      meta.put('last_sync_at', v?.toIso8601String());

  /// Clears everything on sign-out (BR-05: inventory is unique per account, so
  /// one account's data must not be visible to the next).
  Future<void> clearUserData() async {
    await inventory.clear();
    await events.clear();
    await shopping.clear();
    await notifications.clear();
    await outbox.clear();
    await meta.delete('user_id');
    await meta.delete('last_sync_at');
    await meta.delete('is_guest');
  }

  /// Reference data survives sign-out: it is identical for every user, and
  /// re-downloading 65 ingredients and 40 recipes on each login is waste.
  Future<void> clearEverything() async {
    for (final name in _allBoxes) {
      await _box(name).clear();
    }
  }
}
