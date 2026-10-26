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
