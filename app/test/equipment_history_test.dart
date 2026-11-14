import 'package:electrical_department/assets/equipment_history.dart';
import 'package:electrical_department/search/search_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equipment history reads the server row and spots repeat faults', () {
    final h = EquipmentHistory.fromJson({
      'asset_id': 'a1',
      'tag': 'GEN-03',
      'name': 'Generator 3',
      'faults': 5,
      'faults_30': 3,
      'last_fault_at': '2026-11-10T08:00:00Z',
      'down_hours': 7.5,
      'down_now': true,
    });
    expect(h.repeats, isTrue);
    expect(h.downNow, isTrue);
    expect(h.lastFaultAt, DateTime.utc(2026, 11, 10, 8));
    expect(
      EquipmentHistory.fromJson({'asset_id': 'a2', 'faults_30': 2}).repeats,
      isFalse,
    );
  });

  test('downtime reads in hours, then days', () {
    expect(downtimeText(0), '0 h');
    expect(downtimeText(8), '8 h');
    expect(downtimeText(7.5), '7.5 h');
    expect(downtimeText(60), '2.5 days');
    expect(downtimeText(24 * 12), '12 days');
  });

  test('every kind of search result has its own icon', () {
    expect(searchIcon('item:1'), CupertinoIcons.cube_box_fill);
    expect(searchIcon('doc:1'), CupertinoIcons.book_fill);
    expect(searchIcon('unknown:1'), CupertinoIcons.tag_fill);
  });
}
