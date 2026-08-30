/// Opens Hive for a test without touching path_provider.
///
/// `LocalStore.init()` calls `Hive.initFlutter`, which needs the
/// path_provider plugin — absent in `flutter test`, where it throws
/// MissingPluginException. Opening the boxes directly against a temp directory
/// gives the same store with no plugin channel involved.
///
/// A fresh directory per call, so state never leaks between tests.
library;

import 'dart:io';
import 'dart:math';

import 'package:hive_ce/hive.dart';
import 'package:shelflife_app/database/local_store.dart';

/// Must match LocalStore's box list. A box opened here but not there (or the
/// reverse) shows up as a confusing "box not found" deep inside a repository.
const hiveBoxes = [
  'inventory',
  'consumption_events',
  'shopping_list',
  'recipes',
  'ingredients',
  'aliases',
  'products',
  'notifications',
  'sync_outbox',
  'meta',
];

var _counter = 0;

/// A timestamp alone is not unique enough: `flutter test` runs files
/// concurrently, and two of them starting in the same microsecond opened the
/// same directory and deadlocked on Hive's lock file. Process id plus a
/// per-isolate counter plus randomness makes a collision impossible rather
/// than unlikely.
String _uniqueDir() =>
    '.dart_tool/test_hive_${pid}_${_counter++}_'
    '${Random().nextInt(1 << 32).toRadixString(36)}';

Future<LocalStore> openTestStore() async {
  Hive.init(_uniqueDir());
  for (final name in hiveBoxes) {
    await Hive.openBox<dynamic>(name);
  }
  return LocalStore.instance;
}

Future<void> closeTestStore() => Hive.deleteFromDisk();
