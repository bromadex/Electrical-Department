import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../documents/job_documents_panel.dart';

import '../../services/core_providers.dart';
import '../../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'action_sheets.dart';
import 'job_card_panels.dart';
import 'models.dart';
import 'repository.dart';
import 'work.dart';
import 'work_panels.dart';

class JobCardScreen extends ConsumerWidget {
  const JobCardScreen({super.key, required this.reference, this.initialTab});

  /// Job card number (EL-JC-…) or id.
  final String reference;
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(jobCardProvider(reference)),
      onRetry: () => ref.invalidate(jobCardProvider(reference)),
      data: (job) => _JobCardView(job: job, initialTab: initialTab),
    );
  }
}

class _Act {
  const _Act(
    this.label,
    this.icon,
    this.run, {
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback run;
  final bool primary;
  final bool danger;
}

const _tabs = [
  'overview',
  'assessment',
  'assignment',
  'work',
  'safety',
  'files',
  'comments',
  'activity',
  'closure',
];

class _JobCardView extends ConsumerStatefulWidget {
  const _JobCardView({required this.job, this.initialTab});

  final JobCard job;
  final String? initialTab;

  @override
  ConsumerState<_JobCardView> createState() => _JobCardViewState();
}

class _JobCardViewState extends ConsumerState<_JobCardView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: _tabs
        .indexOf(widget.initialTab ?? '')
        .clamp(0, _tabs.length - 1),
  )..addListener(() => setState(() {}));
  bool _busy = false;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  JobCardActions get _actions => ref.read(jobCardActionsProvider);

  Future<void> _sheet(String title, Widget sheet) =>
      showFormSheet<bool>(context, title: title, child: sheet);

