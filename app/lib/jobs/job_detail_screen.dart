import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../documents/job_documents_panel.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'job_editor.dart';
import 'job_rules.dart';
import 'jobs_repository.dart';
import 'media.dart';
import '../widgets/app_back_button.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(id)).value;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/jobs'),
        title: Text(job?.code ?? 'Job'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: job == null
            ? Center(
                child: EmptyState(
                  icon: CupertinoIcons.doc_text_search,
                  title: 'Job not found',
                  message: 'It may be at another site, or not synced to this device yet.',
                  action: TextButton(
                    onPressed: ref.read(jobsSyncProvider.notifier).refresh,
                    child: const Text('Refresh'),
                  ),
                ),
              )
            : _Body(job: job, theme: theme),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.job, required this.theme});

  final LocalJob job;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final detail =
        ref.watch(jobDetailProvider(job.id)).value ?? const JobDetail();
    final actions = jobActions(job, me, session.perms);
    final status = JobStatus.parse(job.status);
    final priority = JobPriority.parse(job.priority);
    final area = session.areas.where((a) => a.id == job.areaId).firstOrNull;
    final site = session.siteById(job.siteId);
    final asset = job.assetId == null
        ? null
        : ref.watch(assetProvider(job.assetId!)).value;
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final header = Hero(
      tag: 'job-${job.id}',
      child: SurfaceCard(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                Pill(
                  label: status.label,
                  color: status.color,
                  icon: status.icon,
                ),
                if (priority != JobPriority.normal)
                  Pill(label: priority.label, color: priority.color),
                if (isOverdue(job))
                  Pill(label: 'Overdue', color: JobPriority.urgent.color),
                if (job.maintenanceType == 'preventive')
                  const Pill(
                    label: 'Planned maintenance',
                    icon: CupertinoIcons.calendar_badge_plus,
                  ),
                if (job.pending)
                  const Pill(
                    label: 'Waiting to sync',
                    icon: CupertinoIcons.cloud_upload,
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(job.title, style: theme.textTheme.headlineSmall),
            if (job.description != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                job.description!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (job.isolationRequired &&
                status != JobStatus.done &&
                status != JobStatus.cancelled) ...[
              const SizedBox(height: Space.sm),
              Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: JobPriority.urgent.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.lock_fill,
                      color: JobPriority.urgent.color,
                    ),
                    const SizedBox(width: Space.sm),
                    const Expanded(
                      child: Text(
                        'Isolate, lock out and tag out before work starts. '
                        'Test for dead.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (status == JobStatus.waiting && job.waitingReason != null) ...[
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Icon(CupertinoIcons.hourglass, size: 16, color: status.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      job.waitingReason!,
                      style: TextStyle(color: status.color),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.md),
            _Facts(
              facts: [
                (
                  CupertinoIcons.location_solid,
                  [site?.name, area?.name].nonNulls.join(' · '),
                ),
                if (asset != null)
                  (CupertinoIcons.gear_alt, '${asset.tag} · ${asset.name}'),
                if (job.dueAt != null)
                  (
                    CupertinoIcons.calendar,
                    '${MaterialLocalizations.of(context).formatMediumDate(job.dueAt!)} '
                        '${TimeOfDay.fromDateTime(job.dueAt!).format(context)}'
                        ' (${relativeTime(job.dueAt!)})',
                  ),
                (
                  CupertinoIcons.person,
                  'Posted by ${people[job.createdBy] ?? 'someone'} · ${relativeTime(job.createdAt)}',
                ),
                (
                  CupertinoIcons.wrench,
                  job.assigneeId == null
                      ? 'Not assigned yet'
                      : 'With ${people[job.assigneeId] ?? 'someone'}',
                ),
              ],
            ),
            if (asset != null) ...[
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: () => context.push('/assets/${asset.id}'),
                icon: const Icon(CupertinoIcons.gear_alt),
                label: Text('${asset.tag} history'),
              ),
            ],
            if (job.lat != null && job.lng != null) ...[
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: () => openMap(job.lat!, job.lng!),
                icon: const Icon(CupertinoIcons.map),
                label: const Text('Open location in Maps'),
              ),
            ],
            if (job.closeNote != null && status == JobStatus.done) ...[
              const SizedBox(height: Space.md),
              Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: BrandColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      color: BrandColors.success,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(job.closeNote!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final actionBar = _Actions(job: job, actions: actions);
    final photos = _Photos(
      job: job,
      detail: detail,
      canAdd:
          session.can('jobs.create', siteId: job.siteId) ||
          session.can('jobs.close', siteId: job.siteId),
    );
    final comments = _Comments(
      job: job,
      detail: detail,
      people: people,
      me: me,
    );
    final history = _History(jobId: job.id);

    final documents = JobDocumentsPanel(
      job: job,
      canAttach:
          job.createdBy == me ||
          job.assigneeId == me ||
          session.can('jobs.assign', siteId: job.siteId),
    );

    final left = [header, if (actions.isNotEmpty) actionBar, photos, documents];
    final right = [comments, history];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.md,
        top + Space.md,
        Space.md,
        MediaQuery.paddingOf(context).bottom + Space.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _stack(context, left)),
                      const SizedBox(width: Space.md),
                      Expanded(
                        flex: 2,
                        child: _stack(context, right, offset: 3),
                      ),
                    ],
                  )
                : _stack(context, [...left, ...right]),
          ),
        ),
      ],
    );
  }

  Widget _stack(BuildContext context, List<Widget> items, {int offset = 0}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in items.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: w.entrance(context, index: offset + i),
            ),
        ],
      );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<(IconData, String)> facts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final (icon, text) in facts)
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.job, required this.actions});

  final LocalJob job;
  final Set<JobAction> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.read(jobActionsProvider);
    void done(String msg) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    final primary = <Widget>[
      if (actions.contains(JobAction.take))
        FilledButton.icon(
          onPressed: () async {
            await a.take(job);
            done("It's yours — ${job.code ?? 'job'} taken");
          },
          icon: const Icon(CupertinoIcons.hand_raised_fill),
          label: const Text("I'll take it"),
        ),
      if (actions.contains(JobAction.start))
        FilledButton.icon(
          onPressed: () async {
            if (job.isolationRequired) {
              final ok = await showSafetyCheck(context, job);
              if (ok != true) return;
            }
            await a.setStatus(job, JobStatus.inProgress);
            done('Started');
          },
          icon: const Icon(CupertinoIcons.play_fill),
          label: const Text('Start'),
        ),
      if (actions.contains(JobAction.resume))
        FilledButton.icon(
          onPressed: () async {
            await a.setStatus(job, JobStatus.inProgress);
            done('Back in progress');
          },
          icon: const Icon(CupertinoIcons.play_fill),
          label: const Text('Resume'),
        ),
      if (actions.contains(JobAction.close))
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: BrandColors.success),
          onPressed: () async {
            final ok = await showCloseJob(context, job);
            if (ok ?? false) done('${job.code ?? 'Job'} closed. Nice work!');
          },
          icon: const Icon(CupertinoIcons.checkmark_seal_fill),
          label: const Text('Close job'),
        ),
    ];

    final secondary = <Widget>[
      if (actions.contains(JobAction.wait))
        OutlinedButton.icon(
          onPressed: () async {
            final r = await askReason(
              context,
              title: 'Waiting for…',
              hint: 'e.g. 16A breakers from Harare',
              action: 'Set waiting',
            );
            if (r != null) await a.setStatus(job, JobStatus.waiting, reason: r);
          },
          icon: const Icon(CupertinoIcons.hourglass),
          label: const Text('Waiting'),
        ),
      if (actions.contains(JobAction.assign))
        OutlinedButton.icon(
          onPressed: () => showAssignJob(context, job),
          icon: const Icon(CupertinoIcons.person_badge_plus),
          label: Text(job.assigneeId == null ? 'Assign' : 'Reassign'),
        ),
      if (actions.contains(JobAction.handBack))
        OutlinedButton.icon(
          onPressed: () async {
            await a.setStatus(job, JobStatus.open);
            done('Handed back to the board');
          },
          icon: const Icon(CupertinoIcons.arrow_uturn_left),
          label: const Text('Hand back'),
        ),
      if (actions.contains(JobAction.edit))
        OutlinedButton.icon(
          onPressed: () => showJobEditor(context, job: job),
          icon: const Icon(CupertinoIcons.pencil),
          label: const Text('Edit'),
        ),
      if (actions.contains(JobAction.cancel))
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            final r = await askReason(
              context,
              title: 'Cancel ${job.code ?? 'job'}?',
              hint: 'Why? (optional)',
              action: 'Cancel job',
              required: false,
            );
            if (r != null) {
              await a.setStatus(job, JobStatus.cancelled, reason: r);
              if (context.mounted) Navigator.of(context).maybePop();
            }
          },
          icon: const Icon(CupertinoIcons.xmark_circle),
          label: const Text('Cancel'),
        ),
    ];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in primary)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: b,
            ),
          if (secondary.isNotEmpty)
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: secondary),
        ],
      ),
    );
  }
}

