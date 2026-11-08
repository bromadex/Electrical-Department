import 'dart:async';

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
import '../v2/site_filter.dart';
import '../widgets/app_back_button.dart';

/// One daily report in the archive, with the updates that matched.
typedef ArchivedReport = ({
  String siteId,
  String code,
  DateTime date,
  String status,
  int updates,
  List<String> matches,
});

/// Daily reports, newest first; with a search, only those whose updates
/// contain it (online).
final reportsArchiveProvider = FutureProvider.autoDispose
    .family<List<ArchivedReport>, String>((ref, query) async {
      final site = ref.watch(siteFilterProvider);
      if (site == null && !ref.watch(allSitesProvider)) return const [];
      final q = query.trim();
      final db = ref.watch(supabaseProvider);
      var select = db
          .from('daily_reports')
          .select(
            q.isEmpty
                ? 'site_id, code, report_date, status, report_updates(body)'
                : 'site_id, code, report_date, status, report_updates!inner(body)',
          );
      if (site != null) select = select.eq('site_id', site);
      if (q.isNotEmpty) {
        // Commas and brackets would break the filter; search the words.
        final clean = q.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
        select = select.ilike('report_updates.body', '%$clean%');
      }
      final rows = await select
          .order('report_date', ascending: false)
          .limit(q.isEmpty ? 120 : 60);
      return [
        for (final r in rows)
          (
            siteId: r['site_id'] as String,
            code: r['code'] as String,
            date: DateTime.parse(r['report_date'] as String),
            status: r['status'] as String,
            updates: (r['report_updates'] as List? ?? const []).length,
            matches: q.isEmpty
                ? const <String>[]
                : [
                    for (final u in (r['report_updates'] as List? ?? const []))
                      (u as Map)['body'] as String,
                  ],
          ),
      ];
    });

/// The archive of daily reports with search through everyone's updates.
class ReportsArchiveScreen extends ConsumerStatefulWidget {
  const ReportsArchiveScreen({super.key});

  @override
  ConsumerState<ReportsArchiveScreen> createState() =>
      _ReportsArchiveScreenState();
}

class _ReportsArchiveScreenState extends ConsumerState<ReportsArchiveScreen> {
  final _search = TextEditingController();
  String _query = '';
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Searches once typing pauses.
  void _changed(String v) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 450), () {
      if (mounted && v.trim() != _query) setState(() => _query = v.trim());
    });
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = ref.watch(reportsArchiveProvider(_query));
    final session = ref.watch(sessionProvider);
    final all = ref.watch(allSitesProvider);
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/reports'),
        title: const Text('Reports archive'),
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
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoSearchTextField(
                      controller: _search,
                      placeholder: 'Search what people wrote (e.g. pump 3)',
                      onChanged: _changed,
                      onSubmitted: (v) => setState(() => _query = v.trim()),
                      onSuffixTap: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
                    const SizedBox(height: Space.sm),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AllSitesChip(),
                    ),
                    const SizedBox(height: Space.sm),
                    ...reports.when(
                      loading: () => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      error: (e, _) => [
                        EmptyState(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Could not load reports',
                          message: AppError.from(e).message,
                        ),
                      ],
                      data: (list) => [
                        if (list.isEmpty)
                          EmptyState(
                            icon: CupertinoIcons.doc_chart,
                            title: _query.isEmpty
                                ? 'No daily reports yet'
                                : 'Nothing matches "$_query"',
                            message:
                                'Daily reports fill in as people add '
                                'their updates.',
                          ),
                        for (final r in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: SurfaceCard(
                              onTap: () =>
                                  context.push('/reports?date=${_iso(r.date)}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      RecordCode(r.code),
                                      if (all) ...[
                                        const SizedBox(width: Space.xs),
                                        Pill(
                                          label:
                                              session
                                                  .siteById(r.siteId)
                                                  ?.code ??
                                              '',
                                          dense: true,
                                        ),
                                      ],
                                      const SizedBox(width: Space.xs),
                                      Expanded(
                                        child: Text(
                                          dates.formatFullDate(r.date),
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      Pill(
                                        label: r.status == 'approved'
                                            ? 'Approved'
                                            : 'Open',
                                        color: r.status == 'approved'
                                            ? BrandColors.success
                                            : null,
                                        dense: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _query.isEmpty
                                        ? '${r.updates} ${r.updates == 1 ? 'update' : 'updates'}'
                                        : r.matches.take(2).join(' … '),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
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
}
