import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_providers.dart';
import '../ui/format.dart';
import 'repository.dart';

/// Measured times of a job card (API.md section 9), in seconds.
class TimeSummary {
  TimeSummary(Map<String, dynamic> r)
    : activeSeconds = _int(r['active_seconds']) ?? 0,
      labourSeconds = _int(r['labour_seconds']) ?? 0,
      waitSeconds = _int(r['wait_seconds']) ?? 0,
      slaExcludedSeconds = _int(r['sla_excluded_seconds']) ?? 0,
      pauseCount = _int(r['pause_count']) ?? 0,
      sessionCount = _int(r['session_count']) ?? 0,
      elapsedSeconds = _int(r['elapsed_seconds']) ?? 0,
      responseSeconds = _int(r['response_seconds']),
      assignmentSeconds = _int(r['assignment_seconds']),
      startSeconds = _int(r['start_seconds']);

  final int activeSeconds;
  final int labourSeconds;
  final int waitSeconds;
  final int slaExcludedSeconds;
  final int pauseCount;
  final int sessionCount;
  final int elapsedSeconds;
  final int? responseSeconds;
  final int? assignmentSeconds;
  final int? startSeconds;
}

int? _int(Object? v) => parseNum(v)?.round();

class WorkSession {
  WorkSession(Map<String, dynamic> r)
    : id = r['id'] as String,
      userId = r['user_id'] as String,
      name = r['name'] as String? ?? 'Someone',
      startedAt = parseTime(r['started_at'])!,
      endedAt = parseTime(r['ended_at']),
      endReason = r['end_reason'] as String?,
      pauseReason = r['pause_reason'] as String?,
      pauseNote = r['pause_note'] as String?,
      corrected = r['corrected'] as bool? ?? false;

  final String id;
  final String userId;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final String? pauseReason;
  final String? pauseNote;
  final bool corrected;

  bool get running => endedAt == null;
}

class JobWait {
  JobWait(Map<String, dynamic> r)
    : id = r['id'] as String,
      holdStatus = r['hold_status'] as String,
      note = r['note'] as String?,
      startedAt = parseTime(r['started_at'])!,
      endedAt = parseTime(r['ended_at']),
      countsTowardSla = r['counts_toward_sla'] as bool? ?? true,
      slaReason = r['sla_reason'] as String?;

  final String id;
  final String holdStatus;
  final String? note;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool countsTowardSla;
  final String? slaReason;
}

class TimeCorrection {
  TimeCorrection(Map<String, dynamic> r)
    : person = r['person'] as String? ?? 'Someone',
      oldStartedAt = parseTime(r['old_started_at']),
      oldEndedAt = parseTime(r['old_ended_at']),
      newStartedAt = parseTime(r['new_started_at'])!,
      newEndedAt = parseTime(r['new_ended_at']),
      reason = r['reason'] as String? ?? '',
      by = r['by'] as String? ?? 'Someone',
      at = parseTime(r['at'])!;

  final String person;
  final DateTime? oldStartedAt;
  final DateTime? oldEndedAt;
  final DateTime newStartedAt;
  final DateTime? newEndedAt;
  final String reason;
  final String by;
  final DateTime at;
}

class Reading {
  const Reading(this.name, this.value, [this.unit]);

  factory Reading.fromJson(Map<String, dynamic> r) => Reading(
    r['name'] as String? ?? '',
    r['value'] as String? ?? '',
    r['unit'] as String?,
  );

  final String name;
  final String value;
  final String? unit;

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    if (unit != null && unit!.isNotEmpty) 'unit': unit,
  };

  @override
  String toString() => '$name: $value${unit == null ? '' : ' $unit'}';
}

/// Work log entry types, in the order the form offers them.
const workRecordKinds = [
  ('work_performed', 'Work performed'),
  ('symptoms', 'Fault symptoms'),
  ('diagnosis', 'Fault diagnosis'),
  ('root_cause', 'Root cause'),
  ('corrective_action', 'Corrective action'),
  ('components', 'Components repaired or replaced'),
  ('spares_used', 'Spare parts used'),
  ('readings', 'Equipment readings'),
  ('test_results', 'Test results'),
  ('safety_observation', 'Safety observation'),
  ('recommendation', 'Recommendation'),
  ('follow_up', 'Follow-up action'),
  ('delay_reason', 'Reason for delay'),
];