class _Photos extends ConsumerWidget {
  const _Photos({
    required this.job,
    required this.detail,
    required this.canAdd,
  });

  final LocalJob job;
  final JobDetail detail;
  final bool canAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final closed = job.status == 'done' || job.status == 'cancelled';
    Widget column(String kind, String label) {
      final list = detail.photos.where((p) => p.kind == kind).toList();
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: Space.xs),
            if (list.isEmpty)
              Text(
                'None yet',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in list)
                    PhotoThumb(
                      bytes: p.bytes,
                      url: p.url,
                      size: 76,
                      pending: p.bytes != null,
                      onTap: () => showPhoto(context, p),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return PanelCard(
      icon: CupertinoIcons.photo_on_rectangle,
      title: 'Photos',
      trailing: canAdd && !closed
          ? TextButton.icon(
              onPressed: () async {
                final picked = await PhotoPicking.pick(context);
                if (picked.isEmpty) return;
                final kind = job.status == 'open' || job.status == 'taken'
                    ? 'before'
                    : 'after';
                await ref.read(jobActionsProvider).addPhotos(job, kind, picked);
              },
              icon: const Icon(CupertinoIcons.camera, size: 18),
              label: const Text('Add'),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column('before', 'Before'),
          const SizedBox(width: Space.md),
          column('after', 'After'),
        ],
      ),
    );
  }
}

