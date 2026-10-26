import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_error.dart';
import '../../services/core_providers.dart';
import '../ui/format.dart';
import '../ui/media.dart';
import 'models.dart';

/// Ticks whenever a job card (or its assignments, comments, files) or a
/// request changes anywhere the user can see; lists, detail pages and the
/// dashboard watch it and reload.
final jobCardsLiveProvider = NotifierProvider<JobCardsLive, int>(
  JobCardsLive.new,
);

class JobCardsLive extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    final user = ref.watch(authUserIdProvider);
    if (user == null) return 0;
    final client = ref.read(supabaseProvider);
    var channel = client.channel('job-cards-live:$user');
    for (final table in const [
      'job_cards',
      'job_assignments',
      'job_comments',
      'job_attachments',
      'service_requests',
      'job_work_sessions',
      'job_waits',
      'job_work_records',
      'job_submissions',
      'job_reviews',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => bump(),
      );
    }
    channel.subscribe();
    ref.onDispose(() {
      _debounce?.cancel();
      unawaited(client.removeChannel(channel));
    });
    return 0;
  }

  /// Reload soon (several changes in a burst cause one reload).
  void bump() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (ref.mounted) state++;
    });
  }

  /// Reload now (after this device made a change).
  void bumpNow() {
    _debounce?.cancel();
    state++;
  }
}

String _cleanSearch(String s) =>
    s.replaceAll(RegExp(r'[,()*%\\.]'), ' ').trim();

/// Midnight today in the site time zone, as an ISO instant.
String _startOfToday() {
  final now = SiteTime.now();
  return SiteTime.toInstant(DateTime(now.year, now.month, now.day))
      .toIso8601String();
}

/// One page of the job card list.
final jobCardsPageProvider = FutureProvider.autoDispose
    .family<PagedResult<JobCard>, JobCardFilter>((ref, f) async {
      ref.watch(jobCardsLiveProvider);
      final client = ref.watch(supabaseProvider);
      var q = client.from('v_job_cards').select();
      if (f.siteId != null) q = q.eq('site_id', f.siteId!);
      q = switch (f.view) {
        JobCardView.all => q,
        JobCardView.open => q.not('status', 'in', '(closed,cancelled)'),
        JobCardView.newJobs => q.eq('is_new', true),
        JobCardView.clarification => q.eq('status', 'awaiting_clarification'),
        JobCardView.awaitingAssignment => q.eq('is_awaiting_assignment', true),
        JobCardView.active => q.eq('is_active', true),
        JobCardView.working => q.eq('is_working', true),
        JobCardView.waiting => q.eq('is_waiting', true),
        JobCardView.critical => q.eq('is_critical_open', true),
        JobCardView.overdue => q.eq('is_overdue', true),
        JobCardView.awaitingReview => q.eq('is_awaiting_review', true),
        JobCardView.outOfService =>
          q
              .eq('equipment_state', 'out_of_service')
              .not('status', 'in', '(closed,cancelled)'),
        JobCardView.closedToday =>
          q.eq('status', 'closed').gte('closed_at', _startOfToday()),
        JobCardView.closed => q.eq('status', 'closed'),
        JobCardView.cancelled => q.eq('status', 'cancelled'),
      };
      if (f.priorities.isNotEmpty) {
        q = q.inFilter('priority', f.priorities.toList());
      }
      if (f.responsibleId != null) q = q.eq('responsible_id', f.responsibleId!);
      if (f.assetId != null) q = q.eq('asset_id', f.assetId!);
      if (f.from != null) q = q.gte('received_at', f.from!.toIso8601String());
      if (f.to != null) q = q.lt('received_at', f.to!.toIso8601String());
      final s = _cleanSearch(f.search);
      if (s.isNotEmpty) {
        q = q.or(
          [
            for (final c in const [
              'number',
              'title',
              'description',
              'equipment_display',
              'asset_no_display',
              'reporter_name',
              'responsible_name',
              'area_name',
              'legacy_code',
            ])
              '$c.ilike.*$s*',
          ].join(','),
        );
      }
      final from = f.page * JobCardFilter.pageSize;
      final res = await q
          .order(f.sort, ascending: f.ascending)
          .order('received_at', ascending: false)
          .range(from, from + JobCardFilter.pageSize - 1)
          .count(CountOption.exact);
      return PagedResult([for (final r in res.data) JobCard(r)], res.count);
    });