  Future<void> _do(Future<void> Function() run, String done) async {
    setState(() => _busy = true);
    try {
      await run();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withReason(
    String title,
    String label,
    String confirm,
    Future<void> Function(String reason) run, {
    required String done,
    String? message,
    bool danger = false,
  }) async {
    final reason = await askReason(
      context,
      title: title,
      label: label,
      confirm: confirm,
      message: message,
      danger: danger,
    );
    if (reason == null) return;
    await _do(() => run(reason), done);
  }

  List<_Act> _available(JobCard j, JobCardExtras x, String? me, JobWork? work) {
    final session = ref.read(sessionProvider);
    bool can(String code) => session.can(code, siteId: j.siteId);
    String? myRole;
    for (final a in x.current) {
      if (a.userId == me) {
        myRole = a.isResponsible ? 'responsible' : (myRole ?? 'support');
      }
    }
    final s = j.status;
    final acts = <_Act>[];
    final myWorkRunning = work?.runningFor(me) != null;

    void assess() => _sheet('Engineering assessment', AssessSheet(job: j));
    void assign(String title) =>
        _sheet(title, AssignSheet(job: j, current: x.current));
    void returnForClarification() => _withReason(
      'Return for clarification',
      'What needs clarifying?',
      'Return',
      (r) => _actions.returnForClarification(j.id, r),
      done: 'Returned for clarification',
    );
    // The team starts their own timer; an engineer off the team only moves
    // the job card back to in progress.
    void start() => myRole != null
        ? _do(() => _actions.startWork(j.id), 'Work started')
        : _do(
            () => _actions.setStatus(j.id, 'in_progress'),
            'Back in progress',
          );
    void pause({required bool holdOnly}) => _sheet(
      holdOnly ? 'Put on hold' : 'Pause work',
      PauseSheet(job: j, myWorkRunning: !holdOnly && myWorkRunning),
    );

    switch (s) {
      case JobStatus.registered:
        if (can('jc.assess')) {
          acts.add(
            _Act('Assess', Icons.fact_check_outlined, assess, primary: true),
          );
          acts.add(
            _Act(
              'Return for clarification',
              Icons.help_outline_rounded,
              returnForClarification,
            ),
          );
        }
      case JobStatus.awaitingClarification:
        if (j.registeredBy == me || can('jc.register')) {
          acts.add(
            _Act(
              'Provide clarification',
              Icons.reply_rounded,
              () => _withReason(
                'Provide clarification',
                'Clarification',
                'Send',
                (r) => _actions.clarify(j.id, r),
                done: 'Clarification sent',
              ),
              primary: true,
            ),
          );
        }
      case JobStatus.awaitingAssignment:
        if (can('jc.assign')) {
          acts.add(
            _Act(
              'Assign',
              Icons.assignment_ind_outlined,
              () => assign('Assign job card'),
              primary: true,
            ),
          );
        }
        if (can('jc.assess')) {
          acts.add(_Act('Edit assessment', Icons.edit_note_rounded, assess));
          acts.add(
            _Act(
              'Return for clarification',
              Icons.help_outline_rounded,
              returnForClarification,
            ),
          );
        }
      case JobStatus.assigned:
        if (myRole != null) {
          acts.add(
            _Act(
              myRole == 'responsible' ? 'Accept job' : 'Acknowledge',
              Icons.task_alt_rounded,
              () => _do(() => _actions.accept(j.id), 'Accepted'),
              primary: true,
            ),
          );
        }
        if (myRole == 'responsible') {
          acts.add(_Act('Start work', Icons.play_arrow_rounded, start));
        }
      case JobStatus.accepted:
        if (myRole != null || can('jc.assign')) {
          acts.add(
            _Act(
              myRole != null ? 'Start work' : 'Mark in progress',
              Icons.play_arrow_rounded,
              start,
              primary: true,
            ),
          );
          acts.add(
            _Act(
              'Put on hold',
              Icons.pause_rounded,
              () => pause(holdOnly: true),
            ),
          );
        }
      case JobStatus.inProgress:
        if (myRole != null && !myWorkRunning) {
          acts.add(
            _Act(
              work != null && work.sessions.any((x) => x.userId == me)
                  ? 'Resume my work'
                  : 'Start work',
              Icons.play_arrow_rounded,
              start,
              primary: myRole != 'responsible',
            ),
          );
        }
        if (myRole == 'responsible' || can('jc.assign')) {
          acts.add(
            _Act(
              'Submit for review',
              Icons.send_rounded,
              () =>
                  _sheet('Submit for engineering review', SubmitSheet(job: j)),
              primary: true,
            ),
          );
        }
        if (myRole != null || can('jc.assign')) {
          acts.add(
            _Act(
              myWorkRunning ? 'Pause' : 'Put on hold',
              Icons.pause_rounded,
              () => pause(holdOnly: !myWorkRunning),
            ),
          );
        }
      case JobStatus.onHold ||
          JobStatus.awaitingMaterials ||
          JobStatus.awaitingIsolation ||
          JobStatus.awaitingSpecialist ||
          JobStatus.awaitingProductionClearance:
        if (myRole != null || can('jc.assign')) {
          acts.add(
            _Act('Resume work', Icons.play_arrow_rounded, start, primary: true),
          );
          acts.add(
            _Act(
              'Change hold reason',
              Icons.edit_outlined,
              () => pause(holdOnly: true),
            ),
          );
        }
      case JobStatus.awaitingReview:
        if (can('jc.review')) {
          acts.add(
            _Act(
              'Verify work',
              Icons.verified_outlined,
              () => _sheet(
                'Engineering verification',
                ReviewSheet(
                  job: j,
                  selfReview: j.performedBy == me || myRole != null,
                ),
              ),
              primary: true,
            ),
          );
        }
        if (work?.openQuestion != null &&
            (myRole != null || can('jc.assign'))) {
          acts.add(
            _Act(
              'Answer the reviewer',
              Icons.reply_rounded,
              () => _withReason(
                'Answer the reviewer',
                'Your answer',
                'Send answer',
                (r) => _actions.answerReview(j.id, r),
                done: 'Answer sent',
                message: work!.openQuestion!.notes,
              ),
              primary: !can('jc.review'),
            ),
          );
        }
      case JobStatus.reopened:
        if (myRole == 'responsible') {
          acts.add(
            _Act(
              'Accept job',
              Icons.task_alt_rounded,
              () => _do(() => _actions.accept(j.id), 'Accepted'),
              primary: true,
            ),
          );
        }
      case JobStatus.closed:
        if (can('jc.reopen')) {
          acts.add(
            _Act(
              'Reopen',
              Icons.replay_rounded,
              () => _withReason(
                'Reopen job card',
                'Why reopen it?',
                'Reopen',
                (r) => _actions.reopen(j.id, r),
                done: 'Job card reopened',
              ),
            ),
          );
        }
      case JobStatus.cancelled:
        break;
    }

    final assignedStage = s.isActive || s == JobStatus.reopened;
    if (assignedStage && can('jc.assign')) {
      acts.add(
        _Act(
          j.responsibleId == null ? 'Assign' : 'Reassign',
          Icons.swap_horiz_rounded,
          () => assign(
            j.responsibleId == null ? 'Assign job card' : 'Reassign job card',
          ),
        ),
      );
      if (s == JobStatus.assigned || s == JobStatus.accepted) {
        acts.add(
          _Act(
            'Unassign',
            Icons.person_remove_outlined,
            () => _withReason(
              'Unassign',
              'Why take it off the team?',
              'Unassign',
              (r) => _actions.unassign(j.id, r),
              done: 'Back in the assignment queue',
            ),
          ),
        );
      }
    }
    if (s.isOpen &&
        can('jc.assess') &&
        j.isAssessed &&
        s != JobStatus.awaitingAssignment) {
      acts.add(_Act('Edit assessment', Icons.edit_note_rounded, assess));
    }
    if (s.isOpen && can('jc.escalate')) {
      if (!j.isCritical) {
        acts.add(
          _Act(
            'Escalate to critical',
            Icons.report_outlined,
            () => _withReason(
              'Escalate to critical',
              'Reason (safety, major failure, production impact…)',
              'Escalate',
              (r) => _actions.escalate(j.id, critical: true, reason: r),
              done: 'Escalated to critical',
              danger: true,
            ),
          ),
        );
      } else if (j.priority != Priority.p1) {
        acts.add(
          _Act(
            'De-escalate',
            Icons.report_off_outlined,
            () => _withReason(
              'De-escalate',
              'Why is it no longer critical?',
              'De-escalate',
              (r) => _actions.escalate(j.id, critical: false, reason: r),
              done: 'No longer critical',
            ),
          ),
        );
      }
    }
    if (s.isOpen && can('jc.cancel')) {
      acts.add(
        _Act(
          'Cancel job card',
          Icons.cancel_outlined,
          () => _withReason(
            'Cancel job card',
            'Reason for cancelling',
            'Cancel job card',
            (r) => _actions.cancel(j.id, r),
            done: 'Job card cancelled',
            danger: true,
          ),
          danger: true,
        ),
      );
    }
    return acts;
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final extras = ref.watch(jobCardExtrasProvider(job.id));
    final x = extras.value ?? const JobCardExtras();
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final work = ref.watch(jobWorkProvider(job.id)).value;
    final acts = _available(job, x, me, work);
    final onTeam = x.current.any((a) => a.userId == me);
    final canAddFiles =
        job.status.isOpen &&
        (session.can('jc.register', siteId: job.siteId) ||
            session.can('jc.assess', siteId: job.siteId) ||
            session.can('jc.execute', siteId: job.siteId));

    final content = switch (_tabs[_tab.index]) {
      'overview' => _Overview(job: job),
      'assessment' => _Assessment(job: job),
      'assignment' => _AssignmentTab(job: job, extras: x),
      'files' => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JobDocumentsPanel(
            jobCardId: job.id,
            closed: !job.status.isOpen,
            canAttach:
                onTeam ||
                job.registeredBy == me ||
                session.can('jc.assign', siteId: job.siteId) ||
                session.can('jc.assess', siteId: job.siteId),
          ),
          const SizedBox(height: Space.md),
          AttachmentsPanel(job: job, files: x.attachments, canAdd: canAddFiles),
        ],
      ),
      'comments' => CommentsPanel(
        job: job,
        comments: x.comments,
        canComment: session.can('jc.view', siteId: job.siteId),
      ),
      'work' =>
        work == null
            ? const LoadingPanel()
            : WorkTab(job: job, work: work, extras: x),
      'safety' =>
        work == null
            ? const LoadingPanel()
            : SafetyTab(
                job: job,
                work: work,
                canRecord:
                    job.status.isOpen &&
                    (onTeam ||
                        session.can('jc.assign', siteId: job.siteId) ||
                        session.can('jc.assess', siteId: job.siteId)),
              ),
      'activity' => TimelinePanel(jobId: job.id),
      _ => ClosureTab(job: job, work: work, closures: x.closures),
    };
    final showClock =
        work != null &&
        (job.status == JobStatus.inProgress ||
            job.status.isHold ||
            (job.status.isOpen && work.sessions.isNotEmpty));

    return AppPage(
      title: job.number,
      subtitle: job.title,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.read(jobCardsLiveProvider.notifier).bumpNow(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(job: job),
          _ReasonBanner(job: job),
          if (work?.openQuestion != null)
            _Banner(
              color: AppColors.info,
              icon: Icons.help_outline_rounded,
              text:
                  '${work!.openQuestion!.reviewer} asked: ${work.openQuestion!.notes ?? ''}',
            ),
          if (showClock) ...[
            const SizedBox(height: Space.sm),
            WorkClock(job: job, work: work),
          ],
          if (acts.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final a in acts)
                  a.primary
                      ? FilledButton.icon(
                          onPressed: _busy ? null : a.run,
                          icon: Icon(a.icon),
                          label: Text(a.label),
                        )
                      : OutlinedButton.icon(
                          style: a.danger
                              ? OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.critical,
                                )
                              : null,
                          onPressed: _busy ? null : a.run,
                          icon: Icon(a.icon),
                          label: Text(a.label),
                        ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  controller: _tab,
                  isScrollable: true,
                  tabs: [
                    const Tab(text: 'Overview'),
                    const Tab(text: 'Assessment'),
                    const Tab(text: 'Assignment'),
                    Tab(text: 'Work (${work?.records.length ?? 0})'),
                    const Tab(text: 'Safety'),
                    Tab(text: 'Files (${x.attachments.length})'),
                    Tab(text: 'Comments (${x.comments.length})'),
                    const Tab(text: 'Activity'),
                    const Tab(text: 'Closure'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: extras.hasError && !extras.hasValue
                      ? ErrorPanel(
                          error: extras.error!,
                          onRetry: () =>
                              ref.invalidate(jobCardExtrasProvider(job.id)),
                        )
                      : content,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.job});

  final JobCard job;

  @override
  Widget build(BuildContext context) {
    final open = job.status.isOpen;
    final deadline = job.targetCompletionAt == null
        ? 'No deadline'
        : !open
        ? fmtDateTime(job.targetCompletionAt)
        : job.isOverdue
        ? '${fmtDateTime(job.targetCompletionAt)}\nOverdue by ${fmtMinutes(job.overdueMinutes)}'
        : '${fmtDateTime(job.targetCompletionAt)}\n${fmtMinutes(job.remainingMinutes)} left';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PriorityBadge(job.priority, showName: true),
                if (job.isCriticalOpen) const CriticalFlag(),
                StatusPill(job.status),
                if (job.targetCompletionAt != null) SlaChip(job.sla),
                if (job.legacyCode != null)
                  Pill(
                    label: 'Migrated from ${job.legacyCode}',
                    color: AppColors.neutral,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            ResponsiveGrid(
              minItemWidth: 200,
              children: [
                KeyValue(
                  'Equipment',
                  [job.equipment, job.assetNo].whereType<String>().join(' · '),
                ),
                KeyValue(
                  'Where',
                  [job.siteName, job.place].whereType<String>().join(' · '),
                ),
                KeyValue('Responsible', job.responsibleName ?? 'Not assigned'),
                KeyValue(
                  'Deadline',
                  null,
                  child: Text(
                    deadline,
                    style: TextStyle(
                      color: job.isOverdue ? AppColors.critical : null,
                      fontWeight: job.isOverdue ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                KeyValue(
                  'Received',
                  '${fmtDateTime(job.receivedAt)}\nfrom ${job.reporterName}',
                ),
                KeyValue(
                  'Response time',
                  job.responseMinutes == null
                      ? 'Waiting for a response (target ${fmtDateTime(job.targetResponseAt)})'
                      : '${fmtMinutes(job.responseMinutes)}'
                            '${job.responseTargetMet == true
                                ? ' · within target'
                                : job.responseTargetMet == false
                                ? ' · target missed'
                                : ''}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Why the job is where it is: held, returned, cancelled or reopened.
class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner({required this.job});

  final JobCard job;

  @override
  Widget build(BuildContext context) {
    final reason = job.statusReason;
    final s = job.status;
    final String? text = switch (s) {
      _ when reason == null => null,
      JobStatus.awaitingClarification => 'Returned for clarification: $reason',
      JobStatus.cancelled => 'Cancelled: $reason',
      JobStatus.reopened => 'Reopened: $reason',
      JobStatus.accepted => 'Returned by the engineer: $reason',
      _ when s.isHold => '${s.label}: $reason',
      _ => null,
    };
    if (text == null && !job.isCriticalOpen) return const SizedBox.shrink();
    final color = s == JobStatus.cancelled
        ? AppColors.neutral
        : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (job.isCriticalOpen)
          _Banner(
            color: AppColors.critical,
            icon: Icons.report_rounded,
            text:
                'Critical${job.criticalReason == null ? '' : ': ${job.criticalReason}'}',
          ),
        if (text != null) _Banner(color: color, icon: s.icon, text: text),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: Space.sm),
    padding: const EdgeInsets.all(Space.sm),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.job});

  final JobCard job;

  @override
  Widget build(BuildContext context) {
    final source = switch (job.source) {
      'request' => 'Request ${job.requestNo ?? ''}',
      'legacy' => 'Jobs board (${job.legacyCode ?? ''})',
      'preventive' => 'Preventive maintenance',
      'follow_up' => 'Follow-up job',
      _ => 'Registered directly',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyValue('Description', null, child: CopyableText(job.description)),
        const SectionHeader('Reception'),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            KeyValue('Reported by', job.reporterName),
            KeyValue('Requesting department', job.departmentName),
            KeyValue(
              'Registered by',
              '${job.registeredByName ?? '—'} · ${fmtDateTime(job.registeredAt)}',
            ),
            KeyValue('Source', source),
            KeyValue('Category', job.categoryName),
            KeyValue('Operational impact', job.impact?.label),
            KeyValue(
              'Requested completion',
              fmtDateTime(job.t('requested_completion_at')),
            ),
            KeyValue(
              'Equipment location',
              job.equipmentLocation ?? job.location,
            ),
          ],
        ),
        if (job.requestId != null || job.assetId != null)
          Wrap(
            spacing: Space.xs,
            children: [
              if (job.requestId != null)
                TextButton.icon(
                  onPressed: () => context.push('/requests/${job.requestId}'),
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: Text('Open request ${job.requestNo ?? ''}'),
                ),
              if (job.assetId != null)
                TextButton.icon(
                  onPressed: () => context.push('/assets/${job.assetId}'),
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                  label: const Text('Open equipment record'),
                ),
            ],
          ),
        const SectionHeader('Timeline'),
        ResponsiveGrid(
          minItemWidth: 170,
          children: [
            KeyValue('Received', fmtDateTime(job.receivedAt)),
            KeyValue('Assessed', fmtDateTime(job.t('assessed_at'))),
            KeyValue('First assigned', fmtDateTime(job.t('first_assigned_at'))),
            KeyValue('Accepted', fmtDateTime(job.t('accepted_at'))),
            KeyValue('Work started', fmtDateTime(job.t('first_started_at'))),
            KeyValue(
              'Submitted for review',
              fmtDateTime(job.t('submitted_at')),
            ),
            KeyValue(
              job.status == JobStatus.cancelled ? 'Cancelled' : 'Closed',
              fmtDateTime(
                job.status == JobStatus.cancelled
                    ? job.t('cancelled_at')
                    : job.closedAt,
              ),
            ),
            KeyValue('Elapsed since received', fmtMinutes(job.elapsedMinutes)),
          ],
        ),
      ],
    );
  }
}

class _Assessment extends StatelessWidget {
  const _Assessment({required this.job});

  final JobCard job;

  @override
  Widget build(BuildContext context) {
    if (!job.isAssessed) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'Not assessed yet',
        message:
            'An electrical engineer assesses the job before it is assigned.',
      );
    }
    String yesNo(bool? v) => v == null ? '—' : (v ? 'Yes' : 'No');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            KeyValue('Type of work', humanize(job.maintenanceType)),
            KeyValue('Severity', humanize(job.s('severity'))),
            KeyValue('Safety risk', humanize(job.s('safety_risk'))),
            KeyValue('Equipment state', humanize(job.equipmentState)),
            KeyValue('Isolation required', yesNo(job.b('isolation_required'))),
            KeyValue(
              'Permit to work required',
              yesNo(job.b('permit_required')),
            ),
            KeyValue(
              'Lockout / tagout required',
              yesNo(job.b('loto_required')),
            ),
            KeyValue('People needed', job.n('required_personnel')?.toString()),
            KeyValue(
              'Expected duration',
              job.n('expected_duration_hours') == null
                  ? null
                  : '${job.n('expected_duration_hours')} h',
            ),
            KeyValue('Target response', fmtDateTime(job.targetResponseAt)),
            KeyValue('Target completion', fmtDateTime(job.targetCompletionAt)),
            KeyValue('Assessed', fmtDateTime(job.t('assessed_at'))),
          ],
        ),
        const SizedBox(height: Space.md),
        ResponsiveGrid(
          minItemWidth: 300,
          children: [
            KeyValue(
              'Personnel and competencies',
              job.s('required_competencies'),
            ),
            KeyValue(
              'Tools, spares and materials',
              job.s('resources_required'),
            ),
            KeyValue('Safety risks and controls', job.s('safety_notes')),
            KeyValue('Assessment notes', job.s('assessment_notes')),
          ],
        ),
      ],
    );
  }
}