String workRecordLabel(String kind) => workRecordKinds
    .firstWhere((k) => k.$1 == kind, orElse: () => (kind, kind))
    .$2;

class WorkRecord {
  WorkRecord(Map<String, dynamic> r)
    : id = r['id'] as String,
      kind = r['kind'] as String,
      body = r['body'] as String?,
      readings = [
        for (final x in (r['readings'] as List? ?? const []))
          Reading.fromJson(Map<String, dynamic>.from(x as Map)),
      ],
      author = r['author'] as String? ?? 'Someone',
      createdAt = parseTime(r['created_at'])!;

  final String id;
  final String kind;
  final String? body;
  final List<Reading> readings;
  final String author;
  final DateTime createdAt;
}

class SafetyRecord {
  SafetyRecord(Map<String, dynamic> r)
    : confirmed = r['confirmed'] as bool? ?? false,
      reference = r['reference'] as String?,
      note = r['note'] as String?,
      by = r['by'] as String? ?? 'Someone',
      at = parseTime(r['at'])!;

  final bool confirmed;
  final String? reference;
  final String? note;
  final String by;
  final DateTime at;
}

class SafetyItem {
  SafetyItem(Map<String, dynamic> r)
    : id = r['id'] as String,
      phase = r['phase'] as String,
      label = r['label'] as String,
      needsReference = r['needs_reference'] as bool? ?? false,
      applies = r['applies'] as bool? ?? true,
      last = r['last'] == null
          ? null
          : SafetyRecord(Map<String, dynamic>.from(r['last'] as Map));

  final String id;
  final String phase;
  final String label;
  final bool needsReference;

  /// Whether this job card needs it (from the assessment).
  final bool applies;
  final SafetyRecord? last;

  bool get done =>
      last != null &&
      last!.confirmed &&
      (!needsReference || (last!.reference?.trim().isNotEmpty ?? false));
}

class SafetyState {
  SafetyState(Map<String, dynamic> r)
    : policy = r['policy'] as String? ?? 'off',
      required = r['required'] as bool? ?? false,
      missingBefore = [
        for (final x in (r['missing_before'] as List? ?? const [])) '$x',
      ],
      missingAfter = [
        for (final x in (r['missing_after'] as List? ?? const [])) '$x',
      ],
      items = [
        for (final x in (r['items'] as List? ?? const []))
          SafetyItem(Map<String, dynamic>.from(x as Map)),
      ];

  final String policy;

  /// The site policy requires the checks on this job card.
  final bool required;
  final List<String> missingBefore;
  final List<String> missingAfter;
  final List<SafetyItem> items;
}

class Submission {
  Submission(Map<String, dynamic> r)
    : id = r['id'] as String,
      submittedAt = parseTime(r['submitted_at'])!,
      submittedBy = r['submitted_by_name'] as String? ?? 'Someone',
      summary = r['completion_summary'] as String? ?? '',
      findings = r['findings'] as String? ?? '',
      correctiveAction = r['corrective_action'] as String? ?? '',
      equipmentStateAfter = r['equipment_state_after'] as String?,
      functionalTests = r['functional_tests'] as String?,
      electricalTests = r['electrical_tests'] as String?,
      materialsUsed = r['materials_used'] as String?,
      labourHours = parseNum(r['labour_hours']),
      recordedLabourMinutes = _int(r['recorded_labour_minutes']) ?? 0,
      outstandingDefects = r['outstanding_defects'] as String?,
      recommendations = r['recommendations'] as String?;

  final String id;
  final DateTime submittedAt;
  final String submittedBy;
  final String summary;
  final String findings;
  final String correctiveAction;
  final String? equipmentStateAfter;
  final String? functionalTests;
  final String? electricalTests;
  final String? materialsUsed;
  final num? labourHours;
  final int recordedLabourMinutes;
  final String? outstandingDefects;
  final String? recommendations;
}

class Review {
  Review(Map<String, dynamic> r)
    : id = r['id'] as String,
      decision = r['decision'] as String,
      notes = r['notes'] as String?,
      reviewer = r['reviewer_name'] as String? ?? 'Someone',
      createdAt = parseTime(r['created_at'])!,
      followUpNumber = r['follow_up_number'] as String?,
      selfApproved = r['self_approved'] as bool? ?? false,
      answer = r['answer'] as String?,
      answeredBy = r['answered_by_name'] as String?,
      answeredAt = parseTime(r['answered_at']);

