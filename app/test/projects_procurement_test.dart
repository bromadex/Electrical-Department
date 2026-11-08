import 'package:electrical_department/procurement/procurement_repository.dart';
import 'package:electrical_department/projects/projects_repository.dart';
import 'package:electrical_department/projects/roster_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BOQ pasted from a spreadsheet', () {
    test('reads tab, comma and semicolon rows and skips the header', () {
      final lines = parseBoq(
        'Description\tUnit\tQty\n'
        '2.5mm twin and earth\tm\t500\n'
        'Isolator 63A,pcs,4\n'
        '"Cable ties 300mm";pack;2,5\n'
        '\n',
      );
      expect(lines.map((l) => l.description), [
        '2.5mm twin and earth',
        'Isolator 63A',
        'Cable ties 300mm',
      ]);
      expect(lines.map((l) => l.unit), ['m', 'pcs', 'pack']);
      expect(lines.map((l) => l.qty), [500, 4, 2.5]);
    });

    test('two columns mean pieces; rows without a quantity are skipped', () {
      final lines = parseBoq('Lugs 16mm\t20\nNotes only\nBlank qty\tm\t');
      expect(lines, hasLength(1));
      expect(lines.single.unit, 'pcs');
      expect(lines.single.qty, 20);
    });
  });

  test('a roster cell cycles day, night, off, leave and back to empty', () {
    final seen = <String?>[];
    String? s;
    for (var i = 0; i < 5; i++) {
      s = nextShift(s);
      seen.add(s);
    }
    expect(seen, ['day', 'night', 'off', 'leave', null]);
  });

  test('weeks start on Monday', () {
    expect(mondayOf(DateTime(2026, 11, 8)), DateTime(2026, 11, 2)); // Sunday
    expect(mondayOf(DateTime(2026, 11, 2, 15)), DateTime(2026, 11, 2));
    expect(isoDay(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('project progress follows its job cards', () {
    Project p(int done, int total, {String status = 'active', String? due}) =>
        Project.fromJson({
          'id': 'p',
          'site_id': 's',
          'code': 'P-0001',
          'name': 'Substation 3',
          'status': status,
          'target_date': due,
          'jobs_total': total,
          'jobs_done': done,
          'member_ids': ['u1'],
        });
    expect(p(1, 4).progress, 0.25);
    expect(p(0, 0).progress, 0);
    final today = DateTime(2026, 11, 8);
    expect(p(0, 1, due: '2026-11-01').overdue(today), isTrue);
    expect(p(0, 1, due: '2026-11-01', status: 'done').overdue(today), isFalse);
    expect(p(0, 1).memberIds, ['u1']);
  });

  test('a line knows what is left to issue or receive', () {
    final l = OrderLine.fromJson({
      'id': 'l',
      'item_id': null,
      'description': '36-way DB board',
      'unit': 'pcs',
      'qty': 3,
      'issued_qty': 1,
    });
    expect(l.left, 2);
    expect(l.stocked, isFalse);
    final over = OrderLine.fromJson({
      'id': 'm',
      'item_id': 'i',
      'description': 'Cable',
      'unit': 'm',
      'qty': 10,
      'received_qty': 12,
    });
    expect(over.left, 0);
    expect(over.stocked, isTrue);
  });
}
