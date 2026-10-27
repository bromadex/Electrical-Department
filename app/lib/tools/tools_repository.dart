import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// Condition of a tool, as stored in `tools.condition`.
enum ToolCondition {
  good('Good'),
  needsRepair('Needs repair'),
  damaged('Damaged'),
  lost('Lost');

  const ToolCondition(this.label);

  final String label;

  String get value => switch (this) {
    needsRepair => 'needs_repair',
    _ => name,
  };

  static ToolCondition parse(String v) =>
      values.firstWhere((c) => c.value == v, orElse: () => ToolCondition.good);
}

LocalTool toolFromRow(Map<String, dynamic> r) {
  DateTime? t(String k) =>
      r[k] == null ? null : DateTime.parse(r[k] as String).toLocal();
  return LocalTool(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    code: r['code'] as String?,
    name: r['name'] as String,
    kind: r['kind'] as String?,
    serialNo: r['serial_no'] as String?,
    condition: r['condition'] as String,
    calibrationDue: t('calibration_due'),
    notes: r['notes'] as String?,
    photoPath: r['photo_path'] as String?,
    holderId: r['holder_id'] as String?,
    holderName: r['holder_name'] as String?,
    formId: r['issue_form_id'] as String?,
    issuedAt: t('issued_at'),
    dueBack: t('due_back'),
    lastCountedAt: t('last_counted_at'),
    pending: false,
  );
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// A date with its year, e.g. "20 Oct 2027", for dates that may be in
/// another year (calibration, certificates).
String dayWithYear(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

/// Out with someone: an app user, or anyone on an issue form.
bool toolOut(LocalTool t) => t.holderId != null || t.holderName != null;

/// Who has it: their name in the app, else the name on the issue form.
String? toolHolder(LocalTool t, Map<String, String> people) =>
    people[t.holderId] ?? t.holderName;

bool toolOverdue(LocalTool t) =>
    toolOut(t) && t.dueBack != null && t.dueBack!.isBefore(_today());

/// Calibration has run out: the server will not let it go out.
bool calibrationExpired(LocalTool t) =>
    t.calibrationDue != null && t.calibrationDue!.isBefore(_today());

/// Calibration due within a week, or already past.
bool calibrationDue(LocalTool t) =>
    t.calibrationDue != null &&
    !t.calibrationDue!.isAfter(_today().add(const Duration(days: 7)));

/// Keeps the current site's tools register in drift. Reloads when the site
/// changes, when realtime says a tool changed, and after queued changes land.
final toolsSyncProvider = NotifierProvider<ToolsSyncNotifier, AppError?>(
  ToolsSyncNotifier.new,
);

class ToolsSyncNotifier extends Notifier<AppError?> {
  LocalDb get _db => ref.read(localDbProvider);
  SupabaseClient get _client => ref.read(supabaseProvider);
  String? _siteId;

  @override
  AppError? build() {
    final userId = ref.watch(authUserIdProvider);
    final site = ref.watch(currentSiteProvider.select((s) => s?.id));
    _siteId = site;
    if (userId == null || site == null) return null;
    final channel = _client
        .channel('tools:$site')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tools',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'site_id',
            value: site,
          ),
          callback: (_) => unawaited(refresh()),
        )
        .subscribe();
    ref.onDispose(() => _client.removeChannel(channel));
    Future.microtask(refresh);
    return null;
  }

  Future<void> refresh() async {
    final site = _siteId;
    if (site == null) return;
    try {
      final rows = await _client
          .from('tools')
          .select()
          .eq('site_id', site)
          .eq('is_archived', false)
          .order('code');
      if (!ref.mounted || _siteId != site) return;
      final pending = (await (_db.select(
        _db.localTools,
      )..where((t) => t.pending.equals(true))).get()).map((t) => t.id).toSet();
      await _db.transaction(() async {
        await (_db.delete(_db.localTools)
              ..where((t) => t.siteId.equals(site))
              ..where((t) => t.pending.equals(false)))
            .go();
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.localTools, [
            for (final r in rows)
              if (!pending.contains(r['id'])) toolFromRow(r),
          ]);
        });
      });
      state = null;
    } catch (e) {
      if (ref.mounted) state = AppError.from(e);
    }
  }

  Future<void> settle() async {
    await (_db.update(_db.localTools)..where((t) => t.pending.equals(true)))
        .write(const LocalToolsCompanion(pending: Value(false)));
    await refresh();
  }
}

