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
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';

class BoardView {
  const BoardView({
    this.filter = JobFilter.all,
    this.areaId,
    this.query = '',
    this.status,
  });

  final JobFilter filter;
  final String? areaId;
  final String query;

  /// Phone only: the status tab (null = all active jobs).
  final JobStatus? status;

  BoardView copyWith({
    JobFilter? filter,
    String? Function()? areaId,
    String? query,
    JobStatus? Function()? status,
  }) => BoardView(
    filter: filter ?? this.filter,
    areaId: areaId == null ? this.areaId : areaId(),
    query: query ?? this.query,
    status: status == null ? this.status : status(),
  );
}

final boardViewProvider = NotifierProvider<BoardViewNotifier, BoardView>(
  BoardViewNotifier.new,
);

class BoardViewNotifier extends Notifier<BoardView> {
  @override
  BoardView build() {
    ref.watch(currentSiteProvider.select((s) => s?.id));
    return const BoardView();
  }

  void update(BoardView v) => state = v;
}

/// Jobs board: list with status tabs on phones, columns on wide screens.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(jobsSyncProvider);
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final view = ref.watch(boardViewProvider);
    final me = ref.watch(authUserIdProvider);
    final inset = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 720;
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    final areaNames = {for (final a in areas) a.id: a.name};
    final canPost = site != null && session.can('jobs.create', siteId: site.id);

    final visible = [
      for (final j in jobs)
        if (j.status != 'cancelled' &&
            matchesFilter(
              j,
              view.filter,
              me: me,
              areaId: view.areaId,
              query: view.query,
            ))
          j,
    ]..sort(compareJobs);

    final byStatus = {
      for (final s in JobStatus.board)
        s: [
          for (final j in visible)
            if (JobStatus.parse(j.status) == s) j,
        ],
    };

    void open(LocalJob j) => context.push('/jobs/${j.id}');
    Widget card(LocalJob j, {bool showStatus = false}) => JobCard(
      key: ValueKey(j.id),
      job: j,
      areaName: areaNames[j.areaId],
      assigneeName: j.assigneeId == null ? null : people[j.assigneeId],
      showStatus: showStatus,
      onTap: () => open(j),
    );

    final firstLoad = sync.loading && jobs.isEmpty;
    final side = phone ? Space.md : Space.xl;

    final controls = Padding(
      padding: EdgeInsets.fromLTRB(side, inset.top + Space.xs, side, 0),
      child: _Controls(areas: areas, total: visible.length),
    );

    final Widget body;
    if (firstLoad) {
      body = ListView(
        padding: EdgeInsets.fromLTRB(side, Space.md, side, 0),
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: Space.sm),
              child: JobCardSkeleton(),
            ),
        ],
      );
    } else if (phone) {
      final shown = view.status == null
          ? [
              for (final j in visible)
                if (j.status != 'done') j,
            ]
          : byStatus[view.status]!;
      body = Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: side, vertical: 6),
              children: [
                _StatusChip(
                  label: 'Active',
                  count: visible.where((j) => j.status != 'done').length,
                  selected: view.status == null,
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => ref
                      .read(boardViewProvider.notifier)
                      .update(view.copyWith(status: () => null)),
                ),
                for (final s in JobStatus.board)
                  _StatusChip(
                    label: s.label,
                    count: byStatus[s]!.length,
                    selected: view.status == s,
                    color: s.color,
                    onTap: () => ref
                        .read(boardViewProvider.notifier)
                        .update(view.copyWith(status: () => s)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: ref.read(jobsSyncProvider.notifier).refresh,
              child: shown.isEmpty
                  ? _Empty(canPost: canPost, filtered: jobs.isNotEmpty)
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        Space.xs,
                        side,
                        inset.bottom + 80,
                      ),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) => card(
                        shown[i],
                        showStatus: view.status == null,
                      ).entrance(context, index: i.clamp(0, 8)),
                    ),
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: ref.read(jobsSyncProvider.notifier).refresh,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(side, Space.md, side, Space.lg),
          children: [
            for (final (i, s) in JobStatus.board.indexed)
              Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: SizedBox(
                  width: ((width - 380) / 5).clamp(250.0, 340.0),
                  child: _Column(
                    status: s,
                    jobs: byStatus[s]!,
                    card: card,
                  ).entrance(context, index: i, dy: 20),
                ),
              ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            controls,
            if (sync.error != null && jobs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'Offline · showing saved jobs',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            Expanded(child: body),
          ],
        ),
        if (canPost)
          Positioned(
            right: side,
            bottom: inset.bottom + (phone ? Space.md : Space.lg),
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

class _Controls extends ConsumerStatefulWidget {
  const _Controls({required this.areas, required this.total});

  final List<LocalArea> areas;
  final int total;

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  late final _search = TextEditingController(
    text: ref.read(boardViewProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(boardViewProvider);
    final notifier = ref.read(boardViewProvider.notifier);
    final g = Glass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final isSuper = site != null && session.can('jobs.assign', siteId: site.id);
    final areaName = widget.areas
        .where((a) => a.id == view.areaId)
        .map((a) => a.name)
        .firstOrNull;

    final search = SizedBox(
      height: 44,
      child: TextField(
        controller: _search,
        onChanged: (q) => notifier.update(view.copyWith(query: q)),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search jobs or J- codes',
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
    );

    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in JobFilter.values)
          ChoiceChip(
            label: Text(f.label),
            selected: view.filter == f,
            showCheckmark: false,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              notifier.update(view.copyWith(filter: f));
            },
            selectedColor: scheme.primary.withValues(alpha: 0.18),
            backgroundColor: g.fill,
            side: BorderSide(color: g.border),
          ),
        if (widget.areas.isNotEmpty)
          PopupMenuButton<String?>(
            tooltip: 'Filter by area',
            onSelected: (a) => notifier.update(view.copyWith(areaId: () => a)),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All areas')),
              for (final a in widget.areas)
                PopupMenuItem(value: a.id, child: Text(a.name)),
            ],
            child: Chip(
              avatar: const Icon(CupertinoIcons.map_pin, size: 16),
              label: Text(areaName ?? 'All areas'),
              backgroundColor: view.areaId == null
                  ? g.fill
                  : scheme.primary.withValues(alpha: 0.18),
              side: BorderSide(color: g.border),
            ),
          ),
        ActionChip(
          avatar: const Icon(CupertinoIcons.gear_alt, size: 16),
          label: const Text('Assets'),
          onPressed: () => context.push('/assets'),
          backgroundColor: g.fill,
          side: BorderSide(color: g.border),
        ),
        if (isSuper)
          ActionChip(
            avatar: const Icon(CupertinoIcons.repeat, size: 16),
            label: const Text('Recurring'),
            onPressed: () => context.push('/jobs/recurring'),
            backgroundColor: g.fill,
            side: BorderSide(color: g.border),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 900
          ? Row(
              children: [
                SizedBox(width: 320, child: search),
                const SizedBox(width: Space.md),
                Expanded(child: chips),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: Space.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                ),
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
      padding: const EdgeInsets.only(right: 6),
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.emphasized,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : g.fill,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : g.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedCount(
                value: count,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.jobs, required this.card});

  final JobStatus status;
  final List<LocalJob> jobs;
  final Widget Function(LocalJob) card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: g.fillInset,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, Space.sm),
            child: Row(
              children: [
                Icon(status.icon, size: 18, color: status.color),
                const SizedBox(width: Space.xs),
                Text(status.label, style: theme.textTheme.titleSmall),
                const Spacer(),
                Pill(label: '${jobs.length}', color: status.color, dense: true),
              ],
            ),
          ),
          Expanded(
            child: jobs.isEmpty
                ? Center(
                    child: Text(
                      'Nothing here',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Space.sm),
                    itemBuilder: (context, i) =>
                        card(jobs[i]).entrance(context, index: i.clamp(0, 6)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canPost, required this.filtered});

  final bool canPost;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        const SizedBox(height: Space.xl),
        Center(
          child: EmptyState(
            icon: filtered
                ? CupertinoIcons.line_horizontal_3_decrease_circle
                : CupertinoIcons.checkmark_seal,
            title: filtered ? 'No jobs match' : 'No jobs yet',
            message: filtered
                ? 'Try another filter or status.'
                : canPost
                ? 'Post the first job with the + button.'
                : 'Jobs posted at this site will appear here.',
          ),
        ),
      ],
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
              'New job',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    ).entrance(context, index: 3);
  }
}
