/// Zimbabwe's public holidays for a year, as closed days with a message
/// for the team. A holiday on a Sunday moves to the Monday; Heroes' Day is
/// the second Monday of August and Defence Forces Day the day after.
library;

typedef Holiday = ({DateTime from, DateTime to, String reason, String message});

/// Easter Sunday (Gregorian), by the anonymous Gregorian algorithm.
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

String _dayName(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

List<Holiday> zimbabweHolidays(int year) {
  Holiday one(DateTime d, String name, String message) {
    // A Sunday holiday is kept on the Monday.
    if (d.weekday == DateTime.sunday) {
      final m = d.add(const Duration(days: 1));
      return (
        from: m,
        to: m,
        reason: '$name (from ${_dayName(d)})',
        message: message,
      );
    }
    return (from: d, to: d, reason: name, message: message);
  }

  final easter = easterSunday(year);
  final goodFriday = easter.subtract(const Duration(days: 2));
  final easterMonday = easter.add(const Duration(days: 1));
  var heroes = DateTime(year, 8, 1);
  while (heroes.weekday != DateTime.monday) {
    heroes = heroes.add(const Duration(days: 1));
  }
  heroes = heroes.add(const Duration(days: 7));
  final afterHeroes = heroes.add(const Duration(days: 2));
  final afterEaster = easterMonday.add(const Duration(days: 1));

  return [
    one(
      DateTime(year, 1, 1),
      "New Year's Day",
      'Happy New Year from the Electrical Department! Wishing you a safe '
          'and good year ahead.',
    ),
    one(
      DateTime(year, 2, 21),
      'National Youth Day',
      "Happy National Youth Day! Here's to the young electricians and "
          'apprentices growing with us: keep learning, keep asking, keep it '
          'safe.',
    ),
    (
      from: goodFriday,
      to: easterMonday,
      reason: 'Easter: Good Friday to Easter Monday',
      message:
          'Happy Easter to you and your families. Enjoy the long weekend, '
          'rest well and travel safely. Back on ${_dayName(afterEaster)}.',
    ),
    one(
      DateTime(year, 4, 18),
      'Independence Day',
      'Happy Independence Day, Zimbabwe! Proud of the team that keeps the '
          'power on, every day.',
    ),
    one(
      DateTime(year, 5, 1),
      "Workers' Day",
      "Happy Workers' Day! Thank you for the skill, care and long hours you "
          'put in. Every job done safely is something to be proud of.',
    ),
    one(
      DateTime(year, 5, 25),
      'Africa Day',
      'Happy Africa Day! Celebrating the people and the work that power our '
          'continent.',
    ),
    (
      from: heroes,
      to: heroes.add(const Duration(days: 1)),
      reason: "Heroes' Day and Defence Forces Day",
      message:
          "On Heroes' Day and Defence Forces Day we remember those who "
          'served. Enjoy the two days with your families; back on '
          '${_dayName(afterHeroes)}.',
    ),
    one(
      DateTime(year, 12, 22),
      'Unity Day',
      'Happy Unity Day! One team, every site: thank you for pulling '
          'together all year.',
    ),
    one(
      DateTime(year, 12, 25),
      'Christmas Day',
      'Merry Christmas from the Electrical Department! Thank you for a safe '
          'year. Enjoy the day with your loved ones.',
    ),
    one(
      DateTime(year, 12, 26),
      'Boxing Day',
      'Happy Boxing Day! Rest, recharge and stay safe on the roads.',
    ),
  ];
}
