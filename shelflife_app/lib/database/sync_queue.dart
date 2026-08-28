// Offline write queue — PRD 5.8, and the board's cross-cutting sync lane.
//
// Every write goes to Hive first and appends an operation here. On reconnect
// the queue drains in original order. That ordering matters: an insert followed
// by an update to the same row, replayed out of order, would either fail or
// resurrect stale values.
//
// Conflict resolution is last-write-wins with both timestamps retained, per
// PRD 5.8. Not per-field merge — the board lists that as a future need once
// households share one inventory, and building it now would be speculative.

import 'dart:convert';

import 'local_store.dart';

enum SyncOp { insert, update, delete }

enum SyncTable { inventory, consumption, shopping, notifications, products }

/// One pending write.
class SyncEntry {
  const SyncEntry({
    required this.seq,
    required this.op,
    required this.table,
    required this.rowId,
    required this.payload,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  /// Monotonic, so FIFO order survives a restart. Hive keys are insertion
  /// ordered but not guaranteed stable across compaction, so the order is
  /// stored explicitly rather than inferred.
  final int seq;

  final SyncOp op;
  final SyncTable table;
  final String rowId;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  /// PostgREST path for this table.
  String get path => switch (table) {
        SyncTable.inventory => 'inventory_items',
        SyncTable.consumption => 'consumption_events',
        SyncTable.shopping => 'shopping_list_items',
        SyncTable.notifications => 'notifications',
        SyncTable.products => 'products',
      };

  /// Exponential backoff, capped. A row that keeps failing must not spin, and
  /// must not block the rows behind it either.
  Duration get retryAfter =>
      Duration(seconds: [0, 2, 8, 30, 120, 300][attempts.clamp(0, 5)]);

  bool get exhausted => attempts >= 6;

  SyncEntry withFailure(String error) => SyncEntry(
        seq: seq,
        op: op,
        table: table,
        rowId: rowId,
        payload: payload,
        queuedAt: queuedAt,
        attempts: attempts + 1,
        lastError: error,
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'op': op.name,
        'table': table.name,
        'row_id': rowId,
        'payload': jsonEncode(payload),
        'queued_at': queuedAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };

  factory SyncEntry.fromJson(Map<String, dynamic> j) => SyncEntry(
        seq: (j['seq'] as num).toInt(),
        op: SyncOp.values.byName(j['op'] as String),
        table: SyncTable.values.byName(j['table'] as String),
        rowId: j['row_id'] as String,
        payload: (jsonDecode(j['payload'] as String) as Map)
            .cast<String, dynamic>(),
        queuedAt: DateTime.parse(j['queued_at'] as String),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['last_error'] as String?,
      );
}

class SyncQueue {
  SyncQueue(this._store);

  final LocalStore _store;

  static const _seqKey = 'sync_seq';

  int _nextSeq() {
    final current = (_store.meta.get(_seqKey) as int?) ?? 0;
    final next = current + 1;
    _store.meta.put(_seqKey, next);
    return next;
  }

  /// Queue a write. Guest mode never reaches the network, so nothing is queued
  /// — the board is explicit that guest has no cloud leg at all.
  Future<void> enqueue({
    required SyncOp op,
    required SyncTable table,
    required String rowId,
    required Map<String, dynamic> payload,
  }) async {
    if (_store.isGuest) return;

    final entry = SyncEntry(
      seq: _nextSeq(),
      op: op,
      table: table,
      rowId: rowId,
      payload: payload,
      queuedAt: DateTime.now(),
    );
    await _store.outbox.put('${entry.seq}', entry.toJson());
  }

  /// Pending writes in the order they were made.
  List<SyncEntry> pending() {
    final entries = _store.outbox.values
        .map((raw) => SyncEntry.fromJson(LocalStore.cast(raw)))
        .where((e) => !e.exhausted)
        .toList();
    entries.sort((a, b) => a.seq.compareTo(b.seq));
    return entries;
  }

  /// Writes that gave up. Surfaced on the sync-error screen rather than hidden,
  /// so a permanent failure is visible instead of silently dropped.
  List<SyncEntry> exhausted() => _store.outbox.values
      .map((raw) => SyncEntry.fromJson(LocalStore.cast(raw)))
      .where((e) => e.exhausted)
      .toList();

  int get pendingCount => pending().length;

  Future<void> remove(int seq) => _store.outbox.delete('$seq');

  Future<void> recordFailure(SyncEntry entry, String error) =>
      _store.outbox.put('${entry.seq}', entry.withFailure(error).toJson());

  Future<void> clear() => _store.outbox.clear();

  /// Re-key every queued write to a new user id.
  ///
  /// Used by the guest upgrade: the board requires local rows to be re-keyed
  /// and pushed with zero data loss, so a guest who signs up keeps the kitchen
  /// they already built.
  Future<void> rekey(String userId) async {
    for (final key in _store.outbox.keys.toList()) {
      final entry = SyncEntry.fromJson(LocalStore.cast(_store.outbox.get(key)));
      final payload = Map<String, dynamic>.from(entry.payload)
        ..['user_id'] = userId;
      await _store.outbox.put(
        key,
        SyncEntry(
          seq: entry.seq,
          op: entry.op,
          table: entry.table,
          rowId: entry.rowId,
          payload: payload,
          queuedAt: entry.queuedAt,
        ).toJson(),
      );
    }
  }
}
