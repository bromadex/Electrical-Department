import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';

typedef RpcCall = Future<dynamic> Function(
  String function,
  Map<String, dynamic> params,
);

/// Queues function calls on the device and sends them when Supabase is
/// reachable. Each action is one function from API.md.
class OutboxService {
  OutboxService(this._db, this._rpc);

  /// Allowed actions, and whether the function takes `p_client_ref`.
  static const actions = <String, bool>{
    'fn_mark_read': false,
    'fn_register_device': false,
  };

  /// Entries that failed this many times stop retrying and keep their error.
  static const maxTries = 5;

  final LocalDb _db;
  final RpcCall _rpc;
  Future<void>? _flushing;

  /// Saves the call and tries to send it straight away. Returns the
  /// client ref, which create functions use to avoid duplicates.
  Future<String> enqueue(String action, Map<String, dynamic> payload) async {
    if (!actions.containsKey(action)) {
      throw ArgumentError.value(action, 'action', 'not an outbox action');
    }
    final ref = const Uuid().v4();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientRef: ref,
            action: action,
            payload: jsonEncode(payload),
          ),
        );
    unawaited(flush());
    return ref;
  }

  /// Number of entries still waiting to be sent.
  Stream<int> watchPending() {
    final count = _db.outbox.clientRef.count();
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([count])
      ..where(_db.outbox.tries.isSmallerThanValue(maxTries));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Entries that gave up, with their last error.
  Stream<List<OutboxEntry>> watchFailed() {
    return (_db.select(
      _db.outbox,
    )..where((o) => o.tries.isBiggerOrEqualValue(maxTries))).watch();
  }

  Future<void> dismiss(String clientRef) {
    return (_db.delete(
      _db.outbox,
    )..where((o) => o.clientRef.equals(clientRef))).go();
  }

  /// Sends waiting entries oldest first. Stops at the first network error.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() {
    _flushing = null;
  });

  Future<void> _flush() async {
    final pending =
        await (_db.select(_db.outbox)
              ..where((o) => o.tries.isSmallerThanValue(maxTries))
              ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
            .get();

    for (final entry in pending) {
      final params = Map<String, dynamic>.from(
        jsonDecode(entry.payload) as Map,
      );
      if (actions[entry.action] ?? false) {
        params['p_client_ref'] = entry.clientRef;
      }

      try {
        await _rpc(entry.action, params);
        await dismiss(entry.clientRef);
      } catch (e) {
        final error = AppError.from(e);
        await (_db.update(
          _db.outbox,
        )..where((o) => o.clientRef.equals(entry.clientRef))).write(
          OutboxCompanion(
            tries: Value(error.isRetryable ? entry.tries + 1 : maxTries),
            lastError: Value(error.toString()),
          ),
        );
        if (error.isRetryable) return;
      }
    }
  }
}
