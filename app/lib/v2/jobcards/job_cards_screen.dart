import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/core_providers.dart';
import '../../services/session_controller.dart';
import '../../ui/motion.dart';
import '../../ui/surfaces.dart';
import '../site_filter.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/data_table.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/status.dart';
import 'job_card_tile.dart';
import 'models.dart';
import 'repository.dart';

/// How many open job cards each quick view holds (for the status chips).
final jobCardCountsProvider = FutureProvider.autoDispose
    .family<Map<JobCardView, int>, String?>((ref, siteId) async {
      ref.watch(jobCardsLiveProvider);
      var q = ref
          .watch(supabaseProvider)
          .from('v_job_cards')
          .select(
            'status, is_new, is_awaiting_assignment, is_active, is_waiting, '
            'is_critical_open, is_overdue, is_awaiting_review',
          )
          .not('status', 'in', '(closed,cancelled)');
      if (siteId != null) q = q.eq('site_id', siteId);
      final rows = await q;
      int count(bool Function(Map<String, dynamic>) test) =>
          rows.where(test).length;
      return {
        JobCardView.open: rows.length,
        JobCardView.newJobs: count((r) => r['is_new'] == true),
        JobCardView.awaitingAssignment: count(
          (r) => r['is_awaiting_assignment'] == true,
        ),
        JobCardView.active: count((r) => r['is_active'] == true),
        JobCardView.waiting: count((r) => r['is_waiting'] == true),
        JobCardView.critical: count((r) => r['is_critical_open'] == true),
        JobCardView.overdue: count((r) => r['is_overdue'] == true),
        JobCardView.awaitingReview: count(
          (r) => r['is_awaiting_review'] == true,
        ),
        JobCardView.clarification: count(
          (r) => r['status'] == 'awaiting_clarification',
        ),
      };
    });

class JobCardsScreen extends ConsumerWidget {
  const JobCardsScreen({super.key, required this.query});

  final Map<String, String> query;

