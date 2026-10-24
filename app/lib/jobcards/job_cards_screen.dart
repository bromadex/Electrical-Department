import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/data_table.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/status.dart';
import 'job_card_tile.dart';
import 'models.dart';
import 'repository.dart';

class JobCardsScreen extends ConsumerWidget {
  const JobCardsScreen({super.key, required this.query});

  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(siteFilterProvider);
    final filter = JobCardFilter.fromQuery(query, siteId: site);
    final page = ref.watch(jobCardsPageProvider(filter));
    final perms = ref.watch(sessionProvider.select((s) => s.perms));

    void update(JobCardFilter f) {
      final q = f.toQuery();
      context.go(
        Uri(
          path: '/job-cards',
          queryParameters: q.isEmpty ? null : q,
        ).toString(),
      );
    }

    return AppPage(
      title: 'Job Cards',
      subtitle: filter.view.label,
      actions: [
        if (perms.can('jc.register'))
          FilledButton.icon(
            onPressed: () => context.go('/job-cards/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New job card'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(filter: filter, onChanged: update),
          const SizedBox(height: Space.sm),
          Card(
            clipBehavior: Clip.antiAlias,
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
                onSort: (key, asc) =>
                    update(filter.copyWith(sort: key, ascending: asc, page: 0)),
                onTap: (j) => context.go('/job-cards/${j.number}'),
                highlight: (j) => j.isOverdue || j.isCriticalOpen
                    ? AppColors.critical.withValues(alpha: 0.06)
                    : j.sla == SlaState.atRisk
                    ? AppColors.warning.withValues(alpha: 0.07)
                    : null,
                cardBuilder: (j) => JobCardTile(
                  job: j,
                  onTap: () => context.go('/job-cards/${j.number}'),
                ),
                columns: _columns,
              ),
            },
          ),
        ],
      ),
    );
  }

  static final _columns = <TableCol<JobCard>>[
    TableCol('Job card no.', (j) => RecordCode(j.number), sortKey: 'number'),
    TableCol(
      'Received',
      (j) => Text(fmtDateTime(j.receivedAt)),
      sortKey: 'received_at',
    ),
    TableCol(
      'Equipment',
      (j) => SizedBox(
        width: 170,
        child: Text(
          j.equipment ?? '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      sortKey: 'equipment_display',
    ),
    TableCol(
      'Work area',
      (j) => Text(j.place, overflow: TextOverflow.ellipsis),
      sortKey: 'area_name',
    ),
    TableCol(
      'Description',
      (j) => SizedBox(
        width: 220,
        child: Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ),
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
    TableCol(
      'Status',
      (j) => StatusPill(j.status, dense: true),
      sortKey: 'status',
    ),
    TableCol(
      'Technician',
      (j) => Text(j.responsibleName ?? '—'),
      sortKey: 'responsible_name',
    ),
    TableCol('Engineer', (j) => Text(j.assignedByName ?? '—')),
    TableCol(
      'Response',
      (j) => Text(fmtMinutes(j.responseMinutes)),
      numeric: true,
    ),
    TableCol(
      'Elapsed',
      (j) => Text(fmtMinutes(j.elapsedMinutes)),
      numeric: true,
    ),
    TableCol(
      'Target',
      (j) => Text(fmtDateTime(j.targetCompletionAt)),
      sortKey: 'target_completion_at',
    ),
    TableCol(
      'Remaining',
      (j) => Text(
        j.remainingMinutes == null || j.isOverdue
            ? '—'
            : fmtMinutes(j.remainingMinutes),
      ),
      numeric: true,
    ),
    TableCol(
      'Overdue by',
      (j) => Text(
        j.overdueMinutes == null ? '—' : fmtMinutes(j.overdueMinutes),
        style: j.isOverdue
            ? const TextStyle(
                color: AppColors.critical,
                fontWeight: FontWeight.w700,
              )
            : null,
      ),
      numeric: true,
    ),
    TableCol('Closure', (j) => SlaChip(j.sla)),
  ];
}

class _FilterBar extends StatefulWidget {
  const _FilterBar({required this.filter, required this.onChanged});

  final JobCardFilter filter;
  final ValueChanged<JobCardFilter> onChanged;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
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

  Future<void> _pickRange() async {
    final f = widget.filter;
    final now = SiteTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: f.from == null || f.to == null
          ? null
          : DateTimeRange(
              start: SiteTime.local(f.from!),
              end: SiteTime.local(f.to!).subtract(const Duration(days: 1)),
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
    widget.onChanged(f.copyWith(from: start, to: end, page: 0));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    const views = [
      JobCardView.open,
      JobCardView.newJobs,
      JobCardView.awaitingAssignment,
      JobCardView.active,
      JobCardView.waiting,
      JobCardView.critical,
      JobCardView.overdue,
      JobCardView.awaitingReview,
      JobCardView.clarification,
      JobCardView.closed,
      JobCardView.cancelled,
      JobCardView.all,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final v in views)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(v.label),
                    selected: f.view == v,
                    showCheckmark: false,
                    onSelected: (_) =>
                        widget.onChanged(f.copyWith(view: v, page: 0)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search number, equipment, fault, technician…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                          },
                        ),
                ),
              ),
            ),
            for (final p in Priority.values)
              FilterChip(
                label: Text('${p.code} ${p.name}'),
                avatar: Icon(p.icon, size: 16, color: p.color),
                selected: f.priorities.contains(p.code),
                showCheckmark: false,
                onSelected: (on) => widget.onChanged(
                  f.copyWith(
                    priorities: on
                        ? {...f.priorities, p.code}
                        : ({...f.priorities}..remove(p.code)),
                    page: 0,
                  ),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                f.from == null
                    ? 'Received: any date'
                    : 'Received ${fmtDate(f.from)} – ${fmtDate(f.to!.subtract(const Duration(days: 1)))}',
              ),
              onPressed: _pickRange,
            ),
            if (f.from != null ||
                f.priorities.isNotEmpty ||
                f.search.isNotEmpty ||
                f.view != JobCardView.open)
              TextButton.icon(
                onPressed: () {
                  _search.clear();
                  widget.onChanged(const JobCardFilter().copyWith());
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear filters'),
              ),
          ],
        ),
      ],
    );
  }
}
