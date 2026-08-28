// Sync queue — PRD 5.8 and the board's cross-cutting sync lane.
//
// The ordering guarantee is the one worth proving: an insert followed by an
// update to the same row, replayed out of order, either fails or resurrects
// stale values. "Queue drains in original order" is a correctness requirement,
// not a nicety.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shelflife_app/database/local_store.dart';
import 'package:shelflife_app/database/sync_queue.dart';

void main() {
  late LocalStore store;
  late SyncQueue queue;

  setUp(() async {
    // A unique temp dir per test, so state never leaks between them.
    Hive.init('.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}');
    for (final name in [
      'inventory', 'consumption_events', 'shopping_list', 'recipes',
      'ingredients', 'aliases', 'products', 'notifications',
      'sync_outbox', 'meta',
    ]) {
      await Hive.openBox<dynamic>(name);
    }
    store = LocalStore.instance;
    queue = SyncQueue(store);
    await store.outbox.clear();
    await store.meta.clear();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  Future<void> add(SyncOp op, String rowId, {SyncTable table = SyncTable.inventory}) =>
      queue.enqueue(
        op: op,
        table: table,
        rowId: rowId,
        payload: {'id': rowId, 'product_name': rowId},
      );

  group('FIFO ordering', () {
    test('three offline writes drain in the order they were made', () async {
      await add(SyncOp.insert, 'a');
      await add(SyncOp.insert, 'b');
      await add(SyncOp.insert, 'c');

      expect(queue.pending().map((e) => e.rowId), ['a', 'b', 'c']);
    });

    test('an insert then an update to the same row keeps that order', () async {
      await add(SyncOp.insert, 'x');
      await add(SyncOp.update, 'x');
      await add(SyncOp.delete, 'x');

      final ops = queue.pending().map((e) => e.op).toList();
      expect(ops, [SyncOp.insert, SyncOp.update, SyncOp.delete]);
    });

    test('order survives removal of an earlier entry', () async {
      await add(SyncOp.insert, 'a');
      await add(SyncOp.insert, 'b');
      await add(SyncOp.insert, 'c');

      await queue.remove(queue.pending().first.seq);
      expect(queue.pending().map((e) => e.rowId), ['b', 'c']);
    });

    test('sequence numbers keep increasing across many writes', () async {
      for (var i = 0; i < 25; i++) {
        await add(SyncOp.insert, 'row$i');
      }
      final seqs = queue.pending().map((e) => e.seq).toList();
      expect(seqs, equals(List.generate(25, (i) => i + 1)));
    });
  });

  group('failure handling', () {
    test('a failed op stays queued', () async {
      await add(SyncOp.insert, 'a');
      final entry = queue.pending().single;
      await queue.recordFailure(entry, 'network unreachable');

      final after = queue.pending().single;
      expect(after.attempts, 1);
      expect(after.lastError, 'network unreachable');
    });

    test('a failing op does not block the ones behind it', () async {
      await add(SyncOp.insert, 'a');
      await add(SyncOp.insert, 'b');

      await queue.recordFailure(queue.pending().first, 'boom');

      // both are still pending, and b is still reachable
      expect(queue.pending().map((e) => e.rowId), ['a', 'b']);
    });

    test('backoff grows and then caps', () async {
      await add(SyncOp.insert, 'a');
      var entry = queue.pending().single;
      final waits = <int>[];
      for (var i = 0; i < 6; i++) {
        waits.add(entry.retryAfter.inSeconds);
        await queue.recordFailure(entry, 'retry $i');
        final next = queue.pending();
        if (next.isEmpty) break;
        entry = next.single;
      }
      // strictly non-decreasing, and bounded
      for (var i = 1; i < waits.length; i++) {
        expect(waits[i], greaterThanOrEqualTo(waits[i - 1]));
      }
      expect(waits.last, lessThanOrEqualTo(300));
    });

    test('an exhausted op leaves the pending list but is still visible', () async {
      await add(SyncOp.insert, 'a');
      var entry = queue.pending().single;
      for (var i = 0; i < 6; i++) {
        await queue.recordFailure(entry, 'fail $i');
        final p = queue.pending();
        if (p.isEmpty) break;
        entry = p.single;
      }
      expect(queue.pending(), isEmpty, reason: 'stops retrying');
      expect(queue.exhausted(), hasLength(1),
          reason: 'but must remain visible on the sync-error screen, not vanish');
    });
  });

  group('guest mode', () {
    test('nothing is queued while browsing as a guest', () async {
      store.isGuest = true;
      await add(SyncOp.insert, 'a');
      await add(SyncOp.insert, 'b');

      expect(queue.pendingCount, 0,
          reason: 'guest mode has no cloud leg at all');
    });

    test('queueing resumes once the guest signs up', () async {
      store.isGuest = true;
      await add(SyncOp.insert, 'ignored');
      store.isGuest = false;
      await add(SyncOp.insert, 'kept');

      expect(queue.pending().map((e) => e.rowId), ['kept']);
    });

    test('upgrade re-keys queued writes to the new user, losing nothing', () async {
      await add(SyncOp.insert, 'a');
      await add(SyncOp.insert, 'b');

      await queue.rekey('user-123');

      final entries = queue.pending();
      expect(entries, hasLength(2), reason: 'zero data loss');
      expect(entries.every((e) => e.payload['user_id'] == 'user-123'), isTrue);
      expect(entries.map((e) => e.rowId), ['a', 'b'],
          reason: 'and order is preserved through the re-key');
    });
  });

  group('sign-out (BR-05)', () {
    test('clears user data but keeps reference data', () async {
      await store.inventory.put('i1', {'id': 'i1'});
      await store.ingredients.put('ing1', {'id': 'ing1'});
      await store.recipes.put('r1', {'id': 'r1'});
      await add(SyncOp.insert, 'a');
      store.currentUserId = 'user-1';

      await store.clearUserData();

      expect(store.inventory.isEmpty, isTrue);
      expect(store.outbox.isEmpty, isTrue);
      expect(store.currentUserId, isNull);
      expect(store.ingredients.length, 1,
          reason: 'identical for every user; re-downloading it is waste');
      expect(store.recipes.length, 1);
    });
  });

  group('routing', () {
    test('each table maps to its PostgREST path', () async {
      await add(SyncOp.insert, 'a', table: SyncTable.inventory);
      await add(SyncOp.insert, 'b', table: SyncTable.consumption);
      await add(SyncOp.insert, 'c', table: SyncTable.shopping);
      await add(SyncOp.insert, 'd', table: SyncTable.notifications);
      await add(SyncOp.insert, 'e', table: SyncTable.products);

      expect(queue.pending().map((e) => e.path), [
        'inventory_items',
        'consumption_events',
        'shopping_list_items',
        'notifications',
        'products',
      ]);
    });
  });
}
