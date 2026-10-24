import 'package:electrical_department/jobcards/models.dart';
import 'package:electrical_department/screens/notifications_screen.dart';
import 'package:electrical_department/ui/format.dart';
import 'package:electrical_department/ui/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('statuses', () {
    test('read exactly as stored, unknown values fall back to New', () {
      expect(
        JobStatus.fromDb('awaiting_production_clearance'),
        JobStatus.awaitingProductionClearance,
      );
      expect(JobStatus.fromDb('nonsense'), JobStatus.registered);
    });

    test('holds count as active but not as being worked on', () {
      expect(JobStatus.awaitingMaterials.isHold, isTrue);
      expect(JobStatus.awaitingMaterials.isActive, isTrue);
      expect(JobStatus.inProgress.isHold, isFalse);
      expect(JobStatus.awaitingReview.isActive, isFalse);
    });

    test('only closed and cancelled are not open', () {
      final notOpen = JobStatus.values.where((s) => !s.isOpen).toSet();
      expect(notOpen, {JobStatus.closed, JobStatus.cancelled});
    });

    test('priority and deadline states read from their codes', () {
      expect(Priority.fromCode('P1'), Priority.p1);
      expect(Priority.fromCode(null), Priority.p3);
      expect(SlaState.fromDb('completed_late'), SlaState.completedLate);
      expect(SlaState.fromDb(null), SlaState.noTarget);
    });
  });

  group('job card list filter', () {
    test('round-trips through the URL', () {
      final f = JobCardFilter(
        view: JobCardView.overdue,
        priorities: const {'P2', 'P1'},
        search: 'conveyor',
        from: DateTime.utc(2026, 10, 1),
        sort: 'target_completion_at',
        ascending: true,
        page: 2,
      );
      final q = f.toQuery();
      expect(q['priority'], 'P1,P2');
      final back = JobCardFilter.fromQuery(q);
      expect(back.view, JobCardView.overdue);
      expect(back.priorities, {'P1', 'P2'});
      expect(back.search, 'conveyor');
      expect(back.from, DateTime.utc(2026, 10, 1));
      expect(back.sort, 'target_completion_at');
      expect(back.ascending, isTrue);
      expect(back.page, 2);
    });

    test('defaults leave the URL clean', () {
      expect(const JobCardFilter().toQuery(), isEmpty);
    });

    test('ignores unknown sort columns and priorities', () {
      final f = JobCardFilter.fromQuery({
        'sort': 'password',
        'priority': 'P9,P4',
        'view': 'x',
      });
      expect(f.sort, 'received_at');
      expect(f.priorities, {'P4'});
      expect(f.view, JobCardView.open);
    });
  });

  test('durations read naturally', () {
    expect(fmtMinutes(null), '—');
    expect(fmtMinutes(45), '45 min');
    expect(fmtMinutes(95), '1 h 35 min');
    expect(fmtMinutes(120), '2 h');
    expect(fmtMinutes(3000), '2 d 2 h');
    expect(fmtMinutes(-30), '30 min');
  });

  test('site time is used whatever the device zone', () {
    SiteTime.configure('Africa/Harare');
    final local = SiteTime.local(DateTime.utc(2026, 10, 24, 22, 30));
    expect((local.day, local.hour), (25, 0));
    expect(
      SiteTime.toInstant(DateTime(2026, 10, 25, 0, 30)),
      DateTime.utc(2026, 10, 24, 22, 30),
    );
  });

  test('notification links open the right screen', () {
    expect(notificationPath('jobcard:abc'), '/job-cards/abc');
    expect(notificationPath('request:def'), '/requests/def');
    expect(notificationPath('job:old'), isNull);
    expect(notificationPath(null), isNull);
  });

  test('database values become readable labels', () {
    expect(humanize('out_of_service'), 'Out of service');
    expect(humanize(null), '—');
  });
}
