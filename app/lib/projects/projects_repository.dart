import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../v2/site_filter.dart';

/// Projects, the roster and the calendar (API.md section 18).

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

/// The Monday of [d]'s week.
DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

const projectStatuses = {
  'active': 'Active',
  'on_hold': 'On hold',
  'done': 'Done',
  'cancelled': 'Cancelled',
};

class Project {
  Project.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      name = j['name'] as String,
      description = j['description'] as String?,
      targetDate = _date(j['target_date']),
      ownerId = j['owner_id'] as String?,
      status = j['status'] as String,
      jobsTotal = (j['jobs_total'] as num?)?.toInt() ?? 0,
      jobsDone = (j['jobs_done'] as num?)?.toInt() ?? 0,
      memberIds = [
        for (final m in (j['member_ids'] as List? ?? const [])) m as String,
      ];

  final String id;
  final String siteId;
  final String code;
  final String name;
  final String? description;
  final DateTime? targetDate;
  final String? ownerId;
  final String status;
  final int jobsTotal;
  final int jobsDone;
  final List<String> memberIds;

  /// Share of its job cards closed, 0 to 1.
  double get progress => jobsTotal == 0 ? 0 : jobsDone / jobsTotal;

  bool get open => status == 'active' || status == 'on_hold';

  bool overdue(DateTime today) =>
      open && targetDate != null && targetDate!.isBefore(today);
}

/// The current site's projects (or every site's, with All my sites), open
/// ones first, then by target date.
final projectsProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final site = ref.watch(siteFilterProvider);
  if (site == null && !ref.watch(allSitesProvider)) return const [];
  var q = ref.watch(supabaseProvider).from('project_overview').select();
  if (site != null) q = q.eq('site_id', site);
  final rows = await q.order('target_date', ascending: true, nullsFirst: false);
  final list = [for (final r in rows) Project.fromJson(r)];
  list.sort((a, b) => (a.open == b.open) ? 0 : (a.open ? -1 : 1));
  return list;
});

final projectProvider = FutureProvider.autoDispose.family<Project?, String>((
  ref,
  id,
) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('project_overview')
      .select()
      .eq('id', id)
      .maybeSingle();
  return row == null ? null : Project.fromJson(row);
});

typedef ProjectJob = ({String id, String number, String title, String status});

/// A project's job cards.
final projectJobsProvider = FutureProvider.autoDispose
    .family<List<ProjectJob>, String>((ref, projectId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_cards')
          .select('id, number, title, status')
          .eq('project_id', projectId)
          .eq('is_archived', false)
          .order('registered_at', ascending: false);
      return [
        for (final r in rows)
          (
            id: r['id'] as String,
            number: r['number'] as String,
            title: r['title'] as String? ?? '',
            status: r['status'] as String? ?? '',
          ),
      ];
    });

/// Stock issued to a project, by item: what went out in total.
final projectMaterialsProvider = FutureProvider.autoDispose
    .family<List<({String name, String unit, double qty})>, String>((
      ref,
      projectId,
    ) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('stock_moves')
          .select('qty, item:store_items(name, unit)')
          .eq('project_id', projectId)
          .eq('kind', 'issue');
      final totals = <String, ({String name, String unit, double qty})>{};
      for (final r in rows) {
        final item = r['item'] as Map? ?? const {};
        final key = '${item['name']}|${item['unit']}';
        final q = -((r['qty'] as num?)?.toDouble() ?? 0);
        final had = totals[key];
        totals[key] = (
          name: item['name'] as String? ?? 'Item',
          unit: item['unit'] as String? ?? '',
          qty: (had?.qty ?? 0) + q,
        );
      }
      return totals.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    });

/// One entry on the calendar.
class CalendarEvent {
  CalendarEvent.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      refId = j['ref_id'] as String?,
      title = j['title'] as String? ?? '',
      day = DateTime.parse(j['day'] as String),
      at = j['at'] == null ? null : DateTime.parse(j['at'] as String).toLocal(),
      link = j['link'] as String?;

