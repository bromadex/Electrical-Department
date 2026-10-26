import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobcards/action_sheets.dart';
import '../jobcards/job_card_tile.dart';
import '../jobcards/models.dart';
import '../jobcards/repository.dart';
import '../../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/page.dart';
import '../ui/status.dart';

/// The user's open assigned job cards, with their role on each. Read live:
/// Version 2 keeps no device copy, so actions always see current data.
final myJobsProvider = FutureProvider.autoDispose<List<JobCard>>((ref) async {
  ref.watch(jobCardsLiveProvider);
  final me = ref.watch(authUserIdProvider);
  final client = ref.watch(supabaseProvider);
  if (me == null) return const [];
  final assignments = await client
      .from('job_assignments')
      .select('job_card_id, role')
      .eq('user_id', me)
      .isFilter('ended_at', null);
  final roles = <String, String>{};
  for (final a in assignments) {
    final id = a['job_card_id'] as String;
    roles[id] = roles[id] == 'responsible'
        ? 'responsible'
        : a['role'] as String;
  }
  if (roles.isEmpty) return const [];
  final rows = await client
      .from('v_job_cards')
      .select()
      .inFilter('id', roles.keys.toList())
      .not('status', 'in', '(closed,cancelled)');
  return [
    for (final r in rows) JobCard({...r, 'my_role': roles[r['id']]}),
  ];
});

class MyJobsScreen extends ConsumerWidget {
  const MyJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(myJobsProvider);

    int byUrgency(JobCard a, JobCard b) {
      final c = (a.isCriticalOpen ? 0 : 1).compareTo(b.isCriticalOpen ? 0 : 1);
      if (c != 0) return c;
      final p = a.priority.index.compareTo(b.priority.index);
      if (p != 0) return p;
      return (a.targetCompletionAt ?? DateTime(9999)).compareTo(
        b.targetCompletionAt ?? DateTime(9999),
      );
    }

    return AppPage(
      title: 'My Assigned Jobs',
      subtitle: 'Work assigned to you, most urgent first',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(myJobsProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsyncView(
            value: jobs,
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.engineering_outlined,
                  title: 'Nothing assigned to you',
                  message: 'Job cards assigned to you appear here.',
                );
              }
              final sorted = [...list]..sort(byUrgency);
              final groups = <(String, List<JobCard>)>[
                (
                  'To accept',
                  [
                    for (final j in sorted)
                      if (j.status == JobStatus.assigned ||
                          j.status == JobStatus.reopened)
                        j,
                  ],
                ),
                (
                  'Ready to start',
                  [
                    for (final j in sorted)
                      if (j.status == JobStatus.accepted) j,
                  ],
                ),
                (
                  'In progress',
                  [
                    for (final j in sorted)
                      if (j.status == JobStatus.inProgress) j,
                  ],
                ),
                (
                  'Waiting / on hold',
                  [
                    for (final j in sorted)
                      if (j.status.isHold) j,
                  ],
                ),
                (
                  'Awaiting engineering review',
                  [
                    for (final j in sorted)
                      if (j.status == JobStatus.awaitingReview) j,
                  ],
                ),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, items) in groups)
                    if (items.isNotEmpty) ...[
                      SectionHeader('$title (${items.length})'),
                      for (final j in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.xs),
                          child: JobCardTile(
                            job: j,
                            onTap: () =>
                                context.go('/v2/job-cards/${j.number}'),
                            trailing: _QuickActions(job: j),
                          ),
                        ),
                    ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The next step for the job, one tap away.
class _QuickActions extends ConsumerStatefulWidget {
  const _QuickActions({required this.job});

  final JobCard job;

  @override
  ConsumerState<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends ConsumerState<_QuickActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final role = j.r['my_role'] as String?;
    final actions = ref.read(jobCardActionsProvider);
    final buttons = <Widget>[];
    switch (j.status) {
      case JobStatus.assigned || JobStatus.reopened:
        buttons.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() => actions.accept(j.id), 'Accepted'),
            icon: const Icon(Icons.task_alt_rounded),
            label: Text(role == 'responsible' ? 'Accept' : 'Acknowledge'),
          ),
        );
      case JobStatus.accepted:
        buttons.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() => actions.startWork(j.id), 'Work started'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start work'),
          ),
        );
      case JobStatus.inProgress:
        if (role == 'responsible') {
          buttons.add(
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => showFormSheet<bool>(
                      context,
                      title: 'Submit for engineering review',
                      child: SubmitSheet(job: j),
                    ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit'),
            ),
          );
        }
        buttons.add(
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => showFormSheet<bool>(
                    context,
                    title: 'Pause work',
                    child: PauseSheet(job: j),
                  ),
            icon: const Icon(Icons.pause_rounded),
            label: const Text('Pause'),
          ),
        );
        // Starting is safe to repeat: it opens my timer only if it is not
        // already running.
        buttons.add(
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => actions.startWork(j.id),
                    'Your timer is running',
                  ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start my timer'),
          ),
        );
      case _ when j.status.isHold:
        buttons.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() => actions.startWork(j.id), 'Work resumed'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Resume'),
          ),
        );
      default:
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Wrap(spacing: Space.xs, runSpacing: Space.xs, children: buttons),
    );
  }
}
