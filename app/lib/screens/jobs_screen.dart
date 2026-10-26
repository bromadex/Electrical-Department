import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../jobs/job_card.dart';
import '../jobs/job_editor.dart';
import '../jobs/job_rules.dart';
import '../jobs/jobs_repository.dart';
import '../requests/requests_screen.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';

class JobsView {
  const JobsView({
    this.filter = JobFilter.active,
    this.areaId,
    this.query = '',
  });

  final JobFilter filter;
  final String? areaId;
  final String query;

  JobsView copyWith({
    JobFilter? filter,
    String? Function()? areaId,
    String? query,
  }) => JobsView(
    filter: filter ?? this.filter,
    areaId: areaId == null ? this.areaId : areaId(),
    query: query ?? this.query,
  );
}

final jobsViewProvider = NotifierProvider<JobsViewNotifier, JobsView>(
  JobsViewNotifier.new,
);

class JobsViewNotifier extends Notifier<JobsView> {
  @override
  JobsView build() {
    ref.watch(currentSiteProvider.select((s) => s?.id));
    return const JobsView();
  }

  void update(JobsView v) => state = v;

  void filter(JobFilter f) => state = state.copyWith(filter: f);
}

/// Opens the Jobs tab with [filter] chosen, e.g. from a number on Home.
void openJobs(BuildContext context, WidgetRef ref, JobFilter filter) {
  ref.read(jobsViewProvider.notifier).filter(filter);
  context.go('/jobs');
}

/// Groups shown when looking at all active jobs.
enum _Group {
  needsSomeone('Needs someone', CupertinoIcons.person_crop_circle_badge_plus),
  inHand('In hand', CupertinoIcons.bolt_fill),
  waiting('Waiting', CupertinoIcons.hourglass);

  const _Group(this.label, this.icon);

  final String label;
  final IconData icon;

  static _Group of(LocalJob j) => switch (j.status) {
    'open' => needsSomeone,
    'waiting' => waiting,
    _ => inHand,
  };
}

/// Jobs tab: search, one row of filters, and the jobs grouped by what they
/// need next.
class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(jobsSyncProvider);
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final view = ref.watch(jobsViewProvider);
    final me = ref.watch(authUserIdProvider);
    final inset = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 720;
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    final areaNames = {for (final a in areas) a.id: a.name};
    final canPost = site != null && session.can('jobs.create', siteId: site.id);
    final side = phone ? Space.md : Space.xl;

    List<LocalJob> matching(JobFilter f) => [
      for (final j in jobs)
        if (matchesFilter(j, f, me: me, areaId: view.areaId, query: view.query))
          j,
    ]..sort(compareJobs);

    final counts = {for (final f in JobFilter.values) f: matching(f).length};
    final shown = matching(view.filter);

    Widget card(LocalJob j) => JobCard(
      key: ValueKey(j.id),
      job: j,
      areaName: areaNames[j.areaId],
      assigneeName: j.assigneeId == null ? null : people[j.assigneeId],
      showStatus: true,
      onTap: () => context.push('/jobs/${j.id}'),
    );

    // Cards flow in columns on wide screens.
    Widget cards(List<LocalJob> list) => LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / 380).floor().clamp(1, 3);
        const gap = Space.sm;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, j) in list.indexed)
              SizedBox(
                width: w,
                child: card(j).entrance(context, index: i.clamp(0, 8)),
              ),
          ],
        );
      },
    );

    final List<Widget> content;
    if (sync.loading && jobs.isEmpty) {
      content = [
        for (var i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: Space.sm),
            child: JobCardSkeleton(),
          ),
      ];
    } else if (shown.isEmpty) {
      content = [
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: EmptyState(
            icon: view.filter == JobFilter.active && view.query.isEmpty
                ? CupertinoIcons.checkmark_seal
                : CupertinoIcons.line_horizontal_3_decrease_circle,
            title: switch (view.filter) {
              _ when view.query.isNotEmpty => 'No jobs match',
              JobFilter.active => 'No open jobs',
              JobFilter.mine => 'Nothing on your list',
              JobFilter.unassigned => 'Every job has someone',
              JobFilter.urgent => 'No urgent jobs',
              JobFilter.overdue => 'Nothing overdue',
              JobFilter.waiting => 'Nothing waiting',
              JobFilter.done => 'No finished jobs yet',
            },
            message: canPost && view.filter == JobFilter.active
                ? 'Tap + to report a fault.'
                : 'Try another filter.',
          ),
        ),
      ];
    } else if (view.filter == JobFilter.active) {
      final groups = {
        for (final g in _Group.values)
          g: [
            for (final j in shown)
              if (_Group.of(j) == g) j,
          ],
      };
      content = [
        for (final g in _Group.values)
          if (groups[g]!.isNotEmpty) ...[
            SectionHeader(
              '${g.label} · ${groups[g]!.length}',
              trailing: Icon(
                g.icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            cards(groups[g]!),
          ],
      ];
    } else {
      content = [const SizedBox(height: Space.sm), cards(shown)];
    }

    return Stack(
      children: [
        RefreshIndicator(
          edgeOffset: inset.top,
          onRefresh: ref.read(jobsSyncProvider.notifier).refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              side,
              inset.top + Space.xs,
              side,
              inset.bottom + 96,
            ),
            children: [
              _SearchRow(areas: areas),
              const SizedBox(height: Space.xs),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in JobFilter.values)
                      if (f == JobFilter.active ||
                          f == view.filter ||
                          counts[f]! > 0)
                        _FilterChip(
                          label: f.label,
                          count: counts[f]!,
                          selected: view.filter == f,
                          color: switch (f) {
                            JobFilter.urgent ||
                            JobFilter.overdue => const Color(0xFFE5484D),
                            JobFilter.unassigned => BrandColors.warning,
                            JobFilter.done => BrandColors.success,
                            _ => Theme.of(context).colorScheme.primary,
                          },
                          onTap: () =>
                              ref.read(jobsViewProvider.notifier).filter(f),
                        ),
                  ],
                ),
              ),
              if (sync.error != null && jobs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    'Offline · showing saved jobs',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ...content,
            ],
          ),
        ),
        if (canPost && !phone)
          Positioned(
            right: side,
            bottom: inset.bottom + Space.lg,
            child: _NewJobButton(
              onTap: () {
                HapticFeedback.lightImpact();
                showJobEditor(context);
              },
            ),
          ),
      ],
    );
  }
}

