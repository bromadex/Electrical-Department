import 'package:electrical_department/data/import_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

const fields = <ImportField>[
  (key: 'name', label: 'Name', aliases: ['item', 'description']),
  (key: 'unit', label: 'Unit', aliases: ['uom']),
  (key: 'min_level', label: 'Minimum', aliases: ['min', 'reorder']),
  (key: 'on_hand', label: 'Stock', aliases: ['on hand', 'qty', 'quantity']),
];

void main() {
  test('columns are found by their headers, whatever the order and case', () {
    final cols = matchColumns([
      'Qty on hand',
      ' DESCRIPTION ',
      'UoM',
      'Notes',
      'Reorder level',
    ], fields);
    expect(cols, {'name': 1, 'unit': 2, 'min_level': 4, 'on_hand': 0});
  });

  test('a column is used once, and unknown columns are left out', () {
    final cols = matchColumns(['Item', 'Item code', 'Colour'], fields);
    expect(cols['name'], 0);
    expect(cols.containsKey('unit'), isFalse);
  });

  test('rows under the header become maps, blanks left out', () {
    final rows = rowsAsMaps(
      [
        ['Name', 'Unit', 'Qty'],
        ['Lugs 16mm', 'pcs', '40'],
        ['Cable', '', ' 300 '],
      ],
      {'name': 0, 'unit': 1, 'on_hand': 2},
    );
    expect(rows, [
      {'name': 'Lugs 16mm', 'unit': 'pcs', 'on_hand': '40'},
      {'name': 'Cable', 'on_hand': '300'},
    ]);
  });

  test('numbers as people type them', () {
    expect(importNumber('1,5'), '1.5');
    expect(importNumber(' 300 '), '300');
    expect(importNumber('lots'), isNull);
    expect(importNumber(null), isNull);
  });

  test('dates from Excel numbers, ISO and day-first text', () {
    expect(importDate('46418'), '2027-01-31'); // Excel's number for that day
    expect(importDate('2027-01-31'), '2027-01-31');
    expect(importDate('31/01/2027'), '2027-01-31');
    expect(importDate('5.3.2027'), '2027-03-05');
    expect(importDate('next year'), isNull);
    expect(importDate(''), isNull);
  });
}
