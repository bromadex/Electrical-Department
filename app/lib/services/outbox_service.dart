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

typedef UploadCall = Future<void> Function(
  String bucket,
  String path,
  Uint8List bytes,
  String contentType,
);

/// Queues uploads and function calls on the device and sends them when
/// Supabase is reachable: files first, then actions in the order they were
/// made. Each action is one function from API.md.
class OutboxService {
  OutboxService(this._db, this._rpc, [this._upload]);

  /// Allowed actions, and whether the outbox adds `p_client_ref` itself.
  /// Job card changes are not queued: they go straight to the server so its
  /// timestamps stay true (see jobcards/repository.dart).
  static const actions = <String, bool>{
    'fn_mark_read': false,
    'fn_register_device': false,
  };

  /// Entries that failed this many times stop retrying and keep their error.
  static const maxTries = 5;

  final LocalDb _db;
  final RpcCall _rpc;
  final UploadCall? _upload;
  Future<void>? _flushing;

  /// Saves the call and tries to send it straight away. Returns the
  /// client ref, which create functions use to avoid duplicates.
  Future<String> enqueue(
    String action,
    Map<String, dynamic> payload, {
    String? clientRef,
    bool flushNow = true,
  }) async {
    if (!actions.containsKey(action)) {
      throw ArgumentError.value(action, 'action', 'not an outbox action');
    }
    final ref = clientRef ?? const Uuid().v4();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientRef: ref,
            action: action,
            payload: jsonEncode(payload),
          ),
        );
    if (flushNow) unawaited(flush());
    return ref;
  }

  /// Saves a file to upload before the actions that refer to it.
  Future<void> enqueueUpload({
    required String id,
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) {
    return _db
        .into(_db.pendingUploads)
        .insert(
          PendingUploadsCompanion.insert(
            id: id,
            bucket: bucket,
            path: path,
            bytes: bytes,
            contentType: contentType,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Number of uploads and actions still waiting to be sent.
  Stream<int> watchPending() {
    final count = _db.outbox.clientRef.count();
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([count])
      ..where(_db.outbox.tries.isSmallerThanValue(maxTries));
    final uploads = _db.pendingUploads.id.count();
    final uq = _db.selectOnly(_db.pendingUploads)
      ..addColumns([uploads])
      ..where(_db.pendingUploads.tries.isSmallerThanValue(maxTries));
    final a = query.map((row) => row.read(count) ?? 0).watchSingle();
    final b = uq.map((row) => row.read(uploads) ?? 0).watchSingle();
    return _combine(a, b);
  }

  /// Pending actions (for showing optimistic comments and the like).
  Stream<List<OutboxEntry>> watchActions(String action) {
    return (_db.select(_db.outbox)
          ..where((o) => o.action.equals(action))
          ..where((o) => o.tries.isSmallerThanValue(maxTries)))
        .watch();
  }

  /// Uploads not yet sent (for showing local photos before they upload).
  Stream<List<PendingUpload>> watchUploads(String pathPrefix) {
    return (_db.select(
      _db.pendingUploads,
    )..where((u) => u.path.like('$pathPrefix%'))).watch();
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

  /// Sends waiting uploads and entries oldest first. Stops at the first
  /// network error so later actions never overtake earlier ones.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() {
    _flushing = null;
  });

  /// Completes when nothing is waiting (or sending has stopped on an error).
  Future<bool> get isEmpty async {
    final a = await (_db.select(
      _db.outbox,
    )..where((o) => o.tries.isSmallerThanValue(maxTries))).get();
    final b = await _db.select(_db.pendingUploads).get();
    return a.isEmpty && b.isEmpty;
  }

  Future<void> _flush() async {
    if (_upload != null) {
      final uploads =
          await (_db.select(_db.pendingUploads)
                ..where((u) => u.tries.isSmallerThanValue(maxTries))
                ..orderBy([
                  (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
                ]))
              .get();
      for (final u in uploads) {
        try {
          await _upload(u.bucket, u.path, u.bytes, u.contentType);
          await (_db.delete(
            _db.pendingUploads,
          )..where((x) => x.id.equals(u.id))).go();
        } catch (e) {
          final error = AppError.from(e);
          await (_db.update(
            _db.pendingUploads,
          )..where((x) => x.id.equals(u.id))).write(
            PendingUploadsCompanion(
              tries: Value(error.isRetryable ? u.tries + 1 : maxTries),
              lastError: Value(error.toString()),
            ),
          );
          return;
        }
      }
    }

    final pending =
        await (_db.select(_db.outbox)
              ..where((o) => o.tries.isSmallerThanValue(maxTries))
              ..orderBy([
                (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
              ]))
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

  static Stream<int> _combine(Stream<int> a, Stream<int> b) {
    late StreamController<int> c;
    var va = 0, vb = 0;
    StreamSubscription<int>? sa, sb;
    c = StreamController<int>(
      onListen: () {
        sa = a.listen((v) {
          va = v;
          c.add(va + vb);
        }, onError: c.addError);
        sb = b.listen((v) {
          vb = v;
          c.add(va + vb);
        }, onError: c.addError);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return c.stream;
  }
}