/// Tools at the current site, from the device cache, by code.
final siteToolsProvider = StreamProvider<List<LocalTool>>((ref) {
  ref.watch(toolsSyncProvider.select((_) => null));
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return Stream.value(const []);
  final db = ref.watch(localDbProvider);
  return (db.select(db.localTools)
        ..where((t) => t.siteId.equals(site))
        ..orderBy([(t) => OrderingTerm(expression: t.code)]))
      .watch();
});

final toolProvider = StreamProvider.family<LocalTool?, String>((ref, id) {
  final db = ref.watch(localDbProvider);
  return (db.select(
    db.localTools,
  )..where((t) => t.id.equals(id))).watchSingleOrNull();
});

/// One time a tool went out (online; for the tool's history).
class ToolIssue {
  ToolIssue.fromJson(Map<String, dynamic> j)
    : issuedTo = j['issued_to'] as String?,
      formId = j['form_id'] as String?,
      formCode = (j['form'] as Map?)?['code'] as String?,
      recipientName = (j['form'] as Map?)?['recipient_name'] as String?,
      company = (j['form'] as Map?)?['company'] as String?,
      issueCondition = j['issue_condition'] as String?,
      issuedBy = j['issued_by'] as String?,
      issuedAt = DateTime.parse(j['issued_at'] as String).toLocal(),
      dueBack = j['due_back'] == null
          ? null
          : DateTime.parse(j['due_back'] as String),
      signaturePath = j['signature_path'] as String?,
      returnedAt = j['returned_at'] == null
          ? null
          : DateTime.parse(j['returned_at'] as String).toLocal(),
      returnCondition = j['return_condition'] as String?,
      returnNote = j['return_note'] as String?;

  final String? issuedTo;
  final String? formId;
  final String? formCode;
  final String? recipientName;
  final String? company;
  final String? issueCondition;
  final String? issuedBy;
  final DateTime issuedAt;
  final DateTime? dueBack;
  final String? signaturePath;
  final DateTime? returnedAt;
  final String? returnCondition;
  final String? returnNote;
}

final toolHistoryProvider = FutureProvider.autoDispose
    .family<List<ToolIssue>, String>((ref, toolId) async {
      // Reload when the tool is issued or returned, and once that change
      // has reached the server.
      ref.watch(
        toolProvider(toolId)
            .select((t) => (t.value?.holderId, t.value?.pending)),
      );
      final rows = await ref
          .watch(supabaseProvider)
          .from('tool_issues')
          .select('*, form:tool_issue_forms(code, recipient_name, company)')
          .eq('tool_id', toolId)
          .order('issued_at', ascending: false)
          .limit(50);
      return [for (final r in rows) ToolIssue.fromJson(r)];
    });

/// People who can hold tools at a site (online).
final toolPeopleProvider = FutureProvider.autoDispose
    .family<List<({String id, String name})>, String>((ref, siteId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_site_people',
            params: {'p_site': siteId, 'p_code': 'tools.view'},
          );
      return [
        for (final r in rows as List)
          (id: r['id'] as String, name: (r['full_name'] as String?) ?? ''),
      ];
    });

/// A signed URL for a file in tool-files (signatures and photos).
final toolFileUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) {
  return ref
      .watch(supabaseProvider)
      .storage
      .from('tool-files')
      .createSignedUrl(path, 3600);
});

final toolActionsProvider = Provider((ref) => ToolActions(ref));

/// Writes to the register. Each one updates the device first, then queues
/// the function call in the outbox, so it works offline.
class ToolActions {
  ToolActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  LocalDb get _db => _ref.read(localDbProvider);