/// One job card by id or by number (EL-JC-…).
final jobCardProvider = FutureProvider.autoDispose.family<JobCard, String>((
  ref,
  reference,
) async {
  ref.watch(jobCardsLiveProvider);
  final client = ref.watch(supabaseProvider);
  final byId = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(reference);
  final row = await client
      .from('v_job_cards')
      .select()
      .eq(byId ? 'id' : 'number', reference)
      .maybeSingle();
  if (row == null) {
    throw const AppError(
      'NOT_FOUND',
      'Job card not found, or you cannot see it.',
    );
  }
  return JobCard(row);
});

/// Assignments, comments, files (with signed URLs) and closures of a job card.
final jobCardExtrasProvider = FutureProvider.autoDispose
    .family<JobCardExtras, String>((ref, id) async {
      ref.watch(jobCardsLiveProvider);
      final client = ref.watch(supabaseProvider);
      // Joins name the foreign key column, not the constraint: the retired
      // jobs board's tables kept some of the constraint names.
      final results = await Future.wait<dynamic>([
        client
            .from('job_assignments')
            .select(
              '*, person:profiles!user_id(full_name), '
              'assigner:profiles!assigned_by(full_name)',
            )
            .eq('job_card_id', id)
            .order('assigned_at', ascending: true),
        client
            .from('job_comments')
            .select('*, author:profiles!author_id(full_name)')
            .eq('job_card_id', id)
            .eq('is_archived', false)
            .order('created_at', ascending: true),
        client
            .from('job_attachments')
            .select('*, uploader:profiles!uploaded_by(full_name)')
            .eq('job_card_id', id)
            .eq('is_archived', false)
            .order('created_at', ascending: true),
        client
            .from('job_closures')
            .select(
              '*, performer:profiles!performed_by(full_name), '
              'verifier:profiles!verified_by(full_name)',
            )
            .eq('job_card_id', id)
            .order('closed_at', ascending: true),
      ]);

      final files = [
        for (final r in results[2] as List) Map<String, dynamic>.from(r),
      ];
      final urls = <String, String>{};
      for (final bucket in {for (final f in files) f['bucket'] as String}) {
        final paths = [
          for (final f in files)
            if (f['bucket'] == bucket) f['path'] as String,
        ];
        try {
          final signed = await client.storage
              .from(bucket)
              .createSignedUrlsResult(paths, 3600);
          for (final s in signed.whereType<SignedUrlSuccess>()) {
            urls['$bucket/${s.path}'] = s.signedUrl;
          }
        } catch (_) {
          // Offline or not allowed: files are listed without previews.
        }
      }

      return JobCardExtras(
        assignments: [for (final r in results[0] as List) Assignment(r)],
        comments: [for (final r in results[1] as List) JobComment(r)],
        attachments: [
          for (final f in files)
            JobAttachment(f, urls['${f['bucket']}/${f['path']}']),
        ],
        closures: [for (final r in results[3] as List) JobClosure(r)],
      );
    });

final jobCardTimelineProvider = FutureProvider.autoDispose
    .family<List<TimelineEntry>, String>((ref, id) async {
      ref.watch(jobCardsLiveProvider);
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_job_card_timeline', params: {'p_job': id});
      return [
        for (final r in rows as List)
          TimelineEntry(Map<String, dynamic>.from(r)),
      ];
    });

