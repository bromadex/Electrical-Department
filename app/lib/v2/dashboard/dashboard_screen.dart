import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/session_controller.dart';
import '../../ui/surfaces.dart';
import '../jobcards/repository.dart' show jobCardsLiveProvider;
import '../my_jobs/my_jobs_screen.dart' show myJobsProvider;
import '../site_filter.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart' show humanize;
import 'dashboard_data.dart';

/// What needs me first, four numbers, then the charts (like the main app's
/// Home). Wide windows put "Needs you" on the left and the rest on the right.
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
      subtitle: site == null ? 'All your sites' : siteName,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.read(jobCardsLiveProvider.notifier).bumpNow(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider((site, range))),
        data: (d) => LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NeedsYouCard(data: d),
                  const SizedBox(height: Space.md),
                  JobCardNumbers(
                    data: d,
                    siteName: site == null ? null : siteName,
                  ),
                  const SizedBox(height: Space.md),
                  _Charts(data: d),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: NeedsYouCard(data: d)),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      JobCardNumbers(
                        data: d,
                        siteName: site == null ? null : siteName,
                      ),
                      const SizedBox(height: Space.md),
                      _Charts(data: d),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One row in "Needs you".
typedef NeedsYouItem = ({
  IconData icon,
  Color color,
  String title,
  String? detail,
  VoidCallback onTap,
});

/// Everything waiting on someone, most pressing first. One row per kind;
/// a single job card opens directly, several open the filtered list.
class NeedsYouCard extends ConsumerWidget {
  const NeedsYouCard({super.key, required this.data, this.extra = const []});

  final DashboardData data;

  /// Rows from outside job cards (Home adds checklists, documents and tools).
  final List<NeedsYouItem> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final perms = ref.watch(sessionProvider.select((s) => s.perms));
    final mine = ref.watch(myJobsProvider).value ?? const [];
    final d = data;
    void list(String view) => context.go('/jobs?view=$view');
    void job(Map<String, dynamic> r) => context.push('/jobs/${r['number']}');

    String one(Map<String, dynamic> r) => '${r['number']} · ${r['title']}';
    String? detail(Map<String, dynamic> r, String extra) => [
      r['site_code'],
      r['responsible_name'] ?? 'Not assigned',
      extra,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    NeedsYouItem? kind({
      required String key,
      required int count,
      required String several,
      required IconData icon,
      required Color color,
      required String Function(Map<String, dynamic> r) extra,
      required String view,
    }) {
      if (count == 0) return null;
      final rows = d.alerts[key] ?? const [];
      if (count == 1 && rows.length == 1) {
        final r = rows.single;
        return (
          icon: icon,
          color: color,
          title: one(r),
          detail: detail(r, extra(r)),
          onTap: () => job(r),
        );
      }
      return (
        icon: icon,
        color: color,
        title: several,
        detail: rows.isEmpty
            ? null
            : 'Most pressing: ${rows.first['number']} · ${rows.first['title']}',
        onTap: () => list(view),
      );
    }

    final critical = d.card('critical');
    final overdue = d.card('overdue');
    final unassigned = d.card('awaiting_assignment');
    final review = d.card('awaiting_review');
    final items = <NeedsYouItem>[
      ?kind(
        key: 'critical',
        count: critical,
        several: '$critical critical job cards',
        icon: Icons.report_rounded,
        color: AppColors.critical,
        extra: (r) => r['critical_reason'] as String? ?? 'Critical',
        view: 'critical',
      ),
      ?kind(
        key: 'overdue',
        count: overdue,
        several: '$overdue job cards are overdue',
        icon: Icons.alarm_rounded,
        color: AppColors.critical,
        extra: (r) =>
            'overdue by ${fmtMinutes(parseNum(r['overdue_minutes']))}',
        view: 'overdue',
      ),
      if (unassigned > 0 && perms.can('jc.assign'))
        (
          icon: Icons.person_search_outlined,
          color: AppColors.warning,
          title: unassigned == 1
              ? '1 job card needs someone'
              : '$unassigned job cards need someone',
          detail: 'Awaiting assignment',
          onTap: () => list('awaiting_assignment'),
        ),
      if (perms.can('jc.review'))
        ?kind(
          key: 'awaiting_review',
          count: review,
          several: '$review job cards to verify',
          icon: Icons.fact_check_outlined,
          color: AppColors.review,
          extra: (r) =>
              'submitted ${fmtRelative(parseTime(r['submitted_at']))}',
          view: 'awaiting_review',
        ),
      if (mine.length == 1)
        (
          icon: Icons.engineering_outlined,
          color: AppColors.burgundy,
          title: '${mine.single.number} · ${mine.single.title}',
          detail: 'Assigned to you · ${mine.single.status.label}',
          onTap: () => context.push('/jobs/${mine.single.number}'),
        )
      else if (mine.length > 1)
        (
          icon: Icons.engineering_outlined,
          color: AppColors.burgundy,
          title: '${mine.length} job cards assigned to you',
          detail: 'Most urgent first in My jobs',
          onTap: () => context.push('/jobs/mine'),
        ),
      ...extra,
    ];

    return SurfaceCard(
      radius: Radii.lg,
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Needs you', style: theme.textTheme.titleMedium),
              const SizedBox(width: Space.xs),
              if (items.isNotEmpty)
                Pill(
                  label: '${items.length}',
                  color: AppColors.burgundy,
                  dense: true,
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Column(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.success,
                    size: 40,
                  ),
                  const SizedBox(height: Space.xs),
                  Text('All caught up', style: theme.textTheme.titleSmall),
                  Text(
                    extra.isEmpty && data.cards.isNotEmpty
                        ? 'No job card is waiting on you.'
                        : 'Nothing is waiting on you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else
            for (final (i, it) in items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _Row(item: it),
            ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final NeedsYouItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.adapt(item.color, theme.brightness);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(item.icon, color: c, size: 20),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (item.detail != null)
                    Text(
                      item.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Four numbers in one card; each opens the job cards list with that filter.
class JobCardNumbers extends StatelessWidget {
  const JobCardNumbers({super.key, required this.data, required this.siteName});

  final DashboardData data;
  final String? siteName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = data;
    final numbers = [
      (
        'Open',
        d.card('total') - d.card('closed') - d.card('cancelled'),
        AppColors.burgundy,
        'open',
      ),
      ('Critical', d.card('critical'), AppColors.critical, 'critical'),
      ('Overdue', d.card('overdue'), AppColors.warning, 'overdue'),
      (
        'Closed today',
        d.card('closed_today'),
        AppColors.success,
        'closed_today',
      ),
    ];
    return SurfaceCard(
      radius: Radii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            siteName == null ? 'Job cards' : 'Job cards at $siteName',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (final (label, value, color, view) in numbers)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => context.go('/jobs?view=$view'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            '$value',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: value > 0
                                  ? AppColors.adapt(color, theme.brightness)
                                  : null,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The charts, with the period they cover.
class _Charts extends ConsumerWidget {
  const _Charts({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = data;
    final range = ref.watch(dashRangeProvider);
    String pct(num part, num whole) =>
        whole == 0 ? '—' : '${(part * 100 / whole).round()}%';
    final respMet = (d.responseTarget['met'] as num?) ?? 0;
    final respMissed = (d.responseTarget['missed'] as num?) ?? 0;
    final onTime = (d.completionTarget['on_time'] as num?) ?? 0;
    final late = (d.completionTarget['late'] as num?) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Charts · received in the last ${range.label}',
              style: theme.textTheme.titleSmall,
            ),
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
          ],
        ),
        const SizedBox(height: Space.sm),
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