  Future<String> save({
    LocalTool? tool,
    required String siteId,
    required String name,
    String? kind,
    String? serialNo,
    DateTime? calibrationDue,
    String? notes,
    ToolCondition condition = ToolCondition.good,
    bool archived = false,
    Uint8List? photo,
  }) async {
    final id = tool?.id ?? _uuid.v4();
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    String? photoPath;
    if (photo != null) {
      final fileId = _uuid.v4();
      photoPath = '$siteId/tool/$id/photo-$fileId.jpg';
      await _ref
          .read(outboxProvider)
          .enqueueUpload(
            id: fileId,
            bucket: 'tool-files',
            path: photoPath,
            bytes: photo,
          );
    }
    if (archived) {
      await (_db.delete(_db.localTools)..where((t) => t.id.equals(id))).go();
    } else {
      await _db
          .into(_db.localTools)
          .insertOnConflictUpdate(
            LocalTool(
              id: id,
              siteId: siteId,
              code: tool?.code,
              name: name.trim(),
              kind: clean(kind),
              serialNo: clean(serialNo),
              condition: condition.value,
              calibrationDue: calibrationDue,
              notes: clean(notes),
              photoPath: photoPath ?? tool?.photoPath,
              holderId: tool?.holderId,
              holderName: tool?.holderName,
              formId: tool?.formId,
              issuedAt: tool?.issuedAt,
              dueBack: tool?.dueBack,
              lastCountedAt: tool?.lastCountedAt,
              pending: true,
            ),
          );
    }
    await _queue('fn_save_tool', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_name': name.trim(),
      'p_kind': clean(kind),
      'p_serial_no': clean(serialNo),
      'p_calibration_due': calibrationDue == null
          ? null
          : _date(calibrationDue),
      'p_notes': clean(notes),
      'p_condition': condition.value,
      'p_archived': archived,
      'p_photo_path': photoPath,
    });
    return id;
  }

  /// Hands [tool] to [userId]; [signature] is the PNG they signed.
  Future<void> issue(
    LocalTool tool, {
    required String userId,
    DateTime? dueBack,
    required Uint8List signature,
  }) async {
    final id = _uuid.v4();
    final path = '${tool.siteId}/tool/${tool.id}/signature-$id.png';
    await _ref
        .read(outboxProvider)
        .enqueueUpload(
          id: id,
          bucket: 'tool-files',
          path: path,
          bytes: signature,
          contentType: 'image/png',
        );
    await _patch(
      tool.id,
      LocalToolsCompanion(
        holderId: Value(userId),
        issuedAt: Value(DateTime.now()),
        dueBack: Value(dueBack),
      ),
    );
    await _queue('fn_issue_tool', {
      'p_client_ref': id,
      'p_tool': tool.id,
      'p_to': userId,
      'p_due_back': dueBack == null ? null : _date(dueBack),
      'p_signature_path': path,
    }, clientRef: id);
  }

  Future<void> takeBack(
    LocalTool tool, {
    required ToolCondition condition,
    String? note,
  }) async {
    await _patch(
      tool.id,
      LocalToolsCompanion(
        holderId: const Value(null),
        holderName: const Value(null),
        formId: const Value(null),
        issuedAt: const Value(null),
        dueBack: const Value(null),
        condition: Value(condition.value),
      ),
    );
    await _queue('fn_return_tool', {
      'p_tool': tool.id,
      'p_condition': condition.value,
      'p_note': note?.trim(),
    });
  }

  /// Monthly count: the tools seen.
  Future<void> count(String siteId, List<String> toolIds) async {
    final now = DateTime.now();
    await (_db.update(_db.localTools)..where((t) => t.id.isIn(toolIds))).write(
      LocalToolsCompanion(
        lastCountedAt: Value(now),
        pending: const Value(true),
      ),
    );
    await _queue('fn_count_tools', {'p_site': siteId, 'p_tools': toolIds});
  }

  Future<void> patch(String id, LocalToolsCompanion change) =>
      _patch(id, change);

  /// Queues [action] and refreshes the register once it lands.
  Future<void> queue(
    String action,
    Map<String, dynamic> payload, {
    String? clientRef,
  }) => _queue(action, payload, clientRef: clientRef);

  Future<void> _patch(String id, LocalToolsCompanion change) {
    return (_db.update(_db.localTools)..where((t) => t.id.equals(id))).write(
      change.copyWith(pending: const Value(true)),
    );
  }

  Future<void> _queue(
    String action,
    Map<String, dynamic> payload, {
    String? clientRef,
  }) async {
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue(
      action,
      payload,
      clientRef: clientRef,
      flushNow: false,
    );
    unawaited(_flushAndSettle());
  }

  Future<void> _flushAndSettle() async {
    final outbox = _ref.read(outboxProvider);
    await outbox.flush();
    if (await outbox.isEmpty) {
      await _ref.read(toolsSyncProvider.notifier).settle();
    }
  }
}