final workloadProvider = FutureProvider.autoDispose
    .family<List<Workload>, String>((ref, siteId) async {
      ref.watch(jobCardsLiveProvider);
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_workload', params: {'p_site': siteId});
      return [
        for (final r in rows as List) Workload(Map<String, dynamic>.from(r)),
      ];
    });

final sitePeopleProvider = FutureProvider.autoDispose
    .family<List<Person>, String>((ref, siteId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_site_people', params: {'p_site': siteId});
      return [
        for (final r in rows as List)
          Person(r['id'] as String, r['full_name'] as String? ?? ''),
      ];
    });

/// Every change a user can make to job cards. Each call goes straight to
/// its database function (status and time changes are never queued offline,
/// so the server's timestamps stay true) and reloads what is on screen.
final jobCardActionsProvider = Provider<JobCardActions>(JobCardActions.new);

class JobCardActions {
  JobCardActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  SupabaseClient get _client => _ref.read(supabaseProvider);

  Future<Map<String, dynamic>> _call(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final res = await _client.rpc(fn, params: params);
      _ref.read(jobCardsLiveProvider.notifier).bumpNow();
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e) {
      throw AppError.from(e);
    }
  }

  static String? _text(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
  static String? _time(DateTime? t) => t?.toUtc().toIso8601String();

  /// Registers a job card (from a request when [requestId] is set) and
  /// uploads its files. Returns the new card's number.
  Future<String> register({
    String? requestId,
    required String siteId,
    String? areaId,
    String? location,
    DateTime? receivedAt,
    String? reporterName,
    String? departmentId,
    String? assetId,
    String? equipmentName,
    String? equipmentAssetNo,
    String? equipmentLocation,
    String? categoryId,
    String? title,
    String? description,
    String? impact,
    required String priority,
    DateTime? requestedCompletionAt,
    List<PickedFile> files = const [],
  }) async {
    final id = _uuid.v4();
    final row = await _call('fn_register_job_card', {
      'p_client_ref': id,
      'p_request': requestId,
      'p_site': siteId,
      'p_area': areaId,
      'p_location': _text(location),
      'p_received_at': _time(receivedAt),
      'p_reporter_name': _text(reporterName),
      'p_department': departmentId,
      'p_asset': assetId,
      'p_equipment_name': _text(equipmentName),
      'p_equipment_asset_no': _text(equipmentAssetNo),
      'p_equipment_location': _text(equipmentLocation),
      'p_category': categoryId,
      'p_title': _text(title),
      'p_description': _text(description),
      'p_impact': impact,
      'p_priority': priority,
      'p_requested_completion_at': _time(requestedCompletionAt),
    });
    if (files.isNotEmpty) {
      await addFiles(
        jobId: id,
        siteId: row['site_id'] as String? ?? siteId,
        files: files,
      );
    }
    return row['number'] as String;
  }

  Future<void> assess(
    String id, {
    required bool valid,
    String? maintenanceType,
    String? severity,
    String? safetyRisk,
    String? safetyNotes,
    String? equipmentState,
    String? competencies,
    int? personnel,
    String? resources,
    bool? isolation,
    bool? permit,
    bool? loto,
    num? durationHours,
    String? priority,
    DateTime? targetResponseAt,
    DateTime? targetCompletionAt,
    String? notes,
  }) => _call('fn_assess_job_card', {
    'p_job': id,
    'p_valid': valid,
    'p_maintenance_type': maintenanceType,
    'p_severity': severity,
    'p_safety_risk': safetyRisk,
    'p_safety_notes': _text(safetyNotes),
    'p_equipment_state': equipmentState,
    'p_competencies': _text(competencies),
    'p_personnel': personnel,
    'p_resources': _text(resources),
    'p_isolation': isolation,
    'p_permit': permit,
    'p_loto': loto,
    'p_duration_hours': durationHours,
    'p_priority': priority,
    'p_target_response_at': _time(targetResponseAt),
    'p_target_completion_at': _time(targetCompletionAt),
    'p_notes': _text(notes),
  });

  Future<void> returnForClarification(String id, String reason) =>
      _call('fn_return_for_clarification', {'p_job': id, 'p_reason': reason});

  Future<void> clarify(String id, String note) =>
      _call('fn_provide_clarification', {'p_job': id, 'p_note': note});

  Future<void> assign(
    String id, {
    required String responsibleId,
    List<String> supportIds = const [],
    DateTime? plannedStartAt,
    DateTime? targetCompletionAt,
    num? estimatedHours,
    String? materials,
    String? tools,
    String? safety,
    String? procedure,
    String? handoverNote,
    String? reason,
  }) => _call('fn_assign_job_card', {
    'p_job': id,
    'p_responsible': responsibleId,
    'p_support': supportIds,
    'p_planned_start_at': _time(plannedStartAt),
    'p_target_completion_at': _time(targetCompletionAt),
    'p_estimated_hours': estimatedHours,
    'p_materials': _text(materials),
    'p_tools': _text(tools),
    'p_safety': _text(safety),
    'p_procedure': _text(procedure),
    'p_handover_note': _text(handoverNote),
    'p_reason': _text(reason),
  });

  Future<void> unassign(String id, String reason) =>
      _call('fn_unassign_job_card', {'p_job': id, 'p_reason': reason});

  Future<void> accept(String id) => _call('fn_accept_job_card', {'p_job': id});

  /// in_progress, or one of the hold statuses with a reason.
  Future<void> setStatus(String id, String status, {String? reason}) => _call(
    'fn_set_job_card_status',
    {'p_job': id, 'p_status': status, 'p_reason': _text(reason)},
  );

  Future<void> escalate(
    String id, {
    required bool critical,
    required String reason,
  }) => _call('fn_escalate_job_card', {
    'p_job': id,
    'p_critical': critical,
    'p_reason': reason,
  });

  Future<void> submit(
    String id, {
    required String summary,
    required String findings,
    required String correctiveAction,
    required String equipmentStateAfter,
    required bool checksConfirmed,
  }) => _call('fn_submit_job_card', {
    'p_job': id,
    'p_summary': summary,
    'p_findings': findings,
    'p_corrective_action': correctiveAction,
    'p_equipment_state_after': equipmentStateAfter,
    'p_checks_confirmed': checksConfirmed,
  });

  /// 'approve' closes the job card; 'reject' returns it for more work.
  Future<void> review(String id, String decision, {String? notes}) => _call(
    'fn_review_job_card',
    {'p_job': id, 'p_decision': decision, 'p_notes': _text(notes)},
  );

  // --- Phase 2: work execution (API.md section 9) --------------------------

  /// Starts, resumes or joins the work; opens a work session for me.
  Future<void> startWork(String id) => _call('fn_start_work', {'p_job': id});

  /// A short pause (break, end_of_shift, other_job, other) stops my timer; a
  /// hold status stops everyone's and starts a wait.
  Future<void> pauseWork(
    String id,
    String reason, {
    String? note,
    bool countsTowardSla = true,
  }) => _call('fn_pause_work', {
    'p_job': id,
    'p_reason': reason,
    'p_note': _text(note),
    'p_counts_toward_sla': countsTowardSla,
  });

  Future<void> addWorkRecord(
    String id, {
    required String kind,
    String? body,
    List<Map<String, dynamic>> readings = const [],
  }) => _call('fn_add_work_record', {
    'p_client_ref': _uuid.v4(),
    'p_job': id,
    'p_kind': kind,
    'p_body': _text(body),
    'p_readings': readings,
  });

  /// [items]: {item_id, confirmed, reference, note}.
  Future<void> recordSafety(String id, List<Map<String, dynamic>> items) =>
      _call('fn_record_safety', {'p_job': id, 'p_items': items});

  Future<void> submitForReview(
    String id, {
    required String summary,
    required String findings,
    required String correctiveAction,
    required String equipmentStateAfter,
    String? functionalTests,
    String? electricalTests,
    String? materialsUsed,
    num? labourHours,
    String? outstandingDefects,
    String? recommendations,
    required bool checksConfirmed,
    required bool safetyConfirmed,
  }) => _call('fn_submit_for_review', {
    'p_job': id,
    'p_summary': summary,
    'p_findings': findings,
    'p_corrective_action': correctiveAction,
    'p_equipment_state_after': equipmentStateAfter,
    'p_functional_tests': _text(functionalTests),
    'p_electrical_tests': _text(electricalTests),
    'p_materials_used': _text(materialsUsed),
    'p_labour_hours': labourHours,
    'p_outstanding_defects': _text(outstandingDefects),
    'p_recommendations': _text(recommendations),
    'p_checks_confirmed': checksConfirmed,
    'p_safety_confirmed': safetyConfirmed,
  });

  /// approve (optionally raising a follow-up job card), reject or
  /// request_info.
  Future<void> verify(
    String id,
    String decision, {
    String? notes,
    String? followUpTitle,
    String? followUpDescription,
    String? followUpPriority,
  }) => _call('fn_verify_job_card', {
    'p_job': id,
    'p_decision': decision,
    'p_notes': _text(notes),
    'p_follow_up_title': _text(followUpTitle),
    'p_follow_up_description': _text(followUpDescription),
    'p_follow_up_priority': followUpPriority,
  });

  Future<void> answerReview(String id, String answer) =>
      _call('fn_answer_review', {'p_job': id, 'p_answer': answer});

  Future<void> correctSession(
    String sessionId, {
    required DateTime startedAt,
    DateTime? endedAt,
    required String reason,
  }) => _call('fn_correct_work_session', {
    'p_session': sessionId,
    'p_started_at': _time(startedAt),
    'p_ended_at': _time(endedAt),
    'p_reason': reason,
  });

  Future<void> addSession(
    String id, {
    required String userId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String reason,
  }) => _call('fn_add_work_session', {
    'p_job': id,
    'p_user': userId,
    'p_started_at': _time(startedAt),
    'p_ended_at': _time(endedAt),
    'p_reason': reason,
  });

  Future<void> setWaitSla(
    String waitId, {
    required bool counts,
    required String reason,
  }) => _call('fn_set_wait_sla', {
    'p_wait': waitId,
    'p_counts': counts,
    'p_reason': reason,
  });

  Future<void> cancel(String id, String reason) =>
      _call('fn_cancel_job_card', {'p_job': id, 'p_reason': reason});

  Future<void> reopen(String id, String reason) =>
      _call('fn_reopen_job_card', {'p_job': id, 'p_reason': reason});

  Future<void> comment(
    String jobId,
    String body, {
    String kind = 'comment',
    String visibility = 'internal',
    List<String> mentions = const [],
  }) => _call('fn_comment_job_card', {
    'p_client_ref': _uuid.v4(),
    'p_job': jobId,
    'p_body': body.trim(),
    'p_kind': kind,
    'p_visibility': visibility,
    'p_mentions': mentions,
  });

  /// Uploads files to `<site>/jobcard/<job>/` and records each one.
  Future<void> addFiles({
    required String jobId,
    required String siteId,
    required List<PickedFile> files,
  }) async {
    for (final f in files) {
      final ref = _uuid.v4();
      final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$siteId/jobcard/$jobId/$ref-$safe';
      try {
        await _client.storage
            .from('job-files')
            .uploadBinary(
              path,
              f.bytes,
              fileOptions: FileOptions(contentType: f.contentType),
            );
      } catch (e) {
        throw AppError.from(e);
      }
      await _call('fn_add_job_attachment', {
        'p_client_ref': ref,
        'p_job': jobId,
        'p_kind': f.kind,
        'p_path': path,
        'p_file_name': f.name,
        'p_content_type': f.contentType,
        'p_size': f.bytes.length,
        'p_caption': null,
      });
    }
  }
}
