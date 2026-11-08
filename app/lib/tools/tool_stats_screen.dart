import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'tools_repository.dart';

/// Tool statistics (API.md section 11c): losses, late returns, damage,
/// calibration and who had what, over a period, for one site or all.
typedef ToolStatsQuery = ({String? site, int days});

final toolStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ToolStatsQuery>((ref, q) async {
      final now = DateTime.now();
      String day(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final res = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_tool_stats',
            params: {
              'p_site': q.site,
              'p_from': day(now.subtract(Duration(days: q.days))),
              'p_to': day(now),
            },
          );
      return Map<String, dynamic>.from(res as Map);
    });

List<Map<String, dynamic>> _list(Map<String, dynamic> s, String key) => [
  for (final x in (s[key] as List? ?? const []))
    Map<String, dynamic>.from(x as Map),
];

class ToolStatsScreen extends ConsumerStatefulWidget {
  const ToolStatsScreen({super.key});

  @override
  ConsumerState<ToolStatsScreen> createState() => _ToolStatsScreenState();
}

class _ToolStatsScreenState extends ConsumerState<ToolStatsScreen> {
  int _days = 30;
  bool _allSites = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final manySites =
        ref.watch(sessionProvider.select((s) => s.mySites.length)) > 1;
    final stats = ref.watch(
      toolStatsProvider((site: _allSites ? null : site?.id, days: _days)),
    );
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/equipment?side=tools'),
        title: Text(
          _allSites
              ? 'Tool stats · all sites'
              : 'Tool stats · ${site?.code ?? ''}',
        ),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            top + Space.md,
            Space.md,
            Space.xl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final d in const [7, 30, 90, 365])
                            chip(
                              d == 365 ? 'Year' : '$d days',
                              _days == d,
                              () => setState(() => _days = d),
                            ),
                          if (manySites)
                            chip(
                              'All my sites',
                              _allSites,
                              () => setState(() => _allSites = !_allSites),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    ...stats.when(
                      loading: () => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      error: (e, _) => [
                        EmptyState(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Could not load tool stats',
                          message: AppError.from(e).isRetryable
                              ? 'Stats load when you are connected.'
                              : AppError.from(e).message,
                        ),
                      ],
                      data: (s) => _body(context, theme, s),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> s,
  ) {
    final t = Map<String, dynamic>.from(s['totals'] as Map? ?? const {});
    int n(String k) => (t[k] as num?)?.toInt() ?? 0;
    final dates = MaterialLocalizations.of(context);
    String day(Object? v) =>
        v == null ? '' : dates.formatShortMonthDay(DateTime.parse(v as String));
    String who(Map<String, dynamic> x) =>
        [x['holder'] ?? 'Someone', ?x['company']].join(' · ');
    Widget toolRow(Map<String, dynamic> x, String sub, {Widget? trailing}) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          onTap: () => context.push('/tools/${x['tool_id']}'),
          title: Text('${x['code'] ?? ''} ${x['name'] ?? ''}'.trim()),
          subtitle: Text(sub),
          trailing: trailing,
        );
    Widget none(String text) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    final losses = _list(s, 'losses');
    final late = _list(s, 'late');
    final damage = _list(s, 'damage');
    final calibration = _list(s, 'calibration');
    final people = _list(s, 'people');

    return [
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          _Stat('Returned', n('returned'), null),
          _Stat('Lost', n('lost'), n('lost') > 0 ? Colors.red : null),
          _Stat(
            'Damaged',
            n('damaged'),
            n('damaged') > 0 ? Colors.orange : null,
          ),
          _Stat(
            'Returned late',
            n('late'),
            n('late') > 0 ? Colors.orange : null,
          ),
          _Stat(
            'Overdue now',
            n('overdue_now'),
            n('overdue_now') > 0 ? Colors.red : null,
          ),
          _Stat(
            'Calibration expired',
            n('calibration_expired'),
            n('calibration_expired') > 0 ? Colors.red : null,
          ),
          _Stat('Calibration in 30 days', n('calibration_due_30'), null),
        ],
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.xmark_octagon,
        title: 'Losses',
        child: losses.isEmpty
            ? none('Nothing lost in this period.')
            : Column(
                children: [
                  for (final x in losses)
                    toolRow(
                      x,
                      '${who(x)} · ${day(x['returned_on'])}'
                      '${x['note'] == null ? '' : ' · ${x['note']}'}',
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.clock,
        title: 'Late returns',
        child: late.isEmpty
            ? none('Everything came back on time.')
            : Column(
                children: [
                  for (final x in late)
                    toolRow(
                      x,
                      '${who(x)} · due ${day(x['due_back'])}'
                      '${x['still_out'] == true ? ' · still out' : ' · back ${day(x['returned_on'])}'}',
                      trailing: Pill(
                        label: '${x['days_late']} d late',
                        color: x['still_out'] == true
                            ? Colors.red
                            : Colors.orange,
                        dense: true,
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.wrench,
        title: 'Damage',
        child: damage.isEmpty
            ? none('Nothing came back damaged.')
            : Column(
                children: [
                  for (final x in damage)
                    toolRow(
                      x,
                      '${who(x)} · ${day(x['returned_on'])} · '
                      '${x['condition'] == 'damaged' ? 'damaged' : 'needs repair'}',
                      trailing: x['repair_number'] == null
                          ? null
                          : ActionChip(
                              label: Text(
                                '${x['repair_number']} · '
                                '${(x['repair_status'] as String? ?? '').replaceAll('_', ' ')}',
                              ),
                              onPressed: () =>
                                  context.push('/jobs/${x['repair_number']}'),
                            ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.gauge,
        title: 'Calibration',
        child: calibration.isEmpty
            ? none('No calibration due in the next 30 days.')
            : Column(
                children: [
                  for (final x in calibration)
                    toolRow(
                      x,
                      '${x['expired'] == true ? 'Expired' : 'Due'} '
                      '${dayWithYear(DateTime.parse(x['calibration_due'] as String))}',
                      trailing: x['expired'] == true
                          ? const Pill(
                              label: 'Expired',
                              color: Colors.red,
                              dense: true,
                            )
                          : null,
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.person_2,
        title: 'By person',
        child: people.isEmpty
            ? none('No tools came back in this period.')
            : Column(
                children: [
                  for (final x in people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: AppAvatar(name: x['holder'] as String? ?? '?'),
                      title: Text(who(x)),
                      subtitle: Text(
                        [
                          '${x['returned']} returned',
                          if ((x['late'] as num) > 0) '${x['late']} late',
                          if ((x['damaged'] as num) > 0)
                            '${x['damaged']} damaged',
                          if ((x['lost'] as num) > 0) '${x['lost']} lost',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
      ),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: SurfaceCard(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