  final String kind;
  final String? refId;
  final String title;
  final DateTime day;
  final DateTime? at;
  final String? link;
}

typedef CalendarQuery = ({String site, DateTime from, DateTime to});

final calendarProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, CalendarQuery>((ref, q) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_calendar',
            params: {
              'p_site': q.site,
              'p_from': isoDay(q.from),
              'p_to': isoDay(q.to),
            },
          );
      return [
        for (final r in rows as List)
          CalendarEvent.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    });

const shifts = {'day': 'Day', 'night': 'Night', 'off': 'Off', 'leave': 'Leave'};

class RosterEntry {
  RosterEntry({
    required this.userId,
    required this.day,
    required this.shift,
    this.standby = false,
  });

  RosterEntry.fromJson(Map<String, dynamic> j)
    : userId = j['user_id'] as String,
      day = DateTime.parse(j['day'] as String),
      shift = j['shift'] as String,
      standby = j['standby'] as bool? ?? false;

  final String userId;
  final DateTime day;
  final String shift;
  final bool standby;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'day': isoDay(day),
    'shift': shift,
    'standby': standby,
  };
}

/// A week of the roster at a site, and whether it was published.
typedef RosterWeek = ({List<RosterEntry> entries, DateTime? publishedAt});

final rosterWeekProvider = FutureProvider.autoDispose
    .family<RosterWeek, ({String site, DateTime monday})>((ref, q) async {
      final db = ref.watch(supabaseProvider);
      final (rows, week) = await (
        db
            .from('roster_entries')
            .select('user_id, day, shift, standby')
            .eq('site_id', q.site)
            .eq('is_archived', false)
            .gte('day', isoDay(q.monday))
            .lte('day', isoDay(q.monday.add(const Duration(days: 6)))),
        db
            .from('roster_weeks')
            .select('published_at')
            .eq('site_id', q.site)
            .eq('week_start', isoDay(q.monday))
            .maybeSingle(),
      ).wait;
      return (
        entries: [for (final r in rows) RosterEntry.fromJson(r)],
        publishedAt: week?['published_at'] == null
            ? null
            : DateTime.parse(week!['published_at'] as String).toLocal(),
      );
    });

final projectActionsProvider = Provider((ref) => ProjectActions(ref));

class ProjectActions {
  ProjectActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) =>
      _ref.read(supabaseProvider).rpc(fn, params: params);

  Future<String> save({
    Project? project,
    required String siteId,
    required String name,
    String? description,
    DateTime? targetDate,
    String? ownerId,
    String status = 'active',
    List<String>? members,
  }) async {
    final id = project?.id ?? _uuid.v4();
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue('fn_save_project', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_name': name.trim(),
      'p_description': description?.trim(),
      'p_target_date': targetDate == null ? null : isoDay(targetDate),
      'p_owner': ownerId,
      'p_status': status,
      'p_members': members,
    }, flushNow: false);
    await outbox.flush();
    _ref.invalidate(projectsProvider);
    _ref.invalidate(projectProvider(id));
    return id;
  }

  /// Puts a job card on [projectId], or takes it off with null (online).
  Future<void> setJobProject(
    String jobCardId,
    String? projectId, {
    String? previous,
  }) async {
    await _rpc('fn_set_job_project', {
      'p_job_card': jobCardId,
      'p_project': projectId,
    });
    for (final p in [?projectId, ?previous]) {
      _ref.invalidate(projectJobsProvider(p));
      _ref.invalidate(projectProvider(p));
    }
    _ref.invalidate(projectsProvider);
  }

  /// Saves a week; [publish] tells everyone on it.
  Future<void> setRoster(
    String siteId,
    DateTime monday,
    List<Map<String, dynamic>> entries, {
    bool publish = false,
  }) async {
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue('fn_set_roster', {
      'p_site': siteId,
      'p_week_start': isoDay(monday),
      'p_entries': entries,
      'p_publish': publish,
    }, flushNow: false);
    await outbox.flush();
    _ref.invalidate(rosterWeekProvider((site: siteId, monday: monday)));
  }
}
