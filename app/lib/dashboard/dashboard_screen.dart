import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobcards/repository.dart' show jobCardsLiveProvider;
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'dashboard_data.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteFilterProvider);
    final siteName = ref.watch(currentSiteProvider)?.name;
    final range = ref.watch(dashRangeProvider);
    final data = ref.watch(dashboardProvider((site, range)));

    return AppPage(
      title: 'Dashboard',
      subtitle:
          '${site == null ? 'All your sites' : siteName ?? ''} · charts cover job cards received in the last ${range.label}',
      actions: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: '7 days', label: Text('7 d')),
            ButtonSegment(value: '30 days', label: Text('30 d')),
            ButtonSegment(value: '90 days', label: Text('90 d')),
            ButtonSegment(value: '12 months', label: Text('12 m')),
          ],
          selected: {range.label},
          onSelectionChanged: (s) {
            final label = s.first;
            final days = switch (label) {
              '7 days' => 7,
              '90 days' => 90,
              '12 months' => 365,
              _ => 30,
            };
            ref
                .read(dashRangeProvider.notifier)
                .set(DashRange.lastDays(days, label));
          },
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.read(jobCardsLiveProvider.notifier).bumpNow(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider((site, range))),
        data: (d) => _Dashboard(data: d),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = data;
    final canTriage = ref.watch(
      sessionProvider.select((s) => s.perms.can('req.triage')),
    );
    void open(String view) => context.go('/job-cards?view=$view');

    String pct(num part, num whole) =>
        whole == 0 ? '—' : '${(part * 100 / whole).round()}%';
    final respMet = (d.responseTarget['met'] as num?) ?? 0;
    final respMissed = (d.responseTarget['missed'] as num?) ?? 0;
    final onTime = (d.completionTarget['on_time'] as num?) ?? 0;
    final late = (d.completionTarget['late'] as num?) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 210,
          children: [
            KpiCard(
              label: 'Total job cards',
              value: '${d.card('total')}',
              icon: Icons.assignment_outlined,
              color: AppColors.navy600,
              onTap: () => open('all'),
            ),
            KpiCard(
              label: 'New / received',
              value: '${d.card('new')}',
              icon: Icons.fiber_new_outlined,
              color: AppColors.info,
              onTap: () => open('new'),
            ),
            if (canTriage && d.incomingRequests != null)
              KpiCard(
                label: 'Incoming requests',
                value: '${d.incomingRequests}',
                icon: Icons.move_to_inbox_outlined,
                color: AppColors.info,
                onTap: () => context.go('/requests'),
              ),
            KpiCard(
              label: 'Awaiting assignment',
              value: '${d.card('awaiting_assignment')}',
              icon: Icons.person_search_outlined,
              color: AppColors.warning,
              onTap: () => open('awaiting_assignment'),
            ),
            KpiCard(
              label: 'Active jobs',
              value: '${d.card('active')}',
              caption:
                  '${d.card('working')} being worked · ${d.card('waiting')} waiting',
              icon: Icons.construction_rounded,
              color: AppColors.info,
              onTap: () => open('active'),
            ),
            KpiCard(
              label: 'Critical',
              value: '${d.card('critical')}',
              icon: Icons.report_rounded,
              color: AppColors.critical,
              onTap: () => open('critical'),
            ),
            KpiCard(
              label: 'Overdue',
              value: '${d.card('overdue')}',
              icon: Icons.alarm_rounded,
              color: AppColors.critical,
              onTap: () => open('overdue'),
            ),
            KpiCard(
              label: 'Awaiting engineering review',
              value: '${d.card('awaiting_review')}',
              icon: Icons.fact_check_outlined,
              color: AppColors.review,
              onTap: () => open('awaiting_review'),
            ),
            KpiCard(
              label: 'Closed',
              value: '${d.card('closed')}',
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.success,
              onTap: () => open('closed'),
            ),
            KpiCard(
              label: 'Closed today',
              value: '${d.card('closed_today')}',
              icon: Icons.today_outlined,
              color: AppColors.success,
              onTap: () => open('closed_today'),
            ),
            KpiCard(
              label: 'Equipment out of service',
              value: '${d.card('equipment_out_of_service')}',
              icon: Icons.power_off_outlined,
              color: AppColors.critical,
              onTap: () => open('out_of_service'),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        _Alerts(alerts: d.alerts),
        const SizedBox(height: Space.md),
        Panel(
          title: 'Job cards received versus closed',
          subtitle:
              'Per ${d.trend.length > 62
                  ? 'month'
                  : d.trend.length > 31
                  ? 'week'
                  : 'day'}',
          icon: Icons.show_chart_rounded,
          child: TrendChart(points: d.trend),
        ),
        const SizedBox(height: Space.md),
        ResponsiveGrid(
          minItemWidth: 380,
          spacing: Space.md,
          children: [
            Panel(
              title: 'Open versus closed',
              subtitle: 'Received in this period',
              icon: Icons.donut_large_rounded,
              child: DonutChart(
                segments: [
                  ChartSegment(
                    'Open',
                    (d.openVsClosed['open'] as num?) ?? 0,
                    AppColors.info,
                  ),
                  ChartSegment(
                    'Closed',
                    (d.openVsClosed['closed'] as num?) ?? 0,
                    AppColors.success,
                  ),
                  ChartSegment(
                    'Cancelled',
                    (d.openVsClosed['cancelled'] as num?) ?? 0,
                    AppColors.neutral,
                  ),
                ],
              ),
            ),
            Panel(
              title: 'By priority',
              icon: Icons.priority_high_rounded,
              child: StackedBarList(
                series: const [
                  ('Open', AppColors.info),
                  ('Closed', AppColors.success),
                ],
                items: [
                  for (final p in d.byPriority)
                    StackedItem('${p['code']} ${p['name']}', [
                      (p['open'] as num?) ?? 0,
                      (p['closed'] as num?) ?? 0,
                    ]),
                ],
              ),
            ),
            Panel(
              title: 'Type of work',
              subtitle: 'Reactive versus preventive and other work',
              icon: Icons.category_outlined,
              child: BarList(
                items: [
                  for (final (label, n) in d.byType)
                    BarItem(
                      label == 'not_assessed'
                          ? 'Not assessed yet'
                          : humanize(label),
                      n,
                      color: label == 'preventive'
                          ? AppColors.success
                          : label == 'reactive'
                          ? AppColors.warning
                          : null,
                    ),
                ],
              ),
            ),
            Panel(
              title: 'Overdue by age',
              subtitle: 'How long past the deadline',
              icon: Icons.alarm_rounded,
              child: BarList(
                color: AppColors.critical,
                items: [
                  for (final (label, n) in d.overdueAgeing) BarItem(label, n),
                ],
              ),
            ),
            Panel(
              title: 'By work area',
              icon: Icons.place_outlined,
              child: BarList(
                items: [for (final (label, n) in d.byArea) BarItem(label, n)],
              ),
            ),
            Panel(
              title: 'By equipment',
              subtitle: 'Most job cards in this period',
              icon: Icons.precision_manufacturing_outlined,
              child: BarList(
                items: [
                  for (final (label, n) in d.byEquipment) BarItem(label, n),
                ],
              ),
            ),
            Panel(
              title: 'By technician',
              icon: Icons.engineering_outlined,
              child: StackedBarList(
                series: const [
                  ('Open', AppColors.info),
                  ('Closed', AppColors.success),
                ],
                items: [
                  for (final t in d.byTechnician)
                    StackedItem(t['label'] as String, [
                      (t['open'] as num?) ?? 0,
                      (t['closed'] as num?) ?? 0,
                    ]),
                ],
              ),
            ),
            Panel(
              title: 'Response and closure',
              subtitle: 'Measured from recorded times',
              icon: Icons.timer_outlined,
              child: ResponsiveGrid(
                minItemWidth: 150,
                children: [
                  StatTile(
                    label: 'Average response time',
                    value: fmtMinutes(d.avgResponseMinutes),
                    caption: 'Received → response',
                  ),
                  StatTile(
                    label: 'Average time to close',
                    value: fmtMinutes(d.avgClosureMinutes),
                    caption: 'Received → closed',
                  ),
                  StatTile(
                    label: 'Response within target',
                    value: pct(respMet, respMet + respMissed),
                    caption: '$respMet met · $respMissed missed',
                  ),
                  StatTile(
                    label: 'Closed within target',
                    value: pct(onTime, onTime + late),
                    caption: '$onTime on time · $late late',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Jobs that need someone's attention now, each one link away.
class _Alerts extends StatefulWidget {
  const _Alerts({required this.alerts});

  final Map<String, List<Map<String, dynamic>>> alerts;

  @override
  State<_Alerts> createState() => _AlertsState();
}

class _AlertsState extends State<_Alerts> {
  static const _sections = [
    ('critical', 'Critical', Icons.report_rounded, AppColors.critical),
    ('overdue', 'Overdue', Icons.alarm_rounded, AppColors.critical),
    (
      'approaching',
      'Deadline soon',
      Icons.hourglass_bottom_rounded,
      AppColors.warning,
    ),
    (
      'production_impact',
      'Production impact',
      Icons.factory_outlined,
      AppColors.warning,
    ),
    (
      'awaiting_review',
      'Awaiting review',
      Icons.fact_check_outlined,
      AppColors.review,
    ),
    (
      'on_hold_long',
      'On hold too long',
      Icons.pause_circle_outline_rounded,
      AppColors.warning,
    ),
  ];
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _sections.fold<int>(
      0,
      (s, e) => s + (widget.alerts[e.$1]?.length ?? 0),
    );
    final key =
        _selected ??
        _sections
            .firstWhere(
              (s) => (widget.alerts[s.$1]?.isNotEmpty ?? false),
              orElse: () => _sections.first,
            )
            .$1;
    final rows = widget.alerts[key] ?? const [];
    return Panel(
      title: 'Needs attention',
      icon: Icons.notification_important_outlined,
      subtitle: total == 0 ? 'Nothing needs attention right now' : null,
      child: total == 0
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (k, label, icon, color) in _sections)
                      ChoiceChip(
                        selected: key == k,
                        showCheckmark: false,
                        avatar: Icon(icon, size: 16, color: color),
                        label: Text(
                          '$label (${widget.alerts[k]?.length ?? 0})',
                        ),
                        onSelected: (_) => setState(() => _selected = k),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(Space.md),
                    child: Text('None.'),
                  ),
                for (final r in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.go('/job-cards/${r['number']}'),
                    leading: PriorityBadge(
                      Priority.fromCode(r['priority'] as String?),
                    ),
                    title: Text(
                      '${r['number']} · ${r['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        r['site_code'],
                        r['equipment_display'],
                        r['responsible_name'] ?? 'Not assigned',
                        switch (key) {
                          'overdue' =>
                            'overdue by ${fmtMinutes(parseNum(r['overdue_minutes']))}',
                          'approaching' =>
                            '${fmtMinutes(parseNum(r['remaining_minutes']))} left',
                          'awaiting_review' =>
                            'submitted ${fmtRelative(parseTime(r['submitted_at']))}',
                          'on_hold_long' =>
                            '${humanize(r['status'] as String?)} since ${fmtDateTime(parseTime(r['status_changed_at']))}',
                          'production_impact' => humanize(
                            (r['operational_impact'] ?? r['equipment_state'])
                                as String?,
                          ),
                          _ => r['critical_reason'],
                        },
                      ].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: StatusPill(
                      JobStatus.fromDb(r['status'] as String?),
                      dense: true,
                    ),
                  ),
              ],
            ),
    );
  }
}
