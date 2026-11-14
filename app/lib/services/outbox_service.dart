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
  /// Create functions whose id the app needs straight away (jobs, photos,
  /// comments) get `p_client_ref` from the caller instead.
  static const actions = <String, bool>{
    'fn_mark_read': false,
    'fn_register_device': false,
    'fn_save_recurrence': false,
    'fn_save_asset': false,
    'fn_save_tool': false,
    'fn_issue_tool': false,
    'fn_return_tool': false,
    'fn_count_tools': false,
    'fn_issue_tools': false,
    'fn_return_tools': false,
    'fn_link_job_card_tool': false,
    'fn_add_tool_certificate': false,
    'fn_create_reminder': false,
    'fn_cancel_reminder': false,
    'fn_save_document': false,
    'fn_add_document_version': false,
    'fn_acknowledge_document': false,
    'fn_link_job_card_document': false,
    'fn_save_folder': false,
    'fn_move_documents': false,
    'fn_save_item': false,
    'fn_receive_stock': false,
    'fn_issue_stock': false,
    'fn_return_stock': false,
    'fn_adjust_stock': false,
    'fn_submit_count': false,
    'fn_save_project': false,
    'fn_set_roster': false,
    'fn_create_mr': false,
    'fn_save_checklist_template': false,
    'fn_submit_checklist': false,
    'fn_add_report_update': false,
    'fn_record_safety_check': false,
    'fn_create_request': false,
    'fn_send_message': false,
    // Job cards: notes, work-log entries and files (status and time
    // changes are never queued, so the server's timestamps stay true).
    'fn_comment_job_card': false,
    'fn_add_work_record': false,
    'fn_add_job_attachment': false,
    'fn_react': false,
    'fn_unsend_message': false,
    'fn_mark_conversation_read': false,
  };

  /// Entries the server failed this many times stop retrying and keep their
  /// error. No signal never counts: those wait and retry, however long.
  static const maxTries = 5;

  /// After a failure for lack of signal, sending waits this long, doubling
  /// each time up to [maxBackoff], so a phone out of signal is not kept busy.
  static const firstBackoff = Duration(seconds: 30);
  static const maxBackoff = Duration(minutes: 10);

  DateTime? _waitUntil;
  int _offlineFailures = 0;

  /// The current wait after failures for lack of signal (for tests and the
  /// outbox screen); null when sending is not held back.
  DateTime? get waitUntil => _waitUntil;

  void _offline() {
    _offlineFailures++;
    var wait = firstBackoff * (1 << (_offlineFailures - 1).clamp(0, 10));
    if (wait > maxBackoff) wait = maxBackoff;
    _waitUntil = DateTime.now().add(wait);
  }

  void _online() {
    _offlineFailures = 0;
    _waitUntil = null;
    // Kept on the device so "Last sent" survives a restart; not awaited, a
    // missed write only shows an older time.
    unawaited(
      _db
          .saveJson(lastSentKey, DateTime.now().toIso8601String())
          .catchError((_) {}),
    );
  }

  static const lastSentKey = 'outbox_last_sent';

  /// When something last reached the server from this device, and how long
  /// the oldest unsent change or file has waited (issue #36): a technician
  /// should never think something reached the office when it is still only
  /// on the phone.
  Future<({DateTime? lastSent, DateTime? oldestWaiting})> syncStatus() async {
    final last = DateTime.tryParse(await _db.readJson(lastSentKey) ?? '');
    final a =
        await (_db.select(_db.outbox)
              ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final b =
        await (_db.select(_db.pendingUploads)
              ..orderBy([(u) => OrderingTerm.asc(u.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final oldest = <DateTime>[
      if (a != null) a.createdAt,
      if (b != null) b.createdAt,
    ]..sort();
    return (lastSent: last, oldestWaiting: oldest.firstOrNull);
  }

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

  /// Files waiting to upload may take up this much of the phone; beyond it
  /// new files are refused until some have sent.
  static const maxPendingBytes = 300 * 1024 * 1024;

  /// Saves a file to upload before the actions that refer to it.
  Future<void> enqueueUpload({
    required String id,
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final size = _db.pendingUploads.bytes.length.sum();
    final waiting = await (_db.selectOnly(
      _db.pendingUploads,
    )..addColumns([size])).map((r) => r.read(size) ?? 0).getSingle();
    if (waiting + bytes.length > maxPendingBytes) {
      throw const AppError(
        'INVALID',
        'Too many files are waiting for signal on this phone (300 MB). '
            'Send them first, then add more.',
      );
    }
    await _db
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
  /// network error so later actions never overtake earlier ones. After a
  /// failure for lack of signal it waits (see [firstBackoff]) unless [force]
  /// (someone tapped "Send now").
  Future<void> flush({bool force = false}) {
    if (!force && _waitUntil != null && DateTime.now().isBefore(_waitUntil!)) {
      return _flushing ?? Future.value();
    }
    return _flushing ??= _flush().whenComplete(() {
      _flushing = null;
    });
  }

  /// Entries and uploads that gave up for lack of signal (before signal
  /// stopped counting as a failure) go back in the queue. Run at start-up.
  Future<int> reviveOfflineFailures() async {
    final a =
        await (_db.update(_db.outbox)
              ..where((o) => o.tries.isBiggerOrEqualValue(maxTries))
              ..where((o) => o.lastError.like('${AppError.network}%')))
            .write(const OutboxCompanion(tries: Value(0)));
    final b =
        await (_db.update(_db.pendingUploads)
              ..where((u) => u.tries.isBiggerOrEqualValue(maxTries))
              ..where((u) => u.lastError.like('${AppError.network}%')))
            .write(const PendingUploadsCompanion(tries: Value(0)));
    return a + b;
  }

  /// Tries a failed entry again.
  Future<void> retry(String clientRef) async {
    await (_db.update(_db.outbox)..where((o) => o.clientRef.equals(clientRef)))
        .write(const OutboxCompanion(tries: Value(0)));
    await flush(force: true);
  }

  /// Every action waiting or failed, oldest first.
  Stream<List<OutboxEntry>> watchAll() {
    return (_db.select(_db.outbox)..orderBy([
          (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
        ]))
        .watch();
  }

  /// Uploads waiting or failed, without their bytes: id, path, size, tries
  /// and last error.
  Stream<List<({String id, String path, int size, int tries, String? error})>>
  watchAllUploads() {
    final size = _db.pendingUploads.bytes.length;
    final q = _db.selectOnly(_db.pendingUploads)
      ..addColumns([
        _db.pendingUploads.id,
        _db.pendingUploads.path,
        size,
        _db.pendingUploads.tries,
        _db.pendingUploads.lastError,
      ]);
    return q
        .map(
          (r) => (
            id: r.read(_db.pendingUploads.id)!,
            path: r.read(_db.pendingUploads.path)!,
            size: r.read(size) ?? 0,
            tries: r.read(_db.pendingUploads.tries) ?? 0,
            error: r.read(_db.pendingUploads.lastError),
          ),
        )
        .watch();
  }

  Future<void> retryUpload(String id) async {
    await (_db.update(_db.pendingUploads)..where((u) => u.id.equals(id))).write(
      const PendingUploadsCompanion(tries: Value(0)),
    );
    await flush(force: true);
  }

  /// Drops a file and the changes that refer to it (they would point at a
  /// file that does not exist). Returns how many changes went with it.
  Future<int> discardUpload(String id) {
    return _db.transaction(() async {
      final u = await (_db.select(
        _db.pendingUploads,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (u == null) return 0;
      await (_db.delete(
        _db.pendingUploads,
      )..where((x) => x.id.equals(id))).go();
      return (_db.delete(
        _db.outbox,
      )..where((o) => o.payload.contains(u.path))).go();
    });
  }

  /// Everything still only on this device: changes and files, waiting or
  /// refused. Signing out must not wipe these unnoticed.
  Future<int> unsentCount() async {
    final a = await _db.select(_db.outbox).get();
    final b = await _db.select(_db.pendingUploads).get();
    return a.length + b.length;
  }

  /// Deletes every unsent change and file (someone chose to sign out and
  /// lose them).
  Future<void> discardAll() => _db.transaction(() async {
    await _db.delete(_db.outbox).go();
    await _db.delete(_db.pendingUploads).go();
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
          _online();
        } catch (e) {
          final error = AppError.from(e);
          await (_db.update(
            _db.pendingUploads,
          )..where((x) => x.id.equals(u.id))).write(
            PendingUploadsCompanion(
              // No signal does not use up a try; the rest of the queue waits.
              tries: Value(error.isRetryable ? u.tries : maxTries),
              lastError: Value(error.toString()),
            ),
          );
          // No signal: everything waits. A refused file is set aside (the
          // changes naming it are held below); the other files still go.
          if (error.isRetryable) {
            _offline();
            return;
          }
        }
      }
    }

    // Files the server refused for good: a change that refers to one waits
    // (and everything after it, to keep the order) until the file is tried
    // again or discarded, so no record points at a file that is not there.
    final refused = [
      for (final u in await (_db.select(
        _db.pendingUploads,
      )..where((u) => u.tries.isBiggerOrEqualValue(maxTries))).get())
        u.path,
    ];

    final pending =
        await (_db.select(_db.outbox)
              ..where((o) => o.tries.isSmallerThanValue(maxTries))
              ..orderBy([
                (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
              ]))
            .get();

    for (final entry in pending) {
      final file = heldBy(entry.payload, refused);
      if (file != null) {
        await (_db.update(
          _db.outbox,
        )..where((o) => o.clientRef.equals(entry.clientRef))).write(
          OutboxCompanion(
            lastError: Value(
              'Waiting for its file ${file.split('/').last}, which could '
              'not be uploaded: try the file again or discard it',
            ),
          ),
        );
        return;
      }
      final params = Map<String, dynamic>.from(
        jsonDecode(entry.payload) as Map,
      );
      if (actions[entry.action] ?? false) {
        params['p_client_ref'] = entry.clientRef;
      }

      try {
        await _rpc(entry.action, params);
        await dismiss(entry.clientRef);
        _online();
      } catch (e) {
        final error = AppError.from(e);
        await (_db.update(
          _db.outbox,
        )..where((o) => o.clientRef.equals(entry.clientRef))).write(
          OutboxCompanion(
            // No signal does not use up a try: it waits and retries.
            tries: Value(error.isRetryable ? entry.tries : maxTries),
            lastError: Value(error.toString()),
          ),
        );
        if (error.isRetryable) {
          _offline();
          return;
        }
      }
    }
  }

  /// The refused file a change's payload refers to, if any.
  static String? heldBy(String payload, List<String> refusedPaths) {
    for (final p in refusedPaths) {
      if (payload.contains(p)) return p;
    }
    return null;
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
