import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import 'tools_repository.dart';

/// The paper tool issue form in the app (API.md section 11b): several
/// tools to one person, who may be someone outside the app, with three
/// signatures going out and three coming back.

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One tool on a form.
class IssueFormLine {
  IssueFormLine.fromJson(Map<String, dynamic> j)
    : toolId = j['tool_id'] as String,
      code = (j['tool'] as Map?)?['code'] as String?,
      name = (j['tool'] as Map?)?['name'] as String? ?? 'Tool',
      serialNo = (j['tool'] as Map?)?['serial_no'] as String?,
      qty = (j['qty'] as num?)?.toInt() ?? 1,
      issueCondition = j['issue_condition'] as String?,
      returnedAt = _date(j['returned_at']),
      returnCondition = j['return_condition'] as String?,
      returnNote = j['return_note'] as String?;

  final String toolId;
  final String? code;
  final String name;
  final String? serialNo;
  final int qty;
  final String? issueCondition;
  final DateTime? returnedAt;
  final String? returnCondition;
  final String? returnNote;

  bool get back => returnedAt != null;
}

class IssueForm {
  IssueForm.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      issuedBy = j['issued_by'] as String?,
      issuedAt = _date(j['issued_at'])!,
      recipientId = j['recipient_id'] as String?,
      recipientName = j['recipient_name'] as String,
      recipientRole = j['recipient_role'] as String?,
      company = j['company'] as String?,
      teamLead = j['team_lead'] as String?,
      location = j['location'] as String?,
      jobCardId = j['job_card_id'] as String?,
      jobCardNumber = (j['job_card'] as Map?)?['number'] as String?,
      dueBack = j['due_back'] == null
          ? null
          : DateTime.parse(j['due_back'] as String),
      remarks = j['remarks'] as String?,
      issuerSignature = j['issuer_signature'] as String?,
      recipientSignature = j['recipient_signature'] as String?,
      leadSignature = j['lead_signature'] as String?,
      status = j['status'] as String,
      returnedAt = _date(j['returned_at']),
      receivedBackBy = j['received_back_by'] as String?,
      returnIssuerSignature = j['return_issuer_signature'] as String?,
      returnRecipientSignature = j['return_recipient_signature'] as String?,
      returnLeadSignature = j['return_lead_signature'] as String?,
      returnRemarks = j['return_remarks'] as String?,
      lines = [
        for (final l in (j['lines'] as List? ?? const []))
          IssueFormLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ]..sort((a, b) => (a.code ?? '').compareTo(b.code ?? ''));

  final String id;
  final String siteId;
  final String code;
  final String? issuedBy;
  final DateTime issuedAt;
  final String? recipientId;
  final String recipientName;
  final String? recipientRole;
  final String? company;
  final String? teamLead;
  final String? location;
  final String? jobCardId;
  final String? jobCardNumber;
  final DateTime? dueBack;
  final String? remarks;
  final String? issuerSignature;
  final String? recipientSignature;
  final String? leadSignature;

  /// out | part_returned | returned
  final String status;
  final DateTime? returnedAt;
  final String? receivedBackBy;
  final String? returnIssuerSignature;
  final String? returnRecipientSignature;
  final String? returnLeadSignature;
  final String? returnRemarks;
  final List<IssueFormLine> lines;

  bool get returned => status == 'returned';
  int get out => lines.where((l) => !l.back).length;
  bool get overdue {
    final n = DateTime.now();
    return !returned &&
        dueBack != null &&
        dueBack!.isBefore(DateTime(n.year, n.month, n.day));
  }
}

const _formSelect =
    '*, job_card:job_cards(number), '
    'lines:tool_issues(tool_id, qty, issue_condition, returned_at, '
    'return_condition, return_note, tool:tools(code, name, serial_no))';

/// The current site's forms, newest first, kept live (online).
final issueFormsProvider = StreamProvider.autoDispose<List<IssueForm>>((
  ref,
) async* {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) {
    yield const [];
    return;
  }
  final client = ref.watch(supabaseProvider);
  Future<List<IssueForm>> load() async {
    final rows = await client
        .from('tool_issue_forms')
        .select(_formSelect)
        .eq('site_id', site)
        .order('issued_at', ascending: false)
        .limit(200);
    return [for (final r in rows) IssueForm.fromJson(r)];
  }

  final changes = StreamController<void>();
  final channel = client
      .channel('tool-forms:$site')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tool_issue_forms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'site_id',
          value: site,
        ),
        callback: (_) => changes.add(null),
      )
      .subscribe();
  ref.onDispose(() {
    client.removeChannel(channel);
    changes.close();
  });
  // Also reload when the tools register changes (a tool came back).
  ref.listen(siteToolsProvider, (_, _) => changes.add(null));
  yield await load();
  await for (final _ in changes.stream) {
    yield await load();
  }
});

