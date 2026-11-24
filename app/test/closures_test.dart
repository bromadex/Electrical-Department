import 'package:electrical_department/maintenance/closures.dart';
import 'package:electrical_department/maintenance/planned_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Closure closure(String from, String to, {String? site}) => Closure.fromJson({
  'id': 'c',
  'site_id': site,
  'starts_on': from,
  'ends_on': to,
  'reason': 'Christmas shutdown',
});

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  test('a closure covers both its days, and work reopens the day after', () {
    final c = closure('2026-12-19', '2027-01-03');
    expect(c.covers(DateTime(2026, 12, 18, 23)), isFalse);
    expect(c.covers(DateTime(2026, 12, 19, 7)), isTrue);
    expect(c.covers(DateTime(2027, 1, 3, 17)), isTrue);
    expect(c.covers(DateTime(2027, 1, 4)), isFalse);
    expect(c.reopens, DateTime(2027, 1, 4));
  });

  test('every-site closures apply everywhere; a site one only there', () {
    expect(closure('2026-12-19', '2027-01-03').at('kam'), isTrue);
    expect(closure('2026-12-19', '2027-01-03', site: 'kam').at('kam'), isTrue);
    expect(closure('2026-12-19', '2027-01-03', site: 'kam').at('sel'), isFalse);
    expect(closure('2026-12-19', '2027-01-03', site: 'kam').at(null), isFalse);
  });

  test('Home mentions a closure on now or within a month', () {
    final now = DateTime.now();
    final soon = closure(
      iso(now.add(const Duration(days: 10))),
      iso(now.add(const Duration(days: 20))),
    );
    final later = closure(
      iso(now.add(const Duration(days: 40))),
      iso(now.add(const Duration(days: 50))),
    );
    final on = closure(iso(now), iso(now.add(const Duration(days: 2))));
    expect(closureSoon([soon], null), soon);
    expect(closureSoon([later], null), isNull);
    expect(closureSoon([on, soon], null), on);
  });

  test('taking turns names who is next', () {
    final people = {'a': 'Tendai Moyo', 'b': 'Farai Dube', 'c': 'Kuda Ncube'};
    expect(
      turnsText(['a', 'b', 'c'], 1, people),
      'turns: Tendai → Farai → Kuda (next Farai)',
    );
    expect(turnsText(['a', 'b'], 5, people), contains('next Farai'));
    expect(turnsText([], 0, people), '');
  });
}
