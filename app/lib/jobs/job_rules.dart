import 'package:flutter/cupertino.dart';

import '../data/local_db.dart';
import '../data/permission_set.dart';
import '../theme/tokens.dart';

/// Job statuses in board order (cancelled jobs are hidden from the board).
enum JobStatus {
  open('Open', CupertinoIcons.circle, BrandColors.info),
  taken('Taken', CupertinoIcons.hand_raised, BrandColors.coral),
  inProgress('In progress', CupertinoIcons.bolt_fill, BrandColors.warning),
  waiting('Waiting', CupertinoIcons.hourglass, Color(0xFF8C8FA3)),
  done('Done', CupertinoIcons.checkmark_seal_fill, BrandColors.success),
  cancelled('Cancelled', CupertinoIcons.xmark_circle, Color(0xFF8C7A7C));

  const JobStatus(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  String get db => this == inProgress ? 'in_progress' : name;

  static JobStatus parse(String s) => s == 'in_progress'
      ? inProgress
      : JobStatus.values.firstWhere((v) => v.name == s, orElse: () => open);

  static const board = [open, taken, inProgress, waiting, done];
}

enum JobPriority {
  low('Low', Color(0xFF8C8FA3)),
  normal('Normal', BrandColors.info),
  urgent('Urgent', Color(0xFFE5484D));

  const JobPriority(this.label, this.color);

  final String label;
  final Color color;

  static JobPriority parse(String s) =>
      JobPriority.values.firstWhere((v) => v.name == s, orElse: () => normal);
}

/// What the signed-in user can do with a job; mirrors the checks in
/// migration 0002 so buttons only show when the server would allow them.
enum JobAction {
  take,
  start,
  wait,
  resume,
  handBack,
  close,
  assign,
  edit,
  cancel,
}

Set<JobAction> jobActions(LocalJob job, String? me, PermissionSet perms) {
  final status = JobStatus.parse(job.status);
  final site = job.siteId;
  final canWork = perms.can('jobs.close', siteId: site);
  final isSuper = perms.can('jobs.assign', siteId: site);
  final mine = me != null && job.assigneeId == me;
  final poster = me != null && job.createdBy == me;
  final a = <JobAction>{};

  if (status == JobStatus.done || status == JobStatus.cancelled) return a;

  if (status == JobStatus.open && canWork) a.add(JobAction.take);
  if (mine || isSuper) {
    if (status == JobStatus.taken) a.add(JobAction.start);
    if (status == JobStatus.inProgress) a.add(JobAction.wait);
    if (status == JobStatus.waiting) a.add(JobAction.resume);
    if (status != JobStatus.open) a.add(JobAction.handBack);
  }
  if ((mine && canWork) || isSuper) {
    if (status != JobStatus.open || isSuper) a.add(JobAction.close);
  }
  if (isSuper) a.add(JobAction.assign);
  if (poster || isSuper) {
    a.add(JobAction.edit);
    a.add(JobAction.cancel);
  }
  return a;
}

bool isOverdue(LocalJob job, [DateTime? now]) {
  final s = JobStatus.parse(job.status);
  if (s == JobStatus.done || s == JobStatus.cancelled) return false;
  return job.dueAt != null && job.dueAt!.isBefore(now ?? DateTime.now());
}

/// The one row of filters on the Jobs tab. Every filter but [done] shows
/// only jobs still to finish.
enum JobFilter {
  active('All active'),
  mine('Mine'),
  unassigned('Needs someone'),
  urgent('Urgent'),
  overdue('Overdue'),
  waiting('Waiting'),
  done('Done');

  const JobFilter(this.label);

  final String label;
}

bool matchesFilter(
  LocalJob job,
  JobFilter filter, {
  String? me,
  String? areaId,
  String query = '',
  DateTime? now,
}) {
  if (job.status == 'cancelled') return false;
  if (areaId != null && job.areaId != areaId) return false;
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty &&
      !job.title.toLowerCase().contains(q) &&
      !(job.code?.toLowerCase().contains(q) ?? false) &&
      !(job.description?.toLowerCase().contains(q) ?? false)) {
    return false;
  }
  final done = job.status == 'done';
  return switch (filter) {
    JobFilter.active => !done,
    JobFilter.mine => !done && me != null && job.assigneeId == me,
    JobFilter.unassigned => !done && job.assigneeId == null,
    JobFilter.urgent => !done && job.priority == 'urgent',
    JobFilter.overdue => isOverdue(job, now),
    JobFilter.waiting => job.status == 'waiting',
    JobFilter.done => done,
  };
}

/// Board order: urgent first, then overdue, then soonest due, then newest.
int compareJobs(LocalJob a, LocalJob b) {
  int rank(LocalJob j) => j.priority == 'urgent' ? 0 : (isOverdue(j) ? 1 : 2);
  final r = rank(a).compareTo(rank(b));
  if (r != 0) return r;
  if (a.dueAt != null && b.dueAt != null) {
    final d = a.dueAt!.compareTo(b.dueAt!);
    if (d != 0) return d;
  } else if (a.dueAt != null || b.dueAt != null) {
    return a.dueAt != null ? -1 : 1;
  }
  return b.createdAt.compareTo(a.createdAt);
}

/// "in 3h", "2d ago" and the like.
String relativeTime(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = t.difference(n);
  final past = d.isNegative;
  final a = d.abs();
  final String s;
  if (a.inMinutes < 1) {
    return 'now';
  } else if (a.inHours < 1) {
    s = '${a.inMinutes}m';
  } else if (a.inDays < 1) {
    s = '${a.inHours}h';
  } else {
    s = '${a.inDays}d';
  }
  return past ? '$s ago' : 'in $s';
}
