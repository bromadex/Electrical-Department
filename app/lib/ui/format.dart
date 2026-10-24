import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Shows times in the site time zone from system_settings (Africa/Harare
/// unless an administrator changes it), whatever the device's own zone.
class SiteTime {
  static tz.Location? _location;
  static bool _loaded = false;

  static void configure(String timezone) {
    if (!_loaded) {
      tzdata.initializeTimeZones();
      _loaded = true;
    }
    try {
      _location = tz.getLocation(timezone);
    } catch (_) {
      _location = null;
    }
  }

  /// The configured zone's name, e.g. `Africa/Harare`.
  static String get zoneName => _location?.name ?? 'device time';

  /// [t] as wall-clock time in the site zone.
  static DateTime local(DateTime t) {
    final loc = _location;
    if (loc == null) return t.toLocal();
    return tz.TZDateTime.from(t, loc);
  }

  /// A wall-clock date and time picked in the site zone, as a UTC instant.
  static DateTime toInstant(DateTime wall) {
    final loc = _location;
    if (loc == null) {
      return DateTime(
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
      ).toUtc();
    }
    return tz.TZDateTime(
      loc,
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    ).toUtc();
  }

  /// Now, as wall-clock time in the site zone.
  static DateTime now() => local(DateTime.now().toUtc());
}

final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _date = DateFormat('d MMM yyyy');
final _time = DateFormat('HH:mm');
final _dayMonth = DateFormat('d MMM');

String fmtDateTime(DateTime? t) =>
    t == null ? '—' : _dateTime.format(SiteTime.local(t));

String fmtDate(DateTime? t) =>
    t == null ? '—' : _date.format(SiteTime.local(t));

String fmtTime(DateTime? t) =>
    t == null ? '—' : _time.format(SiteTime.local(t));

String fmtDayMonth(DateTime? t) =>
    t == null ? '—' : _dayMonth.format(SiteTime.local(t));

/// Minutes as a readable duration: 45 → "45 min", 95 → "1 h 35 min",
/// 3000 → "2 d 2 h". Null (not measured) → "—".
String fmtMinutes(num? minutes) {
  if (minutes == null) return '—';
  final m = minutes.abs().round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final rm = m % 60;
  if (h < 24) return rm == 0 ? '$h h' : '$h h $rm min';
  final d = h ~/ 24;
  final rh = h % 24;
  return rh == 0 ? '$d d' : '$d d $rh h';
}

/// "just now", "5 min ago", "in 2 h".
String fmtRelative(DateTime? t) {
  if (t == null) return '—';
  final diff = DateTime.now().toUtc().difference(t.toUtc()).inMinutes;
  if (diff.abs() < 1) return 'just now';
  return diff > 0 ? '${fmtMinutes(diff)} ago' : 'in ${fmtMinutes(-diff)}';
}

/// A timestamptz value from Supabase, as a UTC instant.
DateTime? parseTime(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toUtc();

/// A numeric value from Supabase (int, double or numeric-as-string).
num? parseNum(Object? v) => switch (v) {
  null => null,
  final num n => n,
  final String s => num.tryParse(s),
  _ => null,
};
