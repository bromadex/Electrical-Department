import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/import_sheet.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'store_repository.dart';

/// Inventory and project numbers (API.md section 20): what went out most,
/// stock used per project, corrections and what is low.
typedef StockStatsQuery = ({String? site, int days});

final stockStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, StockStatsQuery>((ref, q) async {
      final now = DateTime.now();
      String day(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final res = await ref
          .watch(supabaseProvider)
          .rpc(
            'fn_stock_stats',
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

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

class StockStatsScreen extends ConsumerStatefulWidget {
  const StockStatsScreen({super.key});

  @override
  ConsumerState<StockStatsScreen> createState() => _StockStatsScreenState();
}

class _StockStatsScreenState extends ConsumerState<StockStatsScreen> {
  int _days = 30;
  bool _allSites = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final manySites =
        ref.watch(sessionProvider.select((s) => s.mySites.length)) > 1;
    final stats = ref.watch(
      stockStatsProvider((site: _allSites ? null : site?.id, days: _days)),
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
        leading: const AppBackButton(fallback: '/inventory'),
        title: Text(
          _allSites
              ? 'Inventory stats · all sites'
              : 'Inventory stats · ${site?.code ?? ''}',
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
                          title: 'Could not load the stats',
                          message: AppError.from(e).message,
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
    Widget none(String text) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final top = _list(s, 'top_items');
    final projects = _list(s, 'projects');
    final jobs = _list(s, 'jobs');
    final corrections = _list(s, 'corrections');
    final low = _list(s, 'low');
    final dates = MaterialLocalizations.of(context);
    final maxQty = top.isEmpty
        ? 1.0
        : top.map((x) => _d(x['qty'])).reduce((a, b) => a > b ? a : b);

    return [
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          _Stat('Items', n('items'), null),
          _Stat('Low', n('low'), n('low') > 0 ? Colors.orange : null),
          _Stat('Empty', n('empty'), n('empty') > 0 ? Colors.red : null),
          _Stat('Received', n('receipts'), null),
          _Stat('Issued', n('issues'), null),
          _Stat('Returned', n('returns'), null),
          _Stat('Corrections', n('corrections'), null),
          _Stat('Requests open', n('requests_open'), null),
          _Stat('Purchases open', n('purchases_open'), null),
          _Stat('Projects open', n('projects_open'), null),
          _Stat(
            'Projects overdue',
            n('projects_overdue'),
            n('projects_overdue') > 0 ? Colors.red : null,
          ),
        ],
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.arrow_up_right,
        title: 'Used most',
        child: top.isEmpty
            ? none('Nothing issued in this period.')
            : Column(
                children: [
                  for (final x in top)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: InkWell(
                        onTap: () => context.push('/inventory/${x['item_id']}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${x['code']} ${x['name']}',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                Text(
                                  '${qtyText(_d(x['qty']))} ${x['unit']} · '
                                  '${x['issues']}×',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _d(x['qty']) / maxQty,
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.flag,
        title: 'Stock per project',
        child: projects.isEmpty
            ? none('No open projects.')
            : Column(
                children: [
                  for (final p in projects)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/projects/${p['project_id']}'),
                      title: Text('${p['code']} · ${p['name']}'),
                      subtitle: Text(
                        [
                          '${p['jobs_done']}/${p['jobs_total']} job cards',
                          if ((p['items'] as List).isEmpty)
                            'no stock issued'
                          else
                            for (final i in (p['items'] as List).take(4))
                              '${qtyText(_d((i as Map)['qty']))} ${i['unit']} ${i['name']}',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.doc_text,
        title: 'Job cards using the most stock',
        child: jobs.isEmpty
            ? none('No stock went to job cards in this period.')
            : Column(
                children: [
                  for (final j in jobs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => context.push('/jobs/${j['number']}'),
                      title: Text('${j['number']} · ${j['title']}'),
                      trailing: Text('${j['issues']} issues'),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.slider_horizontal_3,
        title: 'Corrections',
        child: corrections.isEmpty
            ? none('No adjustments or count differences.')
            : Column(
                children: [
                  for (final c in corrections)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => context.push('/inventory/${c['item_id']}'),
                      title: Text(
                        '${_d(c['qty']) > 0 ? '+' : '−'}'
                        '${qtyText(_d(c['qty']).abs())} ${c['unit']} '
                        '${c['name']}',
                      ),
                      subtitle: Text(
                        [
                          c['kind'] == 'count' ? 'count' : 'adjusted',
                          dates.formatShortMonthDay(
                            DateTime.parse(c['at'] as String).toLocal(),
                          ),
                          ?c['note'] as String?,
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: Space.md),
      Panel(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Low now',
        child: low.isEmpty
            ? none('Nothing is below its minimum.')
            : Column(
                children: [
                  for (final i in low)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => context.push('/inventory/${i['item_id']}'),
                      title: Text('${i['code']} ${i['name']}'),
                      trailing: Text(
                        '${qtyText(_d(i['on_hand']))} / '
                        '${qtyText(_d(i['min_level']))} ${i['unit']}',
                        style: const TextStyle(color: Colors.orange),
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
      width: 140,
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

/// Inventory items from a spreadsheet.
Widget itemsImportSheet(WidgetRef ref, String siteId) => ImportSheet(
  title: 'Import inventory items',
  help:
      'The first row names the columns. An item already in inventory (same '
      'name and unit) is updated; a new one is added with its stock as '
      'opening stock.',
  fields: const [
    (key: 'name', label: 'Name', aliases: ['item', 'description']),
    (key: 'unit', label: 'Unit', aliases: ['uom']),
    (key: 'category', label: 'Category', aliases: ['type', 'group']),
    (key: 'bin', label: 'Bin', aliases: ['shelf', 'location']),
    (key: 'min_level', label: 'Minimum', aliases: ['min', 'reorder']),
    (key: 'on_hand', label: 'Stock', aliases: ['on hand', 'qty', 'quantity']),
  ],
  required: const ['name'],
  onImport: (rows) async {
    final r = await ref
        .read(supabaseProvider)
        .rpc(
          'fn_import_items',
          params: {
            'p_site': siteId,
            'p_rows': [
              for (final r in rows)
                {
                  ...r,
                  'min_level': importNumber(r['min_level']),
                  'on_hand': importNumber(r['on_hand']),
                },
            ],
          },
        );
    ref.invalidate(storeItemsProvider);
    return '${r['created']} added, ${r['updated']} updated';
  },
);
