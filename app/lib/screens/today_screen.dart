import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/notifications_controller.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';

enum _ChartMode { activity, areas }

final _chartModeProvider = NotifierProvider<_ChartModeNotifier, _ChartMode>(
  _ChartModeNotifier.new,
);

class _ChartModeNotifier extends Notifier<_ChartMode> {
  @override
  _ChartMode build() => _ChartMode.activity;

  void set(_ChartMode m) => state = m;
}

/// Dashboard: greeting, stats, charts and what is coming next.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final notes = ref.watch(notificationsProvider);

    return PageScroll(
      maxWidth: 1240,
      onRefresh: () async {
        await Future.wait([
          ref.read(sessionProvider.notifier).refresh(),
          ref.read(notificationsProvider.notifier).refresh(),
        ]);
      },
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 980;
            final stats = _GeneralStats(session: session, notes: notes);
            final side = [
              _SitesDonut(session: session),
              _PermissionsDonut(session: session),
            ];
            final lower = [const _Roadmap(), _Latest(notes: notes)];

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Greeting(session: session).entrance(context),
                  const SizedBox(height: Space.md),
                  stats.entrance(context, index: 1),
                  for (final (i, w) in [...side, ...lower].indexed) ...[
                    const SizedBox(height: Space.md),
                    w.entrance(context, index: 2 + i),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 13, child: stats.entrance(context)),
                      const SizedBox(width: Space.md),
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            Expanded(
                              child: side[0].entrance(context, index: 1),
                            ),
                            const SizedBox(height: Space.md),
                            Expanded(
                              child: side[1].entrance(context, index: 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lower[0].entrance(context, index: 3)),
                    const SizedBox(width: Space.md),
                    Expanded(child: lower[1].entrance(context, index: 4)),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = harareNow();
    final first = (session.profile?.fullName ?? '').split(' ').first;
    final hello = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${now.day} ${TodayScreen._months[now.month - 1]} · Harare',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            first.isEmpty ? hello : '$hello, $first',
            style: theme.textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _GeneralStats extends ConsumerWidget {
  const _GeneralStats({required this.session, required this.notes});

  final SessionState session;
  final NotificationsState notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(_chartModeProvider);
    final site = ref.watch(currentSiteProvider);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final chartHeight = MediaQuery.sizeOf(context).width >= 980 ? 330.0 : 220.0;

    // Notifications per day over the last 14 days (Harare dates).
    final today = harareNow();
    final days = [
      for (var i = 13; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
    final perDay = [
      for (final d in days)
        notes.items.where((n) {
          final t = n.createdAt.toUtc().add(const Duration(hours: 2));
          return t.year == d.year && t.month == d.month && t.day == d.day;
        }).length,
    ];
    final todayCount = perDay.last;

    final mySites = session.mySites;
    final areaCounts = [for (final s in mySites) session.areasAt(s.id).length];
    final currentIndex = mySites.indexWhere((s) => s.id == site?.id);

    final chart = mode == _ChartMode.activity
        ? BarChart(
            values: perDay,
            labels: [for (final d in days) '${d.day}.${d.month}'],
            highlight: perDay.length - 1,
            height: chartHeight,
          )
        : BarChart(
            values: areaCounts,
            labels: [for (final s in mySites) s.code],
            highlight: currentIndex < 0 ? null : currentIndex,
            height: chartHeight,
          );

    final tiles = [
      _StatTile(
        label: 'Unread',
        value: notes.unread,
        chip: todayCount > 0 ? TrendChip('$todayCount today') : null,
        onTap: () => context.push('/notifications'),
      ),
      _StatTile(
        label: 'Areas here',
        value: site == null ? 0 : session.areasAt(site.id).length,
        chip: Pill(label: site?.code ?? '—', dense: true),
      ),
    ];

    return PanelCard(
      icon: CupertinoIcons.chart_bar_alt_fill,
      title: 'General stats',
      trailing: narrow
          ? null
          : GlassSegmented<_ChartMode>(
              value: mode,
              segments: const {
                _ChartMode.activity: 'Activity',
                _ChartMode.areas: 'Areas',
              },
              onChanged: ref.read(_chartModeProvider.notifier).set,
            ),
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth >= 560;
          final chartBox = AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            child: KeyedSubtree(key: ValueKey(mode), child: chart),
          );
          if (side) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 190,
                  child: Column(
                    children: [
                      tiles[0],
                      const SizedBox(height: Space.sm),
                      tiles[1],
                    ],
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(child: chartBox),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow) ...[
                Center(
                  child: GlassSegmented<_ChartMode>(
                    value: mode,
                    segments: const {
                      _ChartMode.activity: 'Activity',
                      _ChartMode.areas: 'Areas',
                    },
                    onChanged: ref.read(_chartModeProvider.notifier).set,
                  ),
                ),
                const SizedBox(height: Space.md),
              ],
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: Space.sm),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: Space.md),
              chartBox,
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.chip,
    this.onTap,
  });

  final String label;
  final int value;
  final Widget? chip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: g.fillStrong,
          borderRadius: BorderRadius.circular(Radii.lg),
          gradient: g.sheen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedCount(
                  value: value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: Space.xs),
                if (chip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: chip,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPanel extends StatelessWidget {
  const _DonutPanel({
    required this.icon,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final List<(String, num, Color)> rows;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<num>(0, (a, r) => a + r.$2);
    String pct(num v) => total == 0 ? '0%' : '${(v * 100 / total).round()}%';
    return PanelCard(
      icon: icon,
      title: title,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                for (final (i, r) in rows.indexed)
                  LegendRow(
                    color: r.$3,
                    label: r.$1,
                    value: pct(r.$2),
                    last: i == rows.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.lg),
          DonutChart(
            size: 116,
            values: [for (final r in rows) r.$2],
            colors: [for (final r in rows) r.$3],
            center: Text(
              '$total',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

const _palette = [
  BrandColors.coral,
  BrandColors.blush,
  Color(0xFFE8E2E3),
  BrandColors.maroon,
  Color(0xFFB85C64),
  Color(0xFF8C7A7C),
];

class _SitesDonut extends StatelessWidget {
  const _SitesDonut({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return _DonutPanel(
      icon: CupertinoIcons.location_solid,
      title: 'Areas by site',
      rows: [
        for (final (i, s) in session.mySites.indexed)
          (s.name, session.areasAt(s.id).length, _palette[i % _palette.length]),
      ],
    );
  }
}

class _PermissionsDonut extends StatelessWidget {
  const _PermissionsDonut({required this.session});

  final SessionState session;

  static const _modules = {
    'jobs': 'Jobs',
    'store': 'Store',
    'tools': 'Tools',
    'docs': 'Documents',
    'chat': 'Chat',
  };

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final code in session.perms.codes) {
      final module = _modules[code.split('.').first] ?? 'Other';
      counts[module] = (counts[module] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _DonutPanel(
      icon: CupertinoIcons.checkmark_shield_fill,
      title: 'My permissions',
      rows: [
        for (final (i, e) in entries.take(4).indexed)
          (e.key, e.value, _palette[i % _palette.length]),
      ],
    );
  }
}

/// What the team is building next, from the build plan.
class _Roadmap extends StatelessWidget {
  const _Roadmap();

  static const _items = [
    ('Foundation', 'Clement & Tafara', 'Phase 0', 1.0),
    ('Jobs board', 'Clement', 'Phase 1', 0.0),
    ('Push notifications', 'Tafara', 'Phase 1', 0.0),
    ('Daily checklists', 'Clement', 'Phase 2', 0.0),
    ('Group chat', 'Tafara', 'Phase 2', 0.0),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    return PanelCard(
      icon: CupertinoIcons.rocket_fill,
      title: 'Roadmap',
      trailing: Pill(label: '15 weeks', dense: true),
      child: Column(
        children: [
          for (final (name, owner, phase, progress) in _items)
            Container(
              margin: const EdgeInsets.only(bottom: Space.xs),
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: g.fillStrong,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final info = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      Text(
                        '$owner · $phase',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                  final bar = _ProgressBar(value: progress);
                  final pct = SizedBox(
                    width: 44,
                    child: Text(
                      '${(progress * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium,
                    ),
                  );
                  final stacked = c.maxWidth < 360;
                  return Row(
                    children: [
                      AppAvatar(name: owner, size: 38),
                      const SizedBox(width: Space.sm),
                      if (stacked)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              info,
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(child: bar),
                                  pct,
                                ],
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Expanded(flex: 5, child: info),
                        Expanded(flex: 4, child: bar),
                        pct,
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: Motion.of(context, const Duration(milliseconds: 1200)),
      curve: Motion.decelerate,
      builder: (context, v, _) => Container(
        height: 6,
        decoration: BoxDecoration(
          color: g.fillInset,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: BrandColors.brandGradient,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

class _Latest extends ConsumerWidget {
  const _Latest({required this.notes});

  final NotificationsState notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = Glass.of(context);
    return PanelCard(
      icon: CupertinoIcons.bell_fill,
      title: 'Latest',
      trailing: TextButton(
        onPressed: () => context.push('/notifications'),
        child: const Text('See all'),
      ),
      child: notes.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Text(
                'Nothing new. You are all caught up.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : Column(
              children: [
                for (final n in notes.items.take(5))
                  Container(
                    margin: const EdgeInsets.only(bottom: Space.xs),
                    padding: const EdgeInsets.all(Space.sm),
                    decoration: BoxDecoration(
                      color: g.fillStrong,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.bell,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: n.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              ),
                              if (n.body != null)
                                Text(
                                  n.body!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