/// One form with its tools (online).
final issueFormProvider = FutureProvider.autoDispose.family<IssueForm?, String>(
  (ref, id) async {
    // Reload when one of its tools changes on the device or the server.
    ref.watch(
      siteToolsProvider.select(
        (v) => [
          for (final t in v.value ?? const <LocalTool>[])
            if (t.formId == id) '${t.id}${t.pending}',
        ].join(),
      ),
    );
    final row = await ref
        .watch(supabaseProvider)
        .from('tool_issue_forms')
        .select(_formSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : IssueForm.fromJson(row);
  },
);

/// Job cards a tool was used on (online), newest first.
final toolJobCardsProvider = FutureProvider.autoDispose
    .family<
      List<({String id, String number, String title, String status})>,
      String
    >((ref, toolId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_card_tools')
          .select('linked_at, job_card:job_cards(id, number, title, status)')
          .eq('tool_id', toolId)
          .order('linked_at', ascending: false)
          .limit(100);
      return [
        for (final r in rows)
          if (r['job_card'] case final Map j)
            (
              id: j['id'] as String,
              number: j['number'] as String,
              title: j['title'] as String? ?? '',
              status: j['status'] as String? ?? '',
            ),
      ];
    });

/// Tools on a job card (online).
final jobCardToolsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, jobCardId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_card_tools')
          .select('tool_id')
          .eq('job_card_id', jobCardId);
      return [for (final r in rows) r['tool_id'] as String];
    });

/// One tool going out on a new form.
typedef IssueLine = ({LocalTool tool, int qty, ToolCondition condition});

/// One tool coming back.
typedef ReturnLine = ({String toolId, ToolCondition condition, String? note});

/// The three people who sign a form, each way.
typedef FormSignatures = ({
  Uint8List? issuer,
  Uint8List? recipient,
  Uint8List? lead,
});

final issueFormActionsProvider = Provider((ref) => IssueFormActions(ref));

/// Writes for forms. The device's register changes first; the calls and
/// signatures wait in the outbox when there is no signal.
class IssueFormActions {
  IssueFormActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  ToolActions get _tools => _ref.read(toolActionsProvider);

  /// Queues the signature PNGs; returns their storage paths.
  Future<Map<String, String>> _signatures(
    String siteId,
    String formId,
    String stage,
    FormSignatures s,
  ) async {
    final paths = <String, String>{};
    for (final (key, png) in [
      ('issuer', s.issuer),
      ('recipient', s.recipient),
      ('lead', s.lead),
    ]) {
      if (png == null) continue;
      final id = _uuid.v4();
      final path = '$siteId/form/$formId/$stage-$key-$id.png';
      await _ref
          .read(outboxProvider)
          .enqueueUpload(
            id: id,
            bucket: 'tool-files',
            path: path,
            bytes: png,
            contentType: 'image/png',
          );
      paths[key] = path;
    }
    return paths;
  }

  /// Issues [lines] on a new form; returns its id.
  Future<String> issue({
    required String siteId,
    required List<IssueLine> lines,
    String? userId,
    required String name,
    String? role,
    String? company,
    String? teamLead,
    String? location,
    String? jobCardId,
    DateTime? dueBack,
    String? remarks,
    required FormSignatures signatures,
  }) async {
    final id = _uuid.v4();
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final paths = await _signatures(siteId, id, 'issue', signatures);
    final now = DateTime.now();
    for (final l in lines) {
      await _tools.patch(
        l.tool.id,
        LocalToolsCompanion(
          holderId: Value(userId),
          holderName: Value(name.trim()),
          formId: Value(id),
          issuedAt: Value(now),
          dueBack: Value(dueBack),
          condition: Value(l.condition.value),
        ),
      );
    }
    await _tools.queue('fn_issue_tools', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_items': [
        for (final l in lines)
          {'tool_id': l.tool.id, 'qty': l.qty, 'condition': l.condition.value},
      ],
      'p_to': userId,
      'p_name': name.trim(),
      'p_role': clean(role),
      'p_company': clean(company),
      'p_team_lead': clean(teamLead),
      'p_location': clean(location),
      'p_due_back': dueBack == null ? null : _day(dueBack),
      'p_remarks': clean(remarks),
      'p_signatures': paths,
      'p_job_card': jobCardId,
    }, clientRef: id);
    return id;
  }

  /// Takes back [lines] from [form].
  Future<void> takeBack(
    IssueForm form, {
    required List<ReturnLine> lines,
    required FormSignatures signatures,
    String? remarks,
  }) async {
    final paths = await _signatures(
      form.siteId,
      form.id,
      'return-${_uuid.v4().substring(0, 8)}',
      signatures,
    );
    for (final l in lines) {
      await _tools.patch(
        l.toolId,
        LocalToolsCompanion(
          holderId: const Value(null),
          holderName: const Value(null),
          formId: const Value(null),
          issuedAt: const Value(null),
          dueBack: const Value(null),
          condition: Value(l.condition.value),
        ),
      );
    }
    await _tools.queue('fn_return_tools', {
      'p_form': form.id,
      'p_items': [
        for (final l in lines)
          {
            'tool_id': l.toolId,
            'condition': l.condition.value,
            'note': l.note?.trim(),
          },
      ],
      'p_signatures': paths,
      'p_remarks': remarks?.trim(),
    });
  }

  /// Adds or removes a tool on a job card.
  Future<void> linkToJobCard(
    String jobCardId,
    String toolId, {
    required bool linked,
  }) async {
    await _ref.read(outboxProvider).enqueue('fn_link_job_card_tool', {
      'p_job_card': jobCardId,
      'p_tool': toolId,
      'p_linked': linked,
    });
    _ref.invalidate(jobCardToolsProvider(jobCardId));
    _ref.invalidate(toolJobCardsProvider(toolId));
  }
}