class _AssignmentTab extends ConsumerWidget {
  const _AssignmentTab({required this.job, required this.extras});

  final JobCard job;
  final JobCardExtras extras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAssign = ref
        .watch(sessionProvider)
        .can('jc.assign', siteId: job.siteId);
    final past = [
      for (final a in extras.assignments)
        if (!a.isCurrent) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extras.current.isEmpty)
          const Text('Nobody is assigned.')
        else
          for (final a in extras.current)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppAvatar(name: a.personName),
              title: Text(a.personName),
              subtitle: Text(
                '${a.isResponsible ? 'Responsible' : 'Supporting'} · assigned ${fmtDateTime(a.assignedAt)}'
                '${a.assignerName == null ? '' : ' by ${a.assignerName}'}'
                '${a.acknowledgedAt == null ? ' · not acknowledged yet' : ' · acknowledged ${fmtDateTime(a.acknowledgedAt)}'}',
              ),
            ),
        const SectionHeader('Plan'),
        ResponsiveGrid(
          minItemWidth: 260,
          children: [
            KeyValue('Assigning engineer', job.assignedByName),
            KeyValue('Planned start', fmtDateTime(job.t('planned_start_at'))),
            KeyValue(
              'Estimated labour hours',
              job.n('estimated_labour_hours')?.toString(),
            ),
            KeyValue('Target completion', fmtDateTime(job.targetCompletionAt)),
            KeyValue('Required materials', job.s('required_materials')),
            KeyValue('Required tools', job.s('required_tools')),
            KeyValue('Safety precautions', job.s('safety_precautions')),
            KeyValue('Procedure', job.s('procedure_notes')),
          ],
        ),
        if (past.isNotEmpty) ...[
          const SectionHeader('Earlier assignments'),
          for (final a in past)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(
                '${a.personName} (${a.isResponsible ? 'responsible' : 'support'})',
              ),
              subtitle: Text(
                '${fmtDateTime(a.assignedAt)} – ${fmtDateTime(a.endedAt)} · ${a.endReason ?? 'ended'}'
                '${a.handoverNote == null ? '' : '\nHandover: ${a.handoverNote}'}',
              ),
            ),
        ],
        if (canAssign) ...[
          const SectionHeader('Team workload at this site'),
          AsyncView(
            value: ref.watch(workloadProvider(job.siteId)),
            onRetry: () => ref.invalidate(workloadProvider(job.siteId)),
            data: (list) => Column(
              children: [
                for (final w in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(w.name),
                    trailing: Text(
                      '${w.responsibleOpen} resp · ${w.supportOpen} supp'
                      '${w.overdue > 0 ? ' · ${w.overdue} overdue' : ''}',
                      style: TextStyle(
                        color: w.overdue > 0 ? AppColors.warning : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
