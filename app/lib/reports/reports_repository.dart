import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

String reportDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The day's report at a site (API.md section 13).
class DailyReport {
  DailyReport.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      date = DateTime.parse(j['report_date'] as String),
      summary = Map<String, dynamic>.from(j['summary'] as Map? ?? const {}),
      status = j['status'] as String,
      comment = j['supervisor_comment'] as String?,
      approvedBy = j['approved_by'] as String?,
      approvedAt = j['approved_at'] == null
          ? null
          : DateTime.parse(j['approved_at'] as String).toLocal();

  final String id;
  final String siteId;
  final String code;
  final DateTime date;
  final Map<String, dynamic> summary;
  final String status;
  final String? comment;
  final String? approvedBy;
  final DateTime? approvedAt;

  bool get approved => status == 'approved';

  List<Map<String, dynamic>> list(String key) => [
    for (final e in (summary[key] as List? ?? const []))
      if (e is Map) Map<String, dynamic>.from(e),
  ];

  List<String> names(String key) => [
    for (final e in (summary[key] as List? ?? const [])) '$e',
  ];

  int count(String key) => (summary[key] as num?)?.toInt() ?? 0;
}

class ReportUpdate {
  ReportUpdate.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      userId = j['user_id'] as String,
      body = j['body'] as String,
      photoPaths = [
        for (final p in (j['photo_paths'] as List? ?? const [])) '$p',
      ],
      createdAt = DateTime.parse(j['created_at'] as String).toLocal();

  final String id;
  final String userId;
  final String body;
  final List<String> photoPaths;
  final DateTime createdAt;
}

typedef ReportDay = ({DailyReport report, List<ReportUpdate> updates});

/// Builds (or refreshes) the day's report at the current site, with the
/// updates people added. Online: reports need the server's figures.
final dailyReportProvider = FutureProvider.autoDispose
    .family<ReportDay?, String>((ref, date) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      if (site == null) return null;
      final db = ref.watch(supabaseProvider);
      final row = await db.rpc(
        'fn_build_daily_report',
        params: {'p_site': site, 'p_date': date},
      );
      final report = DailyReport.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      final rows = await db
          .from('report_updates')
          .select()
          .eq('report_id', report.id)
          .eq('is_archived', false)
          .order('created_at');
      return (
        report: report,
        updates: [for (final r in rows) ReportUpdate.fromJson(r)],
      );
    });

/// Totals of the stored daily reports between two dates (inclusive), for
/// the week and month views.
class ReportTotals {
  int days = 0;
  int jobsOpened = 0;
  int jobsClosed = 0;
  int roundsDone = 0;
  int roundsMissed = 0;
  int toolsIssued = 0;
  int approved = 0;
}

final reportTotalsProvider = FutureProvider.autoDispose
    .family<ReportTotals, ({String from, String to})>((ref, range) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      final t = ReportTotals();
      if (site == null) return t;
      final rows = await ref
          .watch(supabaseProvider)
          .from('daily_reports')
          .select()
          .eq('site_id', site)
          .gte('report_date', range.from)
          .lte('report_date', range.to);
      for (final r in rows) {
        final d = DailyReport.fromJson(r);
        t.days++;
        t.jobsOpened += d.list('jobs_opened').length;
        t.jobsClosed += d.list('jobs_closed').length;
        t.roundsDone += d.list('checklists_done').length;
        t.roundsMissed += d.names('checklists_missed').length;
        t.toolsIssued += d.count('tools_issued');
        if (d.approved) t.approved++;
      }
      return t;
    });

final reportActionsProvider = Provider((ref) => ReportActions(ref));

class ReportActions {
  ReportActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  /// "Today's update" with photos; queued, so it works offline.
  Future<void> addUpdate({
    required String siteId,
    required String date,
    required String body,
    List<Uint8List> photos = const [],
  }) async {
    final outbox = _ref.read(outboxProvider);
    final id = _uuid.v4();
    final paths = <String>[];
    for (final bytes in photos) {
      final fileId = _uuid.v4();
      final path = '$siteId/report/$date/$fileId.jpg';
      await outbox.enqueueUpload(
        id: fileId,
        bucket: 'job-photos',
        path: path,
        bytes: bytes,
      );
      paths.add(path);
    }
    await outbox.enqueue(
      'fn_add_report_update',
      {
        'p_client_ref': id,
        'p_site': siteId,
        'p_date': date,
        'p_body': body.trim(),
        'p_photo_paths': paths,
      },
      clientRef: id,
      flushNow: false,
    );
    await outbox.flush();
    _ref.invalidate(dailyReportProvider(date));
  }

  Future<void> approve(DailyReport r, String comment) async {
    await _ref
        .read(supabaseProvider)
        .rpc(
          'fn_approve_report',
          params: {'p_report': r.id, 'p_comment': comment.trim()},
        );
    _ref.invalidate(dailyReportProvider(reportDate(r.date)));
  }
}