class _SearchRow extends ConsumerStatefulWidget {
  const _SearchRow({required this.areas});

  final List<LocalArea> areas;

  @override
  ConsumerState<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends ConsumerState<_SearchRow> {
  late final _search = TextEditingController(
    text: ref.read(jobsViewProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(jobsViewProvider);
    final notifier = ref.read(jobsViewProvider.notifier);
    final g = Glass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final isSuper = site != null && session.can('jobs.assign', siteId: site.id);
    final requests = ref.watch(newRequestCountProvider);
    final areaName = widget.areas
        .where((a) => a.id == view.areaId)
        .map((a) => a.name)
        .firstOrNull;

    Widget square(Widget child, {bool on = false}) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: on ? scheme.primary.withValues(alpha: 0.18) : g.fill,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: g.border),
      ),
      child: Center(child: child),
    );

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _search,
              onChanged: (q) => notifier.update(view.copyWith(query: q)),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search jobs',
                prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                suffixIcon: view.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          CupertinoIcons.clear_circled_solid,
                          size: 18,
                        ),
                        onPressed: () {
                          _search.clear();
                          notifier.update(view.copyWith(query: ''));
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
        if (widget.areas.isNotEmpty) ...[
          const SizedBox(width: Space.xs),
          PopupMenuButton<String?>(
            tooltip: areaName ?? 'Filter by area',
            onSelected: (a) => notifier.update(view.copyWith(areaId: () => a)),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All areas')),
              for (final a in widget.areas)
                PopupMenuItem(value: a.id, child: Text(a.name)),
            ],
            child: square(
              Icon(
                view.areaId == null
                    ? CupertinoIcons.map_pin
                    : CupertinoIcons.map_pin_ellipse,
                size: 20,
                color: view.areaId == null ? null : scheme.primary,
              ),
              on: view.areaId != null,
            ),
          ),
        ],
        const SizedBox(width: Space.xs),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (path) => context.push(path),
          itemBuilder: (_) => [
            if (isSuper)
              PopupMenuItem(
                value: '/requests',
                child: ListTile(
                  leading: const Icon(CupertinoIcons.tray_arrow_down),
                  title: const Text('Work requests'),
                  trailing: requests > 0
                      ? Badge(label: Text('$requests'))
                      : null,
                ),
              ),
            if (isSuper)
              const PopupMenuItem(
                value: '/jobs/recurring',
                child: ListTile(
                  leading: Icon(CupertinoIcons.repeat),
                  title: Text('Planned maintenance'),
                ),
              ),
            const PopupMenuItem(
              value: '/assets',
              child: ListTile(
                leading: Icon(CupertinoIcons.gear_alt),
                title: Text('Equipment'),
              ),
            ),
          ],
          child: square(
            Badge(
              isLabelVisible: isSuper && requests > 0,
              label: Text('$requests'),
              child: const Icon(CupertinoIcons.ellipsis, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.emphasized,
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
          ),
        ),
      ),
    );
  }
}

class _NewJobButton extends StatelessWidget {
  const _NewJobButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          gradient: BrandColors.brandGradient,
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: [
            BoxShadow(
              color: BrandColors.maroon.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.add, color: Colors.white),
            SizedBox(width: Space.xs),
            Text(
              'Report a fault',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
