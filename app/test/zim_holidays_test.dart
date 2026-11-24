import 'package:electrical_department/maintenance/zim_holidays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Easter Sunday', () {
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
    expect(easterSunday(2028), DateTime(2028, 4, 16));
  });

  test('2027 matches the holidays put in by migration 0059', () {
    final h = {for (final x in zimbabweHolidays(2027)) x.reason: x};
    expect(
      h['National Youth Day (from Sunday 21 February)']!.from,
      DateTime(2027, 2, 22),
    );
    expect(
      h['Easter: Good Friday to Easter Monday']!.from,
      DateTime(2027, 3, 26),
    );
    expect(
      h['Easter: Good Friday to Easter Monday']!.to,
      DateTime(2027, 3, 29),
    );
    expect(
      h['Independence Day (from Sunday 18 April)']!.from,
      DateTime(2027, 4, 19),
    );
    expect(h["Heroes' Day and Defence Forces Day"]!.from, DateTime(2027, 8, 9));
    expect(h["Heroes' Day and Defence Forces Day"]!.to, DateTime(2027, 8, 10));
    expect(
      h['Boxing Day (from Sunday 26 December)']!.from,
      DateTime(2027, 12, 27),
    );
    expect(h["Workers' Day"]!.from, DateTime(2027, 5, 1));
    expect(
      h['Easter: Good Friday to Easter Monday']!.message,
      contains('Back on Tuesday 30 March'),
    );
  });

  test("Heroes' Day is the second Monday of August", () {
    for (final y in [2026, 2028, 2029, 2030]) {
      final h = zimbabweHolidays(y)
          .firstWhere((x) => x.reason.startsWith('Heroes'));
      expect(h.from.weekday, DateTime.monday);
      expect(h.from.day, inInclusiveRange(8, 14));
    }
  });
}
