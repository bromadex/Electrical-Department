import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/core_providers.dart';
import '../../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'action_sheets.dart';
import 'models.dart';
import 'repository.dart';
import 'work.dart';

/// Live work clock: my running session, and the job's active, labour,
/// waiting and elapsed time, kept apart (spec section 6).
class WorkClock extends ConsumerStatefulWidget {
  const WorkClock({super.key, required this.job, required this.work});

  final JobCard job;
  final JobWork work;

  @override
  ConsumerState<WorkClock> createState() => _WorkClockState();
}

class _WorkClockState extends ConsumerState<WorkClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = widget.job;
    final work = widget.work;
    final me = ref.watch(authUserIdProvider);
    final now = DateTime.now();
    final mine = work.runningFor(me);
    final live = work.liveTimes(now, open: job.status.isOpen);
    final working = [
      for (final s in work.sessions)
        if (s.running) s.name,
    ];
    final deadlineMoved =
        work.effectiveDeadline != null &&
        work.deadline != null &&
        work.effectiveDeadline!.isAfter(work.deadline!);

    return Panel(
      title: mine != null ? 'You are working on this job' : 'Work time',
      subtitle: working.isEmpty
          ? (work.openWait != null
                ? 'On hold since ${fmtDateTime(work.openWait!.startedAt)}'
                : 'Nobody is working on it right now')
          : 'Working now: ${working.join(', ')}',
      icon: mine != null ? Icons.timer_rounded : Icons.timer_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mine != null) ...[
            Text(
              fmtClock(
                work.serverTime(now).difference(mine.startedAt).inSeconds,
              ),
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Your session since ${fmtTime(mine.startedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.sm),
          ],
          ResponsiveGrid(
            minItemWidth: 150,
            children: [
              StatTile(
                label: 'Active work',
                value: fmtMinutes(live.active / 60),
                caption: 'time anyone was working',
                icon: Icons.construction_rounded,
              ),
              StatTile(
                label: 'Labour',
                value: fmtHours(live.labour),
                caption: 'person-hours, everyone added',
                icon: Icons.groups_outlined,
              ),
              StatTile(
                label: 'Waiting',
                value: fmtMinutes(live.wait / 60),
                caption: work.time.slaExcludedSeconds > 0
                    ? '${fmtMinutes(work.time.slaExcludedSeconds / 60)} not counted'
                    : 'on hold',
                icon: Icons.hourglass_bottom_rounded,
              ),
              StatTile(
                label: 'Elapsed',
                value: fmtMinutes(live.elapsed / 60),
                caption: 'since received ${fmtDayMonth(job.receivedAt)}',
                icon: Icons.schedule_rounded,
              ),
              StatTile(
                label: 'Deadline',
                value: fmtDateTime(work.effectiveDeadline),
                caption: deadlineMoved
                    ? 'moved by waits not counted'
                    : '${work.time.pauseCount} pauses',
                icon: Icons.flag_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Work tab: sessions, waits, time corrections and the work log.
class WorkTab extends ConsumerWidget {
  const WorkTab({
    super.key,
    required this.job,
    required this.work,
    required this.extras,
  });

  final JobCard job;
  final JobWork work;
  final JobCardExtras extras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final me = ref.watch(authUserIdProvider);
    final engineer = session.can('jc.assign', siteId: job.siteId);
    final onTeam = extras.current.any((a) => a.userId == me);
    final canLog =
        job.status.isOpen &&
        (onTeam || engineer || session.can('jc.review', siteId: job.siteId));
    final people = <String, String>{
      for (final a in extras.assignments) a.userId: a.personName,
    };

    Future<void> sheet(String title, Widget child) =>
        showFormSheet<bool>(context, title: title, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Work log',
          trailing: canLog
              ? TextButton.icon(
                  onPressed: () =>
                      sheet('Add to the work log', WorkRecordSheet(job: job)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add entry'),
                )
              : null,
        ),
        if (work.records.isEmpty)
          Text(
            'Nothing logged yet. Record symptoms, diagnosis, readings, tests, '
            'parts used and recommendations as the work goes on.',
            style: theme.textTheme.bodyMedium,
          )
        else
          for (final r in work.records.reversed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Pill(label: workRecordLabel(r.kind), dense: true),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text(
                            '${r.author} · ${fmtDateTime(r.createdAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (r.body != null) ...[
                      const SizedBox(height: 4),
                      CopyableText(r.body!),
                    ],
                    if (r.readings.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: 4,
                        children: [
                          for (final x in r.readings)
                            Pill(
                              label: x.toString(),
                              dense: true,
                              color: AppColors.info,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        SectionHeader(
          'Work sessions',
          trailing: engineer && people.isNotEmpty
              ? TextButton.icon(
                  onPressed: () => sheet(
                    'Enter missed work time',
                    CorrectTimeSheet(
                      job: job,
                      people: [
                        for (final e in people.entries) (e.key, e.value),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.more_time_rounded),
                  label: const Text('Enter missed time'),
                )
              : null,
        ),
        if (work.sessions.isEmpty)
          Text('No work recorded yet.', style: theme.textTheme.bodyMedium)
        else
          for (final s in work.sessions.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.running ? Icons.timer_rounded : Icons.timer_off_outlined,
                color: s.running ? AppColors.success : null,
              ),
              title: Text(
                '${s.name} · ${fmtDateTime(s.startedAt)} → '
                '${s.running ? 'now' : fmtTime(s.endedAt)}',
              ),
              subtitle: Text(
                [
                  if (!s.running)
                    fmtMinutes(
                      s.endedAt!.difference(s.startedAt).inSeconds / 60,
                    ),
                  if (s.endReason != null) _endReason(s),
                  if (s.pauseNote != null) s.pauseNote!,
                  if (s.corrected) 'corrected',
                ].join(' · '),
              ),
              trailing: engineer
                  ? IconButton(
                      tooltip: 'Correct the times',
                      icon: const Icon(Icons.edit_calendar_outlined),
                      onPressed: () => sheet(
                        'Correct work time',
                        CorrectTimeSheet(job: job, session: s),
                      ),
                    )
                  : null,
            ),
        if (work.waits.isNotEmpty) ...[
          const SectionHeader('Waiting'),
          for (final w in work.waits.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(JobStatus.fromDb(w.holdStatus).icon),
              title: Text(
                '${JobStatus.fromDb(w.holdStatus).label} · '
                '${fmtDateTime(w.startedAt)} → ${w.endedAt == null ? 'now' : fmtTime(w.endedAt)}',
              ),
              subtitle: Text(
                [
                  if (w.note != null) w.note!,
                  w.countsTowardSla
                      ? 'counts toward the deadline'
                      : 'not counted toward the deadline',
                  if (w.slaReason != null) w.slaReason!,
                ].join(' · '),
              ),
              trailing: engineer
                  ? TextButton(
                      onPressed: () => _changeWaitSla(context, ref, w),
                      child: Text(
                        w.countsTowardSla ? 'Don\'t count' : 'Count it',
                      ),
                    )
                  : null,
            ),
        ],
        if (work.corrections.isNotEmpty) ...[
          const SectionHeader('Time corrections'),
          for (final c in work.corrections.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_edu_outlined),
              title: Text(
                '${c.person}: ${c.oldStartedAt == null ? 'added' : '${fmtTime(c.oldStartedAt)}–${fmtTime(c.oldEndedAt)}'}'
                ' → ${fmtTime(c.newStartedAt)}–${fmtTime(c.newEndedAt)}',
              ),
              subtitle: Text('${c.reason} · by ${c.by}, ${fmtDateTime(c.at)}'),
            ),
        ],
      ],
    );
  }

  static String _endReason(WorkSession s) => switch (s.endReason) {
    'pause' => 'paused (${humanize(s.pauseReason)})',
    'hold' => 'stopped: job on hold',
    'submitted' => 'stopped: submitted',
    'reassigned' => 'came off the job',
    'corrected' => 'entered by an engineer',
    'cancelled' => 'job cancelled',
    _ => 'stopped',
  };

  Future<void> _changeWaitSla(
    BuildContext context,
    WidgetRef ref,
    JobWait w,
  ) async {
    final reason = await askReason(
      context,
      title: w.countsTowardSla
          ? 'Stop counting this wait toward the deadline'
          : 'Count this wait toward the deadline',
      label: 'Reason',
      confirm: 'Save',
      message: w.countsTowardSla
          ? 'The deadline moves later by the length of this wait. It is still '
                'shown in the elapsed time and recorded in the audit trail.'
          : null,
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(jobCardActionsProvider)
          .setWaitSla(w.id, counts: !w.countsTowardSla, reason: reason);
      if (context.mounted) showSnack(context, 'Saved');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Safety tab: the checklist for this job card, before and after the work.
class SafetyTab extends ConsumerStatefulWidget {
  const SafetyTab({
    super.key,
    required this.job,
    required this.work,
    required this.canRecord,
  });

  final JobCard job;
  final JobWork work;
  final bool canRecord;

  @override
  ConsumerState<SafetyTab> createState() => _SafetyTabState();
}

class _SafetyTabState extends ConsumerState<SafetyTab> {
  final _done = <String, bool>{};
  final _refs = <String, TextEditingController>{};
  bool _busy = false;

  TextEditingController _ref(SafetyItem i) => _refs.putIfAbsent(
    i.id,
    () => TextEditingController(text: i.last?.reference),
  );

  @override
  void dispose() {
    for (final c in _refs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (final i in widget.work.safety.items) {
      final done = _done[i.id];
      final ref = _refs[i.id]?.text.trim();
      final changedRef = ref != null && ref != (i.last?.reference ?? '');
      if (done == null && !changedRef) continue;
      items.add({
        'item_id': i.id,
        'confirmed': done ?? i.last?.confirmed ?? false,
        'reference': ref,
      });
    }
    if (items.isEmpty) {
      showSnack(context, 'Nothing changed.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(jobCardActionsProvider).recordSafety(widget.job.id, items);
      if (!mounted) return;
      _done.clear();
      showSnack(context, 'Safety checks recorded');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safety = widget.work.safety;
    Widget group(String phase, String title) {
      final items = [
        for (final i in safety.items)
          if (i.phase == phase) i,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          for (final i in items)
            Opacity(
              opacity: i.applies ? 1 : 0.55,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _done[i.id] ?? i.last?.confirmed ?? false,
                      onChanged: widget.canRecord
                          ? (v) => setState(() => _done[i.id] = v ?? false)
                          : null,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.label + (i.applies ? '' : ' (not needed here)'),
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (i.last != null)
                            Text(
                              '${i.last!.confirmed ? 'Done' : 'Not done'} · '
                              '${i.last!.by}, ${fmtDateTime(i.last!.at)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          if (i.needsReference)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: TextField(
                                controller: _ref(i),
                                enabled: widget.canRecord,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Reference number',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: const Text(
            'These checks are a record. They do not isolate equipment or make it safe. '
            'Follow the site\'s isolation, lockout/tagout, permit and emergency procedures.',
          ),
        ),
        if (safety.required) ...[
          const SizedBox(height: Space.sm),
          Text(
            safety.missingBefore.isEmpty
                ? 'Site policy: the pre-work checks are recorded; work can start.'
                : 'Site policy: work cannot start until the pre-work checks are recorded.',
            style: theme.textTheme.titleSmall,
          ),
        ],
        group('before', 'Before the work'),
        group('after', 'After the work'),
        if (widget.canRecord)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save safety checks'),
            ),
          ),
      ],
    );
  }
}

/// Closure tab: the frozen metrics, every submission and every review.
class ClosureTab extends ConsumerWidget {
  const ClosureTab({
    super.key,
    required this.job,
    required this.work,
    required this.closures,
  });

  final JobCard job;
  final JobWork? work;
  final List<JobClosure> closures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final submissions = work?.submissions ?? const <Submission>[];
    final reviews = work?.reviews ?? const <Review>[];
    if (submissions.isEmpty && closures.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_outlined,
        title: 'Not submitted yet',
        message: 'When the work is done, the responsible person submits it here for engineering review.',
      );
    }
    String met(bool? v) => v == null ? '—' : (v ? 'Yes' : 'No');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in closures.reversed)
          Panel(
            title: 'Closed ${fmtDateTime(c.closedAt)}',
            subtitle: [
              if (c.performerName != null) 'Work by ${c.performerName}',
              if (c.verifierName != null) 'verified by ${c.verifierName}',
              if (c.selfApproved) 'self-approved',
              if (c.legacy) 'from the jobs board',
            ].join(' · '),
            icon: Icons.verified_rounded,
            child: c.hasMetrics
                ? ResponsiveGrid(
                    minItemWidth: 170,
                    children: [
                      StatTile(
                        label: 'Elapsed',
                        value: fmtMinutes(c.elapsedMinutes),
                        caption: 'from receipt to closure',
                      ),
                      StatTile(
                        label: 'Active work',
                        value: fmtMinutes(c.activeMinutes),
                      ),
                      StatTile(
                        label: 'Labour',
                        value: fmtHours((c.labourMinutes ?? 0) * 60),
                        caption: c.labourHoursReported == null
                            ? 'recorded'
                            : '${c.labourHoursReported} h reported',
                      ),
                      StatTile(
                        label: 'On hold',
                        value: fmtMinutes(c.waitMinutes),
                        caption: (c.slaExcludedMinutes ?? 0) > 0
                            ? '${fmtMinutes(c.slaExcludedMinutes)} not counted'
                            : null,
                      ),
                      StatTile(label: 'Pauses', value: '${c.pauseCount ?? 0}'),
                      StatTile(
                        label: 'Response',
                        value: fmtMinutes(c.responseMinutes),
                        caption: 'target met: ${met(c.responseTargetMet)}',
                      ),
                      StatTile(
                        label: 'Completion target met',
                        value: met(c.completionTargetMet),
                      ),
                      StatTile(
                        label: 'Equipment after',
                        value: humanize(c.equipmentStateAfter),
                      ),
                    ],
                  )
                : Text(c.summary ?? '—'),
          ),
        if (submissions.isNotEmpty) ...[
          SectionHeader('Submissions (${submissions.length})'),
          for (final (i, s) in submissions.indexed.toList().reversed)
            Panel(
              title: 'Submission ${i + 1}',
              icon: Icons.send_outlined,
              child: SubmissionDetails(submission: s),
            ),
        ],
        if (reviews.isNotEmpty) ...[
          SectionHeader('Engineering reviews (${reviews.length})'),
          for (final r in reviews.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (r.decision) {
                  'approve' => Icons.verified_outlined,
                  'reject' => Icons.undo_rounded,
                  _ => Icons.help_outline_rounded,
                },
                color: switch (r.decision) {
                  'approve' => AppColors.success,
                  'reject' => AppColors.warning,
                  _ => AppColors.info,
                },
              ),
              title: Text(
                '${switch (r.decision) {
                  'approve' => r.selfApproved ? 'Approved (self-approved)' : 'Approved',
                  'reject' => 'Returned for more work',
                  _ => 'Question',
                }} · ${r.reviewer} · ${fmtDateTime(r.createdAt)}',
              ),
              subtitle: Text(
                [
                  if (r.notes != null) r.notes!,
                  if (r.answer != null)
                    'Answer (${r.answeredBy ?? 'technician'}): ${r.answer}',
                  if (r.isOpenQuestion) 'Waiting for an answer',
                  if (r.followUpNumber != null)
                    'Follow-up job card ${r.followUpNumber}',
                ].join('\n'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ],
    );
  }
}
