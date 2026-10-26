import 'package:electrical_department/data/local_db.dart';
import 'package:electrical_department/jobs/job_rules.dart';
import 'package:flutter_test/flutter_test.dart';

LocalJob job(
  String id, {
  String status = 'open',
  String priority = 'normal',
  String? assignee,
  DateTime? due,
}) => LocalJob(
  id: id,
  siteId: 's',
  title: 'Job $id',
  priority: priority,
  status: status,
  assigneeId: assignee,
  dueAt: due,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  pending: false,
  maintenanceType: 'corrective',
  isolationRequired: false,
);

void main() {
  final now = DateTime(2026, 10, 26, 12);
  final jobs = [
    job('open'),
    job('urgent', priority: 'urgent'),
    job('mine', status: 'in_progress', assignee: 'me'),
    job('late', status: 'taken', assignee: 'you', due: DateTime(2026, 10, 25)),
    job('waiting', status: 'waiting', assignee: 'me'),
    job('done', status: 'done', assignee: 'me'),
    job('cancelled', status: 'cancelled'),
  ];

  Set<String> ids(JobFilter f) => {
    for (final j in jobs)
      if (matchesFilter(j, f, me: 'me', now: now)) j.id,
  };

  test('each filter shows the jobs its name promises', () {
    expect(ids(JobFilter.active), {
      'open',
      'urgent',
      'mine',
      'late',
      'waiting',
    });
    expect(ids(JobFilter.mine), {'mine', 'waiting'});
    expect(ids(JobFilter.unassigned), {'open', 'urgent'});
    expect(ids(JobFilter.urgent), {'urgent'});
    expect(ids(JobFilter.overdue), {'late'});
    expect(ids(JobFilter.waiting), {'waiting'});
    expect(ids(JobFilter.done), {'done'});
  });

  test('search matches the title', () {
    expect(matchesFilter(job('x'), JobFilter.active, query: 'job x'), isTrue);
    expect(matchesFilter(job('x'), JobFilter.active, query: 'pump'), isFalse);
  });
}
