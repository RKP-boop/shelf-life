// Draining the outbox to Supabase.
//
// Principle 6, restated as a rule this file obeys absolutely: no read path
// touches the network. Hive is the source of truth; this only pushes.
//
// The queue itself — ordering, backoff, exhaustion, and the PostgREST path for
// each table — lives in SyncQueue. This class is only the transport: when to
// try, what to call, and how to read the answer. Keeping them apart is why the
// queue's ordering and backoff tests need no network at all.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/capabilities.dart';
import '../database/local_store.dart';
import '../database/sync_queue.dart';

enum SyncPhase { idle, running, offline }

class SyncService extends ChangeNotifier {
  SyncService({
    required this.queue,
    required this.store,
    required this.connectivity,
    this.client,
  });

  final SyncQueue queue;
  final LocalStore store;
  final ConnectivityService connectivity;

  /// Null in guest mode and in tests. A null client means "queue and do
  /// nothing", which is exactly the guest-mode contract.
  final SupabaseClient? client;

  SyncPhase _phase = SyncPhase.idle;
  SyncPhase get phase => _phase;

  DateTime? _lastSynced;
  DateTime? get lastSynced => _lastSynced;

  String? _lastProblem;

  /// The most recent transport problem, in the user's terms. Null when the last
  /// attempt succeeded or none has been made.
  String? get lastProblem => _lastProblem;

  int get pendingCount => queue.pendingCount;
  int get exhaustedCount => queue.exhausted().length;

  bool _online = true;
  bool get isOnline => _online;

  StreamSubscription<bool>? _connSub;
  Timer? _retryTimer;

  /// Starts watching connectivity and drains once if already online.
  Future<void> start() async {
    _online = await connectivity.isOnline;
    _connSub = connectivity.onChanged.listen((online) {
      _online = online;
      notifyListeners();
      // Coming back online is the single best moment to drain, and it costs
      // nothing when the queue is empty.
      if (online) nudge();
    });
    nudge();
  }

  /// Asks for a drain. Cheap and safe to call after every write — it returns
  /// immediately when there is nothing to do, no client, or no connection.
  void nudge() {
    if (client == null) return;
    if (!_online) {
      _setPhase(SyncPhase.offline);
      return;
    }
    if (_phase == SyncPhase.running) return;
    if (queue.pendingCount == 0) {
      _setPhase(SyncPhase.idle);
      return;
    }
    unawaited(drain());
  }

  /// Pushes queued operations in `seq` order, stopping at the first failure.
  ///
  /// Stopping rather than skipping is the important part: an update queued
  /// after an insert cannot be applied before it, so a failed insert must block
  /// its own follow-ups rather than let them fail individually.
  Future<void> drain() async {
    final api = client;
    if (api == null || !_online) return;

    _setPhase(SyncPhase.running);
    _lastProblem = null;

    try {
      for (final entry in queue.pending()) {
        try {
          await _push(api, entry);
          await queue.remove(entry.seq);
        } on PostgrestException catch (e) {
          // A conflict on insert means the row is already there — the previous
          // attempt succeeded and the acknowledgement was lost. Treat it as
          // done rather than retrying forever.
          if (e.code == '23505' && entry.op == SyncOp.insert) {
            await queue.remove(entry.seq);
            continue;
          }
          await queue.recordFailure(entry, '${e.code}: ${e.message}');
          _lastProblem = _humanise(e);
          break;
        } catch (e) {
          await queue.recordFailure(entry, e.toString());
          _lastProblem = 'We could not reach the server just now.';
          break;
        }
      }
      if (queue.pendingCount == 0) {
        _lastSynced = DateTime.now();
        await store.meta.put('last_synced', _lastSynced!.toIso8601String());
      }
    } finally {
      _setPhase(_online ? SyncPhase.idle : SyncPhase.offline);
      _scheduleRetryIfNeeded();
    }
  }

  Future<void> _push(SupabaseClient api, SyncEntry entry) async {
    final table = api.from(entry.path);
    switch (entry.op) {
      case SyncOp.insert:
        // Upsert rather than insert: a client-generated id plus a lost
        // acknowledgement would otherwise wedge the queue permanently.
        await table.upsert(entry.payload);
      case SyncOp.update:
        await table.update(entry.payload).eq('id', entry.payload['id'] as Object);
      case SyncOp.delete:
        await table.delete().eq('id', entry.payload['id'] as Object);
    }
  }

  /// Retries on the queue's own backoff schedule rather than a fixed interval,
  /// so a persistent failure does not hammer the server.
  void _scheduleRetryIfNeeded() {
    _retryTimer?.cancel();
    final next = queue.pending();
    if (next.isEmpty || !_online) return;
    final wait = next.first.retryAfter;
    if (wait == Duration.zero) return;
    _retryTimer = Timer(wait, nudge);
  }

  void _setPhase(SyncPhase p) {
    if (_phase == p) return;
    _phase = p;
    notifyListeners();
  }

  /// Postgres codes translated into something a person can act on. Never the
  /// raw code, and never the forbidden vocabulary.
  static String _humanise(PostgrestException e) => switch (e.code) {
        '42501' =>
          'The server would not accept that change. Signing out and back in '
              'usually clears it.',
        '23503' =>
          'That change refers to something the server does not have yet. It '
              'will go through once the earlier ones do.',
        _ => 'The server did not accept that change just yet.',
      };

  @override
  void dispose() {
    _connSub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