  /// Below this window width the list shows cards instead of a table.
  static const tableFrom = 1100.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteFilterProvider);
    final filter = JobCardFilter.fromQuery(query, siteId: site);
    final page = ref.watch(jobCardsPageProvider(filter));
    final perms = ref.watch(sessionProvider.select((s) => s.perms));
    final width = MediaQuery.sizeOf(context).width;

    void update(JobCardFilter f) {
      final q = f.toQuery();
      context.go(
        Uri(path: '/jobs', queryParameters: q.isEmpty ? null : q).toString(),
      );
    }

    return AppPage(
      title: 'Job Cards',
      subtitle: filter.view.label,
      actions: [
        // Phones start a job card from the + in the bottom bar.
        if (perms.can('jc.register') && width >= Breakpoints.phone)
          FilledButton.icon(
            onPressed: () => context.push('/jobs/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New job card'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchRow(filter: filter, onChanged: update),
          const SizedBox(height: Space.xs),
          _StatusChips(
            filter: filter,
            siteId: site,
            shown: page.value?.total,
            onChanged: update,
          ),
          const SizedBox(height: Space.sm),
          SurfaceCard(
            padding: EdgeInsets.zero,
            radius: Radii.lg,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: switch (page) {
                AsyncError(:final error) when !page.hasValue => ErrorPanel(
                  error: error,
                  onRetry: () => ref.invalidate(jobCardsPageProvider(filter)),
                ),
                _ => PagedTable<JobCard>(
                  loading: page.isLoading,
                  rows: page.value?.rows ?? const [],
                  total: page.value?.total ?? 0,
                  page: filter.page,
                  pageSize: JobCardFilter.pageSize,
                  onPage: (p) => update(filter.copyWith(page: p)),
                  sortKey: filter.sort,
                  ascending: filter.ascending,
                  onSort: (key, asc) => update(
                    filter.copyWith(sort: key, ascending: asc, page: 0),
                  ),
                  onTap: (j) => context.push('/jobs/${j.number}'),
                  highlight: (j) => j.isOverdue || j.isCriticalOpen
                      ? AppColors.critical.withValues(alpha: 0.06)
                      : j.sla == SlaState.atRisk
                      ? AppColors.warning.withValues(alpha: 0.07)
                      : null,
                  cardBelow: tableFrom,
                  cardBuilder: (j) => JobCardTile(
                    job: j,
                    onTap: () => context.push('/jobs/${j.number}'),
                  ),
                  columns: _columns(workArea: width >= 1400),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Most important first; the description takes the free width. The work
  /// area only shows on wide windows.
  static List<TableCol<JobCard>> _columns({required bool workArea}) => [
    TableCol(
      'Priority',
      (j) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PriorityBadge(j.priority),
          if (j.isCriticalOpen) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.report_rounded,
              size: 16,
              color: AppColors.critical,
            ),
          ],
        ],
      ),
      sortKey: 'priority_rank',
    ),
    TableCol('Job card no.', (j) => RecordCode(j.number), sortKey: 'number'),
    TableCol(
      'Description',
      (j) => Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      flex: 3,
    ),
    TableCol(
      'Equipment',
      (j) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          j.equipment ?? '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      sortKey: 'equipment_display',
      flex: 2,
    ),
    if (workArea)
      TableCol(
        'Work area',
        (j) => Text(j.place, maxLines: 2, overflow: TextOverflow.ellipsis),
        sortKey: 'area_name',
        flex: 1.5,
      ),
    TableCol(
      'Status',
      (j) => StatusPill(j.status, dense: true),
      sortKey: 'status',
    ),
    TableCol(
      'Received',
      (j) => Text(fmtDateTime(j.receivedAt)),
      sortKey: 'received_at',
    ),
  ];
}

/// Search, and a Filter button for priority, received date and the closed
/// lists (badge: how many filters are on).
class _SearchRow extends StatefulWidget {
  const _SearchRow({required this.filter, required this.onChanged});

  final JobCardFilter filter;
  final ValueChanged<JobCardFilter> onChanged;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  late final _search = TextEditingController(text: widget.filter.search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      widget.onChanged(widget.filter.copyWith(search: v.trim(), page: 0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final g = Glass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = f.priorities.length + (f.from == null ? 0 : 1);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _search,
              onChanged: (v) {
                setState(() {});
                _onSearch(v);
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search number, equipment, fault, technician',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                          _onSearch('');
                        },
                      ),
                filled: true,
                fillColor: g.fill,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide(color: g.border),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.xs),
        Semantics(
          button: true,
          label: active == 0 ? 'Filter' : 'Filter, $active on',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => _FilterSheet.show(context, f, widget.onChanged),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              decoration: BoxDecoration(
                color: active == 0
                    ? g.fill
                    : scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: g.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    isLabelVisible: active > 0,
                    label: Text('$active'),
                    child: const Icon(Icons.tune_rounded, size: 20),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Filter',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Priority, received date and the lists of finished job cards.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.filter, required this.onChanged});

  final JobCardFilter filter;
  final ValueChanged<JobCardFilter> onChanged;

  static Future<void> show(
    BuildContext context,
    JobCardFilter filter,
    ValueChanged<JobCardFilter> onChanged,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _FilterSheet(filter: filter, onChanged: onChanged),
  );

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late var _f = widget.filter;

  void _set(JobCardFilter f) {
    setState(() => _f = f);
    widget.onChanged(f);
  }

  Future<void> _pickRange() async {
    final now = SiteTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _f.from == null || _f.to == null
          ? null
          : DateTimeRange(
              start: SiteTime.local(_f.from!),
              end: SiteTime.local(_f.to!).subtract(const Duration(days: 1)),
            ),
    );
    if (range == null) return;
    final start = SiteTime.toInstant(
      DateTime(range.start.year, range.start.month, range.start.day),
    );
    final end = SiteTime.toInstant(
      DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1)),
    );
    _set(_f.copyWith(from: start, to: end, page: 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = _f;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: GlassSurface(
          radius: 30,
          strong: true,
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter job cards', style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              const SectionHeader('Priority'),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final p in Priority.values)
                    FilterChip(
                      label: Text('${p.code} ${p.name}'),
                      avatar: Icon(p.icon, size: 16, color: p.color),
                      selected: f.priorities.contains(p.code),
                      showCheckmark: false,
                      onSelected: (on) => _set(
                        f.copyWith(
                          priorities: on
                              ? {...f.priorities, p.code}
                              : ({...f.priorities}..remove(p.code)),
                          page: 0,
                        ),
                      ),
                    ),
                ],
              ),
              const SectionHeader('Received'),
              Wrap(
                spacing: Space.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(
                      f.from == null
                          ? 'Any date'
                          : '${fmtDate(f.from)} – ${fmtDate(f.to!.subtract(const Duration(days: 1)))}',
                    ),
                    onPressed: _pickRange,
                  ),
                  if (f.from != null)
                    ActionChip(
                      label: const Text('Any date'),
                      onPressed: () => _set(
                        JobCardFilter.fromQuery({
                          ...f.toQuery()
                            ..remove('from')
                            ..remove('to')
                            ..remove('page'),
                        }, siteId: f.siteId),
                      ),
                    ),
                ],
              ),
              const SectionHeader('Finished and other lists'),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final v in const [
                    JobCardView.closedToday,
                    JobCardView.closed,
                    JobCardView.cancelled,
                    JobCardView.outOfService,
                    JobCardView.all,
                  ])
                    ChoiceChip(
                      label: Text(v.label),
                      selected: f.view == v,
                      showCheckmark: false,
                      onSelected: (_) => _set(f.copyWith(view: v, page: 0)),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _set(JobCardFilter(siteId: f.siteId));
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Clear filters'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One scrolling row of quick views with their counts. Empty ones are
/// hidden, except "All open" and the one that is selected.
class _StatusChips extends ConsumerWidget {
  const _StatusChips({
    required this.filter,
    required this.siteId,
    required this.shown,
    required this.onChanged,
  });

  final JobCardFilter filter;
  final String? siteId;

  /// How many the list shows now (the count for views not in [_views]).
  final int? shown;
  final ValueChanged<JobCardFilter> onChanged;

  static const _views = [
    JobCardView.open,
    JobCardView.newJobs,
    JobCardView.awaitingAssignment,
    JobCardView.active,
    JobCardView.waiting,
    JobCardView.critical,
    JobCardView.overdue,
    JobCardView.awaitingReview,
    JobCardView.clarification,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(jobCardCountsProvider(siteId)).value ?? const {};
    final scheme = Theme.of(context).colorScheme;
    final views = [
      for (final v in _views)
        if (v == JobCardView.open || v == filter.view || (counts[v] ?? 0) > 0)
          v,
      if (!_views.contains(filter.view)) filter.view,
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final v in views)
            _FilterChip(
              label: v.label,
              count: counts[v] ?? (v == filter.view ? shown : null),
              selected: filter.view == v,
              color: switch (v) {
                JobCardView.critical ||
                JobCardView.overdue => AppColors.critical,
                JobCardView.awaitingAssignment ||
                JobCardView.clarification => AppColors.warning,
                JobCardView.awaitingReview => AppColors.review,
                _ => scheme.primary,
              },
              onTap: () => onChanged(filter.copyWith(view: v, page: 0)),
            ),
        ],
      ),
    );
  }
}

/// The main app's filter chip (screens/jobs_screen.dart): glass when off,
/// filled with its colour when on, with its count.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: count == null ? label : '$label $count',
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : g.fill,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: selected ? color : g.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: selected ? Colors.white : null,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
