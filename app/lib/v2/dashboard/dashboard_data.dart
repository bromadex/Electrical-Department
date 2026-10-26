import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jobcards/repository.dart' show jobCardsLiveProvider;
import '../../services/core_providers.dart';
import '../ui/charts.dart';
import '../ui/format.dart';

/// Date range for the charts. Absolute, set when chosen, so the dashboard
/// does not reload on every rebuild.
class DashRange {
  const DashRange(this.label, this.from, this.to);

  final String label;
  final DateTime from;
  final DateTime to;

  /// The last [days] days including today, in the site time zone.
  factory DashRange.lastDays(int days, String label) {
    final now = SiteTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return DashRange(
      label,
      SiteTime.toInstant(tomorrow.subtract(Duration(days: days))),
      SiteTime.toInstant(tomorrow),
    );
  }
}

final dashRangeProvider = NotifierProvider<DashRangeNotifier, DashRange>(
  DashRangeNotifier.new,
);

class DashRangeNotifier extends Notifier<DashRange> {
  @override
  DashRange build() => DashRange.lastDays(30, '30 days');

  void set(DashRange r) => state = r;
}

class DashboardData {
  DashboardData(Map<String, dynamic> j, this.incomingRequests)
    : cards = {
        for (final e in Map<String, dynamic>.from(j['cards'] as Map).entries)
          e.key: (e.value as num).toInt(),
      },
      openVsClosed = Map<String, dynamic>.from(j['open_vs_closed'] as Map),
      byPriority = [
        for (final r in j['by_priority'] as List)
          Map<String, dynamic>.from(r as Map),
      ],
      byArea = _counts(j['by_area']),
      byEquipment = _counts(j['by_equipment']),
      byType = _counts(j['by_type']),
      overdueAgeing = _counts(j['overdue_ageing']),
      byTechnician = [
        for (final r in j['by_technician'] as List)
          Map<String, dynamic>.from(r as Map),
      ],
      trend = [
        for (final r in j['trend'] as List)
          TrendPoint(
            DateTime.parse((r as Map)['period'] as String),
            (r['received'] as num).toInt(),
            (r['closed'] as num).toInt(),
          ),
      ],
      avgResponseMinutes = parseNum(j['avg_response_minutes']),
      avgClosureMinutes = parseNum(j['avg_closure_minutes']),
      responseTarget = Map<String, dynamic>.from(j['response_target'] as Map),
      completionTarget = Map<String, dynamic>.from(
        j['completion_target'] as Map,
      ),
      alerts = {
        for (final e in Map<String, dynamic>.from(j['alerts'] as Map).entries)
          e.key: [
            for (final r in e.value as List)
              Map<String, dynamic>.from(r as Map),
          ],
      };

  static List<(String, int)> _counts(Object? v) => [
    for (final r in v as List)
      ((r as Map)['label'] as String, (r['count'] as num).toInt()),
  ];

  final Map<String, int> cards;
  final Map<String, dynamic> openVsClosed;
  final List<Map<String, dynamic>> byPriority;
  final List<(String, int)> byArea;
  final List<(String, int)> byEquipment;
  final List<(String, int)> byType;
  final List<(String, int)> overdueAgeing;
  final List<Map<String, dynamic>> byTechnician;
  final List<TrendPoint> trend;
  final num? avgResponseMinutes;
  final num? avgClosureMinutes;
  final Map<String, dynamic> responseTarget;
  final Map<String, dynamic> completionTarget;
  final Map<String, List<Map<String, dynamic>>> alerts;

  /// Requests from other departments waiting to be registered.
  final int? incomingRequests;

  int card(String key) => cards[key] ?? 0;
}

/// Everything on the dashboard for a site (null = all the user's sites).
final dashboardProvider = FutureProvider.autoDispose
    .family<DashboardData, (String?, DashRange)>((ref, args) async {
      ref.watch(jobCardsLiveProvider);
      final (site, range) = args;
      final client = ref.watch(supabaseProvider);
      final res = await client.rpc(
        'fn_dashboard',
        params: {
          'p_site': site,
          'p_from': range.from.toIso8601String(),
          'p_to': range.to.toIso8601String(),
        },
      );
      int? incoming;
      try {
        var q = client
            .from('service_requests')
            .select('id')
            .eq('status', 'submitted')
            .eq('is_archived', false);
        if (site != null) q = q.eq('site_id', site);
        incoming = (await q.count(CountOption.exact)).count;
      } catch (_) {
        incoming = null;
      }
      return DashboardData(Map<String, dynamic>.from(res as Map), incoming);
    });