  final String id;

  /// approve, reject or request_info.
  final String decision;
  final String? notes;
  final String reviewer;
  final DateTime createdAt;
  final String? followUpNumber;
  final bool selfApproved;
  final String? answer;
  final String? answeredBy;
  final DateTime? answeredAt;

  bool get isOpenQuestion => decision == 'request_info' && answeredAt == null;
}

/// Everything fn_job_work returns: time, the work log, safety checks,
/// submissions and reviews of one job card.
class JobWork {
  JobWork(Map<String, dynamic> r, {DateTime? fetchedAt})
    : serverNow = parseTime(r['now'])!,
      fetchedAt = (fetchedAt ?? DateTime.now()).toUtc(),
      time = TimeSummary(Map<String, dynamic>.from(r['time'] as Map)),
      deadline = parseTime(r['deadline']),
      effectiveDeadline = parseTime(r['effective_deadline']),
      sessions = [
        for (final x in (r['sessions'] as List? ?? const []))
          WorkSession(Map<String, dynamic>.from(x as Map)),
      ],
      waits = [
        for (final x in (r['waits'] as List? ?? const []))
          JobWait(Map<String, dynamic>.from(x as Map)),
      ],
      corrections = [
        for (final x in (r['corrections'] as List? ?? const []))
          TimeCorrection(Map<String, dynamic>.from(x as Map)),
      ],
      records = [
        for (final x in (r['records'] as List? ?? const []))
          WorkRecord(Map<String, dynamic>.from(x as Map)),
      ],
      safety = SafetyState(Map<String, dynamic>.from(r['safety'] as Map)),
      submissions = [
        for (final x in (r['submissions'] as List? ?? const []))
          Submission(Map<String, dynamic>.from(x as Map)),
      ],
      reviews = [
        for (final x in (r['reviews'] as List? ?? const []))
          Review(Map<String, dynamic>.from(x as Map)),
      ];

  /// The server's clock when the record was read, and the device's.
  final DateTime serverNow;
  final DateTime fetchedAt;
  final TimeSummary time;
  final DateTime? deadline;

  /// The deadline after waits excluded from it.
  final DateTime? effectiveDeadline;
  final List<WorkSession> sessions;
  final List<JobWait> waits;
  final List<TimeCorrection> corrections;
  final List<WorkRecord> records;
  final SafetyState safety;
  final List<Submission> submissions;
  final List<Review> reviews;

  /// Server time now, from the device clock corrected by the difference
  /// seen when the record was read.
  DateTime serverTime(DateTime deviceNow) =>
      serverNow.add(deviceNow.toUtc().difference(fetchedAt));

  WorkSession? runningFor(String? userId) {
    for (final s in sessions) {
      if (s.running && s.userId == userId) return s;
    }
    return null;
  }

  int get runningCount => sessions.where((s) => s.running).length;
  JobWait? get openWait => waits.where((w) => w.endedAt == null).firstOrNull;

  Review? get openQuestion => reviews.where((r) => r.isOpenQuestion).lastOrNull;

  /// Times counted on to [deviceNow]: active grows while anyone works,
  /// labour by the number of people working, waiting while on hold.
  ({int active, int labour, int wait, int elapsed}) liveTimes(
    DateTime deviceNow, {
    required bool open,
  }) {
    final extra = deviceNow
        .toUtc()
        .difference(fetchedAt)
        .inSeconds
        .clamp(0, 1 << 30);
    return (
      active: time.activeSeconds + (runningCount > 0 ? extra : 0),
      labour: time.labourSeconds + runningCount * extra,
      wait: time.waitSeconds + (openWait != null ? extra : 0),
      elapsed: time.elapsedSeconds + (open ? extra : 0),
    );
  }
}

final jobWorkProvider = FutureProvider.autoDispose.family<JobWork, String>((
  ref,
  id,
) async {
  ref.watch(jobCardsLiveProvider);
  final res = await ref
      .watch(supabaseProvider)
      .rpc('fn_job_work', params: {'p_job': id});
  return JobWork(Map<String, dynamic>.from(res as Map));
});
