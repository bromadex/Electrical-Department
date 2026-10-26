import '../ui/format.dart';
import '../ui/status.dart';

/// One row of v_job_cards: the job card plus names and computed
/// classification and timing.
class JobCard {
  JobCard(this.r)
    : id = r['id'] as String,
      number = r['number'] as String,
      siteId = r['site_id'] as String,
      title = r['title'] as String,
      description = r['description'] as String,
      status = JobStatus.fromDb(r['status'] as String?),
      priority = Priority.fromCode(r['priority'] as String?),
      sla = SlaState.fromDb(r['sla_state'] as String?),
      impact = Impact.fromDb(r['operational_impact'] as String?),
      receivedAt = parseTime(r['received_at'])!,
      registeredAt = parseTime(r['registered_at'])!;

  /// The raw row, for the many optional fields read on the detail page.
  final Map<String, dynamic> r;

  final String id;
  final String number;
  final String siteId;
  final String title;
  final String description;
  final JobStatus status;
  final Priority priority;
  final SlaState sla;
  final Impact? impact;
  final DateTime receivedAt;
  final DateTime registeredAt;

  String? s(String key) {
    final v = r[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  DateTime? t(String key) => parseTime(r[key]);
  num? n(String key) => parseNum(r[key]);
  bool? b(String key) => r[key] as bool?;

  String get source => r['source'] as String;
  String? get siteCode => s('site_code');
  String? get siteName => s('site_name');
  String? get areaId => s('area_id');
  String? get areaName => s('area_name');
  String? get location => s('location');
  String get place => areaName ?? location ?? equipmentLocation ?? '—';
  String get reporterName => r['reporter_name'] as String;
  String? get departmentName => s('department_name');
  String? get assetId => s('asset_id');
  String? get equipment => s('equipment_display');
  String? get assetNo => s('asset_no_display');
  String? get equipmentLocation => s('equipment_location');
  String? get categoryName => s('category_name');
  String? get requestId => s('request_id');
  String? get requestNo => s('request_no');
  String? get legacyCode => s('legacy_code');
  String? get responsibleId => s('responsible_id');
  String? get responsibleName => s('responsible_name');
  String? get assignedByName => s('assigned_by_name');
  String? get registeredBy => s('registered_by');
  String? get registeredByName => s('registered_by_name');
  String? get performedBy => s('performed_by');
  String? get statusReason => s('status_reason');
  String? get maintenanceType => s('maintenance_type');
  String? get equipmentState => s('equipment_state');
  String? get criticalReason => s('critical_reason');

  bool get isCritical => r['is_critical'] as bool? ?? false;
  bool get isCriticalOpen => r['is_critical_open'] as bool? ?? false;
  bool get isOverdue => r['is_overdue'] as bool? ?? false;
  bool get isAssessed => t('assessed_at') != null;

  DateTime? get targetResponseAt => t('target_response_at');
  DateTime? get targetCompletionAt => t('target_completion_at');
  DateTime? get closedAt => t('closed_at');
  num? get responseMinutes => n('response_minutes');
  num? get elapsedMinutes => n('elapsed_minutes');
  num? get remainingMinutes => n('remaining_minutes');
  num? get overdueMinutes => n('overdue_minutes');
  bool? get responseTargetMet => b('response_target_met');
}

/// Saved views of the job card list; the dashboard cards open these.
enum JobCardView {
  open('open', 'All open'),
  all('all', 'All'),
  newJobs('new', 'New / received'),
  clarification('clarification', 'Needs clarification'),
  awaitingAssignment('awaiting_assignment', 'Awaiting assignment'),
  active('active', 'Active'),
  working('working', 'Being worked on'),
  waiting('waiting', 'Waiting / on hold'),
  critical('critical', 'Critical'),
  overdue('overdue', 'Overdue'),
  awaitingReview('awaiting_review', 'Awaiting review'),
  outOfService('out_of_service', 'Equipment out of service'),
  closedToday('closed_today', 'Closed today'),
  closed('closed', 'Closed'),
  cancelled('cancelled', 'Cancelled');

  const JobCardView(this.key, this.label);

  final String key;
  final String label;

  static JobCardView fromKey(String? k) =>
      values.firstWhere((v) => v.key == k, orElse: () => open);
}

/// Everything that decides which job cards the list shows; round-trips
/// through the URL so a filtered list can be linked to.
class JobCardFilter {
  const JobCardFilter({
    this.view = JobCardView.open,
    this.priorities = const {},
    this.search = '',
    this.from,
    this.to,
    this.responsibleId,
    this.assetId,
    this.sort = 'received_at',
    this.ascending = false,
    this.page = 0,
    this.siteId,
  });

  static const pageSize = 25;

  /// Server columns the table may sort by.
  static const sortable = {
    'number',
    'received_at',
    'priority_rank',
    'status',
    'target_completion_at',
    'responsible_name',
    'equipment_display',
    'area_name',
  };

  final JobCardView view;
  final Set<String> priorities;
  final String search;
  final DateTime? from;
  final DateTime? to;
  final String? responsibleId;
  final String? assetId;
  final String sort;
  final bool ascending;
  final int page;

  /// Site to show; null = all the user's sites. Comes from the site picker.
  final String? siteId;

  factory JobCardFilter.fromQuery(Map<String, String> q, {String? siteId}) {
    final sort = q['sort'];
    return JobCardFilter(
      view: JobCardView.fromKey(q['view']),
      priorities: {
        for (final p in (q['priority'] ?? '').split(','))
          if (const {'P1', 'P2', 'P3', 'P4'}.contains(p)) p,
      },
      search: q['q'] ?? '',
      from: DateTime.tryParse(q['from'] ?? '')?.toUtc(),
      to: DateTime.tryParse(q['to'] ?? '')?.toUtc(),
      responsibleId: q['responsible'],
      assetId: q['asset'],
      sort: sortable.contains(sort) ? sort! : 'received_at',
      ascending: q['asc'] == '1',
      page: int.tryParse(q['page'] ?? '') ?? 0,
      siteId: siteId,
    );
  }

  Map<String, String> toQuery() => {
    if (view != JobCardView.open) 'view': view.key,
    if (priorities.isNotEmpty)
      'priority': (priorities.toList()..sort()).join(','),
    if (search.isNotEmpty) 'q': search,
    if (from != null) 'from': from!.toIso8601String(),
    if (to != null) 'to': to!.toIso8601String(),
    'responsible': ?responsibleId,
    'asset': ?assetId,
    if (sort != 'received_at') 'sort': sort,
    if (ascending) 'asc': '1',
    if (page > 0) 'page': '$page',
  };

  JobCardFilter copyWith({
    JobCardView? view,
    Set<String>? priorities,
    String? search,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    String? sort,
    bool? ascending,
    int? page,
  }) => JobCardFilter(
    view: view ?? this.view,
    priorities: priorities ?? this.priorities,
    search: search ?? this.search,
    from: clearDates ? null : from ?? this.from,
    to: clearDates ? null : to ?? this.to,
    responsibleId: responsibleId,
    assetId: assetId,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    page: page ?? this.page,
    siteId: siteId,
  );

  @override
  bool operator ==(Object other) =>
      other is JobCardFilter &&
      other.view == view &&
      other.priorities.length == priorities.length &&
      other.priorities.containsAll(priorities) &&
      other.search == search &&
      other.from == from &&
      other.to == to &&
      other.responsibleId == responsibleId &&
      other.assetId == assetId &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.page == page &&
      other.siteId == siteId;

  @override
  int get hashCode => Object.hash(
    view,
    Object.hashAllUnordered(priorities),
    search,
    from,
    to,
    responsibleId,
    assetId,
    sort,
    ascending,
    page,
    siteId,
  );
}

class PagedResult<T> {
  const PagedResult(this.rows, this.total);

  final List<T> rows;
  final int total;
}

class Assignment {
  Assignment(Map<String, dynamic> r)
    : id = r['id'] as String,
      userId = r['user_id'] as String,
      role = r['role'] as String,
      personName = (r['person'] as Map?)?['full_name'] as String? ?? 'Someone',
      assignerName = (r['assigner'] as Map?)?['full_name'] as String?,
      assignedAt = parseTime(r['assigned_at'])!,
      acknowledgedAt = parseTime(r['acknowledged_at']),
      endedAt = parseTime(r['ended_at']),
      endReason = r['end_reason'] as String?,
      handoverNote = r['handover_note'] as String?;

  final String id;
  final String userId;
  final String role;
  final String personName;
  final String? assignerName;
  final DateTime assignedAt;
  final DateTime? acknowledgedAt;
  final DateTime? endedAt;
  final String? endReason;
  final String? handoverNote;

  bool get isCurrent => endedAt == null;
  bool get isResponsible => role == 'responsible';
}

class JobComment {
  JobComment(Map<String, dynamic> r)
    : id = r['id'] as String,
      authorId = r['author_id'] as String?,
      authorName = (r['author'] as Map?)?['full_name'] as String? ?? 'Someone',
      kind = r['kind'] as String,
      visibility = r['visibility'] as String,
      body = r['body'] as String,
      createdAt = parseTime(r['created_at'])!;

  final String id;
  final String? authorId;
  final String authorName;
  final String kind;
  final String visibility;
  final String body;
  final DateTime createdAt;
}

class JobAttachment {
  JobAttachment(Map<String, dynamic> r, this.url)
    : id = r['id'] as String,
      kind = r['kind'] as String,
      bucket = r['bucket'] as String,
      path = r['path'] as String,
      fileName = r['file_name'] as String?,
      contentType = r['content_type'] as String?,
      caption = r['caption'] as String?,
      uploaderName = (r['uploader'] as Map?)?['full_name'] as String?,
      createdAt = parseTime(r['created_at'])!;

  final String id;
  final String kind;
  final String bucket;
  final String path;
  final String? fileName;
  final String? contentType;
  final String? caption;
  final String? uploaderName;
  final DateTime createdAt;

  /// Signed URL, valid for an hour.
  final String? url;

  bool get isImage =>
      (contentType ?? '').startsWith('image/') ||
      kind.startsWith('photo') ||
      path.toLowerCase().endsWith('.jpg');
}

class JobClosure {
  JobClosure(Map<String, dynamic> r)
    : closedAt = parseTime(r['closed_at'])!,
      summary = r['completion_summary'] as String?,
      findings = r['findings'] as String?,
      correctiveAction = r['corrective_action'] as String?,
      equipmentStateAfter = r['equipment_state_after'] as String?,
      performerName = (r['performer'] as Map?)?['full_name'] as String?,
      verifierName = (r['verifier'] as Map?)?['full_name'] as String?,
      selfApproved = r['self_approved'] as bool? ?? false,
      legacy = r['legacy'] as bool? ?? false,
      elapsedMinutes = parseNum(r['elapsed_minutes'])?.round(),
      activeMinutes = parseNum(r['active_minutes'])?.round(),
      labourMinutes = parseNum(r['labour_minutes'])?.round(),
      waitMinutes = parseNum(r['wait_minutes'])?.round(),
      slaExcludedMinutes = parseNum(r['sla_excluded_minutes'])?.round(),
      pauseCount = parseNum(r['pause_count'])?.round(),
      responseMinutes = parseNum(r['response_minutes'])?.round(),
      assignmentMinutes = parseNum(r['assignment_minutes'])?.round(),
      startMinutes = parseNum(r['start_minutes'])?.round(),
      responseTargetMet = r['response_target_met'] as bool?,
      completionTargetMet = r['completion_target_met'] as bool?,
      labourHoursReported = parseNum(r['labour_hours_reported']);

  /// Phase 2 metrics, frozen at closure; null on earlier closures.
  final int? elapsedMinutes;
  final int? activeMinutes;
  final int? labourMinutes;
  final int? waitMinutes;
  final int? slaExcludedMinutes;
  final int? pauseCount;
  final int? responseMinutes;
  final int? assignmentMinutes;
  final int? startMinutes;
  final bool? responseTargetMet;
  final bool? completionTargetMet;
  final num? labourHoursReported;

  bool get hasMetrics => activeMinutes != null;

  final DateTime closedAt;
  final String? summary;
  final String? findings;
  final String? correctiveAction;
  final String? equipmentStateAfter;
  final String? performerName;
  final String? verifierName;
  final bool selfApproved;
  final bool legacy;
}

class JobCardExtras {
  const JobCardExtras({
    this.assignments = const [],
    this.comments = const [],
    this.attachments = const [],
    this.closures = const [],
  });

  final List<Assignment> assignments;
  final List<JobComment> comments;
  final List<JobAttachment> attachments;
  final List<JobClosure> closures;

  List<Assignment> get current => [
    for (final a in assignments)
      if (a.isCurrent) a,
  ];
}

class TimelineEntry {
  TimelineEntry(Map<String, dynamic> r)
    : at = parseTime(r['at'])!,
      actor = r['actor'] as String? ?? 'System',
      kind = r['kind'] as String,
      title = r['title'] as String? ?? '',
      detail = r['detail'] as String?;

  final DateTime at;
  final String actor;
  final String kind;
  final String title;
  final String? detail;
}

/// A person who can be assigned, with their current load (fn_workload).
class Workload {
  Workload(Map<String, dynamic> r)
    : userId = r['user_id'] as String,
      name = r['full_name'] as String? ?? '',
      responsibleOpen = (r['responsible_open'] as num?)?.toInt() ?? 0,
      supportOpen = (r['support_open'] as num?)?.toInt() ?? 0,
      overdue = (r['overdue'] as num?)?.toInt() ?? 0,
      critical = (r['critical'] as num?)?.toInt() ?? 0,
      estimatedHours = parseNum(r['estimated_hours']) ?? 0;

  final String userId;
  final String name;
  final int responsibleOpen;
  final int supportOpen;
  final int overdue;
  final int critical;
  final num estimatedHours;
}

class Person {
  const Person(this.id, this.name);

  final String id;
  final String name;
}