class _Comments extends ConsumerStatefulWidget {
  const _Comments({
    required this.job,
    required this.detail,
    required this.people,
    required this.me,
  });

  final LocalJob job;
  final JobDetail detail;
  final Map<String, String> people;
  final String? me;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    HapticFeedback.lightImpact();
    _text.clear();
    await ref.read(jobActionsProvider).comment(widget.job, body);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = Glass.of(context);
    final comments = widget.detail.comments;
    return PanelCard(
      icon: CupertinoIcons.chat_bubble_2_fill,
      title: 'Comments',
      trailing: Pill(label: '${comments.length}', dense: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                'No comments yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final c in comments)
            Align(
              alignment: c.authorId == widget.me
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.only(bottom: Space.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.authorId == widget.me
                      ? scheme.primary.withValues(alpha: 0.18)
                      : g.fillStrong,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.people[c.authorId] ?? 'Someone'} · '
                      '${c.pending ? 'sending…' : relativeTime(c.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(c.body),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Write a comment',
                  ),
                ),
              ),
              const SizedBox(width: Space.xs),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _send,
                icon: const Icon(CupertinoIcons.arrow_up),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.jobId});

  final String jobId;

  /// Plain words for the fields people change on a job.
  static const _fields = {
    'title': 'the title',
    'description': 'the details',
    'priority': 'the priority',
    'due_at': 'the due time',
    'area_id': 'the area',
    'asset_id': 'the equipment',
    'isolation_required': 'the lock-out rule',
    'maintenance_type': 'the job type',
    'waiting_reason': 'the waiting reason',
    'close_note': 'the closing note',
    'lat': 'the location',
  };

  /// What happened, or null for changes the system makes for itself
  /// (reminder and escalation stamps), which are left out.
  static String? _describe(Map<String, dynamic> h) {
    final table = h['table_name'] as String;
    final action = h['action'] as String;
    final d = Map<String, dynamic>.from(h['details'] as Map? ?? {});
    if (table == 'job_photos') return 'added a ${d['kind'] ?? ''} photo';
    if (table == 'job_comments') return 'commented';
    if (table == 'job_safety_checks') return 'recorded the safety check';
    if (action == 'insert') return 'posted the job';
    if (action == 'archive') return 'archived the job';
    if (d.containsKey('status')) {
      final to = JobStatus.parse((d['status'] as Map)['to'] as String).label;
      return 'moved it to $to';
    }
    if (d.containsKey('assignee_id')) return 'changed who has it';
    final changed = {for (final k in d.keys) ?_fields[k]};
    if (changed.isEmpty) return null;
    final list = changed.toList();
    return 'changed ${list.length == 1 ? list.first : '${list.take(list.length - 1).join(', ')} and ${list.last}'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(jobHistoryProvider(jobId));
    return PanelCard(
      icon: CupertinoIcons.time,
      title: 'History',
      child: history.when(
        loading: () => const Skeleton(height: 40),
        error: (_, _) => Text(
          'History loads when you are online.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        data: (rows) => Column(
          children: [
            for (final h
                in rows.reversed.where((h) => _describe(h) != null).take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${h['user_name']} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: _describe(h)!),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      relativeTime(DateTime.parse(h['at'] as String).toLocal()),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
