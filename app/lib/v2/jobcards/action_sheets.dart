import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reference/reference_data.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/media.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'models.dart';
import 'repository.dart';
import 'work.dart';

/// Opens [child] as a dialog on wide screens and a full-height sheet on phones.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  final phone = MediaQuery.sizeOf(context).width < Breakpoints.phone;
  final content = _SheetFrame(title: title, child: child);
  if (phone) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.94, child: content),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(Space.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: (MediaQuery.sizeOf(context).height * 0.9).clamp(480, 1600),
        ),
        child: content,
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Scrollable form body with a save button that shows progress and errors.
class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.formKey,
    required this.children,
    required this.saveLabel,
    required this.onSave,
    required this.busy,
    this.danger = false,
  });

  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final String saveLabel;
  final VoidCallback onSave;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Space.xs),
                FilledButton(
                  style: danger
                      ? FilledButton.styleFrom(
                          backgroundColor: AppColors.critical,
                        )
                      : null,
                  onPressed: busy ? null : onSave,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(saveLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mixin for sheets that call an action, show errors and close on success.
mixin _Saving<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;

  Future<void> save(Future<void> Function() action, {String? done}) async {
    if (!(formKey.currentState?.validate() ?? true)) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context, true);
      if (done != null) showSnack(context, done);
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showError(context, e);
    }
  }
}

/// A short prompt for a reason (cancel, reopen, return, unassign, escalate).
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String? message,
  bool danger = false,
}) {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Text(message),
                const SizedBox(height: Space.sm),
              ],
              TextFormField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: label),
                validator: Valid.length(2, 2000, 'A reason'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.critical)
              : null,
          onPressed: () {
            if (key.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Stage 2: assessment
// ---------------------------------------------------------------------------
class AssessSheet extends ConsumerStatefulWidget {
  const AssessSheet({super.key, required this.job});

  final JobCard job;

  @override
  ConsumerState<AssessSheet> createState() => _AssessSheetState();
}

class _AssessSheetState extends ConsumerState<AssessSheet> with _Saving {
  late bool? _valid = widget.job.b('is_valid') ?? true;
  late String? _type = widget.job.maintenanceType;
  late String? _severity = widget.job.s('severity');
  late String? _risk = widget.job.s('safety_risk');
  late String? _state = widget.job.equipmentState;
  late bool? _isolation = widget.job.b('isolation_required');
  late bool? _permit = widget.job.b('permit_required');
  late bool? _loto = widget.job.b('loto_required');
  late String _priority = widget.job.priority.code;
  late DateTime? _targetResponse = widget.job.targetResponseAt;
  late DateTime? _targetCompletion = widget.job.targetCompletionAt;
  late final _safetyNotes = TextEditingController(
    text: widget.job.s('safety_notes'),
  );
  late final _competencies = TextEditingController(
    text: widget.job.s('required_competencies'),
  );
  late final _personnel = TextEditingController(
    text: widget.job.n('required_personnel')?.toString(),
  );
  late final _resources = TextEditingController(
    text: widget.job.s('resources_required'),
  );
  late final _duration = TextEditingController(
    text: widget.job.n('expected_duration_hours')?.toString(),
  );
  late final _notes = TextEditingController(
    text: widget.job.s('assessment_notes'),
  );

  @override
  Widget build(BuildContext context) {
    final valid = _valid ?? true;
    return _FormBody(
      formKey: formKey,
      busy: busy,
      danger: !valid,
      saveLabel: valid ? 'Save assessment' : 'Cancel as not valid',
      onSave: () {
        if (valid &&
            (_type == null ||
                _severity == null ||
                _risk == null ||
                _state == null)) {
          showSnack(
            context,
            'Choose the type of work, severity, safety risk and equipment state.',
          );
          return;
        }
        save(
          () => ref
              .read(jobCardActionsProvider)
              .assess(
                widget.job.id,
                valid: valid,
                maintenanceType: _type,
                severity: _severity,
                safetyRisk: _risk,
                safetyNotes: _safetyNotes.text,
                equipmentState: _state,
                competencies: _competencies.text,
                personnel: int.tryParse(_personnel.text.trim()),
                resources: _resources.text,
                isolation: _isolation,
                permit: _permit,
                loto: _loto,
                durationHours: num.tryParse(_duration.text.trim()),
                priority: _priority,
                targetResponseAt: _targetResponse,
                targetCompletionAt: _targetCompletion,
                notes: _notes.text,
              ),
          done: valid ? 'Assessment saved' : 'Job card cancelled as not valid',
        );
      },
      children: [
        YesNoField(
          label: 'Is the request valid?',
          value: _valid,
          onChanged: (v) => setState(() => _valid = v),
        ),
        const SizedBox(height: Space.md),
        if (!valid)
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Why is it not valid? *',
            ),
            validator: Valid.length(2, 2000, 'A reason'),
          )
        else ...[
          FormSection(
            title: 'Classification',
            children: [
              DropdownField<String>(
                label: 'Type of work',
                required: true,
                value: _type,
                items: const [
                  ('reactive', 'Reactive'),
                  ('corrective', 'Corrective'),
                  ('emergency', 'Emergency'),
                  ('preventive', 'Preventive'),
                  ('inspection', 'Inspection'),
                  ('installation', 'Installation'),
                  ('improvement', 'Improvement'),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              FullWidth(
                child: ChoiceField<String>(
                  label: 'Severity *',
                  value: _severity,
                  onChanged: (v) => setState(() => _severity = v),
                  options: const [
                    ('minor', 'Minor', null, AppColors.neutral),
                    ('moderate', 'Moderate', null, AppColors.info),
                    ('major', 'Major', null, AppColors.warning),
                    ('critical', 'Critical', null, AppColors.critical),
                  ],
                ),
              ),
              FullWidth(
                child: ChoiceField<String>(
                  label: 'Safety risk *',
                  value: _risk,
                  onChanged: (v) => setState(() => _risk = v),
                  options: const [
                    ('low', 'Low', null, AppColors.success),
                    ('medium', 'Medium', null, AppColors.info),
                    ('high', 'High', null, AppColors.warning),
                    (
                      'extreme',
                      'Extreme',
                      Icons.report_rounded,
                      AppColors.critical,
                    ),
                  ],
                ),
              ),
              FullWidth(
                child: ChoiceField<String>(
                  label: 'Equipment state *',
                  value: _state,
                  onChanged: (v) => setState(() => _state = v),
                  options: const [
                    ('operational', 'Operational', null, AppColors.success),
                    ('degraded', 'Degraded', null, AppColors.warning),
                    (
                      'out_of_service',
                      'Out of service',
                      null,
                      AppColors.critical,
                    ),
                  ],
                ),
              ),
              FullWidth(
                child: TextFormField(
                  controller: _safetyNotes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Safety risks and controls',
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            title: 'Safety arrangements',
            subtitle: 'Recording these here does not make equipment safe; follow the site\'s isolation and permit procedures.',
            children: [
              YesNoField(
                label: 'Isolation required?',
                value: _isolation,
                onChanged: (v) => setState(() => _isolation = v),
              ),
              YesNoField(
                label: 'Permit to work required?',
                value: _permit,
                onChanged: (v) => setState(() => _permit = v),
              ),
              YesNoField(
                label: 'Lockout / tagout required?',
                value: _loto,
                onChanged: (v) => setState(() => _loto = v),
              ),
            ],
          ),
          FormSection(
            title: 'Resources',
            children: [
              TextFormField(
                controller: _competencies,
                decoration: const InputDecoration(
                  labelText: 'Personnel and competencies',
                ),
              ),
              TextFormField(
                controller: _personnel,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'People needed'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  return n == null || n < 1 || n > 50
                      ? 'A whole number from 1 to 50'
                      : null;
                },
              ),
              TextFormField(
                controller: _duration,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Expected duration (hours)',
                ),
                validator: Valid.positiveNumber('The duration'),
              ),
              FullWidth(
                child: TextFormField(
                  controller: _resources,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Tools, spares and materials needed',
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            title: 'Priority and targets',
            subtitle: 'Changing the priority applies its default targets unless you set them.',
            children: [
              FullWidth(
                child: ChoiceField<String>(
                  label: 'Priority',
                  value: _priority,
                  onChanged: (v) => setState(() {
                    _priority = v;
                    _targetResponse = null;
                    _targetCompletion = null;
                  }),
                  options: [
                    for (final p in Priority.values)
                      (p.code, '${p.code} ${p.name}', p.icon, p.color),
                  ],
                ),
              ),
              DateTimeField(
                label: 'Target response',
                value: _targetResponse,
                helper: _targetResponse == null ? 'From the priority' : null,
                onChanged: (v) => setState(() => _targetResponse = v),
              ),
              DateTimeField(
                label: 'Target completion (deadline)',
                value: _targetCompletion,
                helper: _targetCompletion == null ? 'From the priority' : null,
                onChanged: (v) => setState(() => _targetCompletion = v),
              ),
              FullWidth(
                child: TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Assessment notes',
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stage 3: assignment
// ---------------------------------------------------------------------------
class AssignSheet extends ConsumerStatefulWidget {
  const AssignSheet({super.key, required this.job, required this.current});

  final JobCard job;
  final List<Assignment> current;

  @override
  ConsumerState<AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<AssignSheet> with _Saving {
  late String? _responsible = widget.job.responsibleId;
  late final Set<String> _support = {
    for (final a in widget.current)
      if (a.role == 'support') a.userId,
  };
  late DateTime? _plannedStart = widget.job.t('planned_start_at');
  late DateTime? _target = widget.job.targetCompletionAt;
  late final _hours = TextEditingController(
    text: widget.job.n('estimated_labour_hours')?.toString(),
  );
  late final _materials = TextEditingController(
    text: widget.job.s('required_materials'),
  );
  late final _tools = TextEditingController(
    text: widget.job.s('required_tools'),
  );
  late final _safety = TextEditingController(
    text: widget.job.s('safety_precautions'),
  );
  late final _procedure = TextEditingController(
    text: widget.job.s('procedure_notes'),
  );
  final _handover = TextEditingController();
  final _reason = TextEditingController();

  bool get _reassigning =>
      widget.job.responsibleId != null &&
      _responsible != null &&
      _responsible != widget.job.responsibleId;

  bool get _workStarted =>
      widget.job.status == JobStatus.accepted ||
      widget.job.status == JobStatus.inProgress ||
      widget.job.status.isHold;

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(workloadProvider(widget.job.siteId));
    final handoverRequired =
        ref.watch(referenceDataProvider).value?.settings.handoverNoteRequired ??
        true;
    final theme = Theme.of(context);
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: widget.job.responsibleId == null
          ? 'Assign'
          : 'Save assignment',
      onSave: () {
        if (_responsible == null) {
          showSnack(context, 'Choose the responsible person.');
          return;
        }
        save(
          () => ref
              .read(jobCardActionsProvider)
              .assign(
                widget.job.id,
                responsibleId: _responsible!,
                supportIds: [
                  for (final s in _support)
                    if (s != _responsible) s,
                ],
                plannedStartAt: _plannedStart,
                targetCompletionAt: _target,
                estimatedHours: num.tryParse(_hours.text.trim()),
                materials: _materials.text,
                tools: _tools.text,
                safety: _safety.text,
                procedure: _procedure.text,
                handoverNote: _handover.text,
                reason: _reason.text,
              ),
          done: 'Assignment saved',
        );
      },
      children: [
        Text('Responsible person', style: theme.textTheme.titleSmall),
        Text(
          'Current load: open jobs as responsible / supporting, overdue, estimated hours.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.xs),
        AsyncView(
          value: people,
          onRetry: () => ref.invalidate(workloadProvider(widget.job.siteId)),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(Space.md),
                  child: Text('Nobody at this site can work job cards yet.'),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final w in list)
                        _PersonRow(
                          w: w,
                          responsible: _responsible == w.userId,
                          support: _support.contains(w.userId),
                          onResponsible: () => setState(() {
                            _responsible = w.userId;
                            _support.remove(w.userId);
                          }),
                          onSupport: (on) => setState(() {
                            if (on) {
                              _support.add(w.userId);
                            } else {
                              _support.remove(w.userId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
        ),
        if (_reassigning && _workStarted) ...[
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _handover,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: handoverRequired
                  ? 'Handover note for the new person *'
                  : 'Handover note',
            ),
            validator: handoverRequired
                ? Valid.length(2, 2000, 'A handover note')
                : null,
          ),
        ],
        if (_reassigning) ...[
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason for reassigning',
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        FormSection(
          title: 'Plan',
          children: [
            DateTimeField(
              label: 'Planned start',
              value: _plannedStart,
              onChanged: (v) => setState(() => _plannedStart = v),
            ),
            DateTimeField(
              label: 'Target completion (deadline)',
              value: _target,
              allowClear: false,
              onChanged: (v) => setState(() => _target = v),
            ),
            TextFormField(
              controller: _hours,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Estimated labour hours',
              ),
              validator: Valid.positiveNumber('Estimated hours'),
            ),
            FullWidth(
              child: TextFormField(
                controller: _materials,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Required materials',
                ),
              ),
            ),
            FullWidth(
              child: TextFormField(
                controller: _tools,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Required tools and test instruments',
                ),
              ),
            ),
            FullWidth(
              child: TextFormField(
                controller: _safety,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Safety precautions',
                ),
              ),
            ),
            FullWidth(
              child: TextFormField(
                controller: _procedure,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Procedure / work instructions',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.w,
    required this.responsible,
    required this.support,
    required this.onResponsible,
    required this.onSupport,
  });

  final Workload w;
  final bool responsible;
  final bool support;
  final VoidCallback onResponsible;
  final ValueChanged<bool> onSupport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onResponsible,
      leading: Icon(
        responsible
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: responsible ? theme.colorScheme.primary : null,
      ),
      title: Text(w.name.isEmpty ? 'Unnamed' : w.name),
      subtitle: Text(
        '${w.responsibleOpen} responsible · ${w.supportOpen} supporting'
        '${w.overdue > 0 ? ' · ${w.overdue} overdue' : ''}'
        '${w.estimatedHours > 0 ? ' · ~${w.estimatedHours} h' : ''}',
        style: w.overdue > 0 ? const TextStyle(color: AppColors.warning) : null,
      ),
      trailing: responsible
          ? const Pill(label: 'Responsible', dense: true)
          : FilterChip(
              label: const Text('Support'),
              selected: support,
              onSelected: onSupport,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage 4: pausing work and holds
// ---------------------------------------------------------------------------

/// Pause my work (break, end of shift, another job) or put the job on hold
/// because it is waiting for something (materials, isolation, ...).
class PauseSheet extends ConsumerStatefulWidget {
  const PauseSheet({
    super.key,
    required this.job,
    this.myWorkRunning = true,
    this.canHold = true,
  });

  final JobCard job;

  /// Offer the short pauses (only when my timer is running).
  final bool myWorkRunning;

  /// Offer the hold reasons.
  final bool canHold;

  @override
  ConsumerState<PauseSheet> createState() => _PauseSheetState();
}

const _shortPauses = [
  ('break', 'Break', Icons.coffee_outlined),
  ('end_of_shift', 'End of shift', Icons.nightlight_outlined),
  ('other_job', 'Another job', Icons.swap_horiz_rounded),
  ('other', 'Other', Icons.more_horiz_rounded),
];

class _PauseSheetState extends ConsumerState<PauseSheet> with _Saving {
  late String? _reason = widget.job.status.isHold ? widget.job.status.db : null;
  bool _counts = true;
  final _note = TextEditingController();

  bool get _isHold => JobStatus.holds.any((s) => s.db == _reason);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: _isHold ? 'Put on hold' : 'Pause my work',
      onSave: () {
        if (_reason == null) {
          showSnack(context, 'Choose why the work is pausing.');
          return;
        }
        save(
          () => ref
              .read(jobCardActionsProvider)
              .pauseWork(
                widget.job.id,
                _reason!,
                note: _note.text,
                countsTowardSla: _counts,
              ),
          done: _isHold ? 'Job card on hold' : 'Your work is paused',
        );
      },
      children: [
        if (widget.myWorkRunning) ...[
          ChoiceField<String>(
            label: 'Short pause (stops only your timer)',
            value: _isHold ? null : _reason,
            onChanged: (v) => setState(() => _reason = v),
            options: [
              for (final (v, l, i) in _shortPauses) (v, l, i, AppColors.info),
            ],
          ),
          const SizedBox(height: Space.md),
        ],
        if (widget.canHold)
          ChoiceField<String>(
            label: 'The job is waiting (stops everyone\'s timer)',
            value: _isHold ? _reason : null,
            onChanged: (v) => setState(() => _reason = v),
            options: [
              for (final s in JobStatus.holds)
                (
                  s.db,
                  s == JobStatus.awaitingSpecialist
                      ? 'Awaiting specialist or contractor'
                      : s.label,
                  s.icon,
                  s.color,
                ),
            ],
          ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: _isHold ? 'What is it waiting for? *' : 'Note',
            hintText: _isHold ? 'e.g. 63 A MCB from Harare stores' : null,
          ),
          validator: _isHold ? Valid.length(2, 1000, 'A reason') : null,
        ),
        if (_isHold) ...[
          const SizedBox(height: Space.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _counts,
            onChanged: (v) => setState(() => _counts = v),
            title: const Text('Count this wait toward the completion deadline'),
            subtitle: Text(
              'Switch off only when the delay is outside the team\'s control, such '
              'as waiting for production clearance. The wait still shows in the '
              'elapsed time and on the job card.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stage 5: submit for engineering review
// ---------------------------------------------------------------------------
class SubmitSheet extends ConsumerStatefulWidget {
  const SubmitSheet({super.key, required this.job});

  final JobCard job;

  @override
  ConsumerState<SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends ConsumerState<SubmitSheet> with _Saving {
  late final _summary = TextEditingController(
    text: widget.job.s('completion_summary'),
  );
  late final _findings = TextEditingController(text: widget.job.s('findings'));
  late final _action = TextEditingController(
    text: widget.job.s('corrective_action'),
  );
  final _functional = TextEditingController();
  final _electrical = TextEditingController();
  final _materials = TextEditingController();
  final _labour = TextEditingController();
  final _defects = TextEditingController();
  final _recommendations = TextEditingController();
  late String? _after = widget.job.s('equipment_state_after');
  bool _checks = false;
  bool _safety = false;
  bool _labourFilled = false;
  List<PickedFile> _files = const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final work = ref.watch(jobWorkProvider(widget.job.id)).value;
    final recorded = work?.time.labourSeconds;
    if (!_labourFilled && recorded != null) {
      _labourFilled = true;
      _labour.text = (recorded / 3600).toStringAsFixed(2);
    }
    final missingAfter = work?.safety.missingAfter ?? const <String>[];
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: 'Submit for review',
      onSave: () {
        if (_after == null) {
          showSnack(context, 'Record the equipment condition after the work.');
          return;
        }
        if (!_checks || !_safety) {
          showSnack(
            context,
            'Confirm that the required checks and safety procedures were completed.',
          );
          return;
        }
        save(() async {
          final actions = ref.read(jobCardActionsProvider);
          if (_files.isNotEmpty) {
            await actions.addFiles(
              jobId: widget.job.id,
              siteId: widget.job.siteId,
              files: _files,
            );
          }
          await actions.submitForReview(
            widget.job.id,
            summary: _summary.text,
            findings: _findings.text,
            correctiveAction: _action.text,
            equipmentStateAfter: _after!,
            functionalTests: _functional.text,
            electricalTests: _electrical.text,
            materialsUsed: _materials.text,
            labourHours: num.tryParse(_labour.text.trim()),
            outstandingDefects: _defects.text,
            recommendations: _recommendations.text,
            checksConfirmed: _checks,
            safetyConfirmed: _safety,
          );
        }, done: 'Submitted for engineering review');
      },
      children: [
        if (missingAfter.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: Space.md),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              'Record these post-work safety checks first (Safety tab): '
              '${missingAfter.join(', ')}.',
            ),
          ),
        FormSection(
          title: 'What was done',
          children: [
            FullWidth(
              child: TextFormField(
                controller: _summary,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Work completion summary *',
                ),
                validator: Valid.length(5, 4000, 'The summary'),
              ),
            ),
            FullWidth(
              child: TextFormField(
                controller: _findings,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Fault cause or findings *',
                ),
                validator: Valid.length(2, 4000, 'The findings'),
              ),
            ),
            FullWidth(
              child: TextFormField(
                controller: _action,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Corrective action taken *',
                ),
                validator: Valid.length(2, 4000, 'The corrective action'),
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Tests, materials and time',
          children: [
            TextFormField(
              controller: _functional,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Functional test results',
              ),
            ),
            TextFormField(
              controller: _electrical,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Electrical test results',
                hintText: 'e.g. IR 500 MΩ, earth 0.4 Ω',
              ),
            ),
            TextFormField(
              controller: _materials,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Materials used'),
            ),
            TextFormField(
              controller: _labour,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Actual labour hours',
                helperText: recorded == null
                    ? null
                    : 'Work sessions recorded ${fmtHours(recorded)} '
                          '(all people together)',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                final n = num.tryParse(t);
                return n == null || n < 0 || n > 2000
                    ? 'Hours between 0 and 2000'
                    : null;
              },
            ),
          ],
        ),
        FormSection(
          title: 'Condition and what is left',
          children: [
            FullWidth(
              child: ChoiceField<String>(
                label: 'Equipment condition after the work *',
                value: _after,
                onChanged: (v) => setState(() => _after = v),
                options: const [
                  ('operational', 'Operational', null, AppColors.success),
                  ('degraded', 'Degraded', null, AppColors.warning),
                  (
                    'out_of_service',
                    'Out of service',
                    null,
                    AppColors.critical,
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _defects,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Outstanding defects',
              ),
            ),
            TextFormField(
              controller: _recommendations,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Recommendations'),
            ),
          ],
        ),
        Text('After photos and test sheets', style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.xs),
        AttachmentPicker(
          files: _files,
          photoKind: 'photo_after',
          onChanged: (f) => setState(() => _files = f),
        ),
        const SizedBox(height: Space.md),
        CheckboxListTile(
          value: _checks,
          onChanged: (v) => setState(() => _checks = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I confirm the required checks and tests were completed.',
          ),
        ),
        CheckboxListTile(
          value: _safety,
          onChanged: (v) => setState(() => _safety = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I confirm the applicable safety procedures were followed: isolation, '
            'permits, test before touch and safe reinstatement.',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Engineering verification
// ---------------------------------------------------------------------------
class ReviewSheet extends ConsumerStatefulWidget {
  const ReviewSheet({super.key, required this.job, required this.selfReview});

  final JobCard job;

  /// The reviewer did (or helped with) the work.
  final bool selfReview;

  @override
  ConsumerState<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<ReviewSheet> with _Saving {
  String _decision = 'approve';
  final _notes = TextEditingController();
  final _followTitle = TextEditingController();
  final _followDescription = TextEditingController();
  String? _followPriority;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final work = ref.watch(jobWorkProvider(job.id)).value;
    final latest = work?.submissions.lastOrNull;
    final question = work?.reviews.lastOrNull;
    final reject = _decision == 'reject';
    final followUp = _decision == 'follow_up';
    final ask = _decision == 'request_info';
    final (saveLabel, done) = switch (_decision) {
      'reject' => ('Return for more work', 'Returned to the technician'),
      'request_info' => ('Send question', 'Question sent'),
      'follow_up' => (
        'Approve and raise follow-up',
        'Job card closed; follow-up raised',
      ),
      _ => ('Approve and close', 'Job card closed'),
    };
    return _FormBody(
      formKey: formKey,
      busy: busy,
      danger: reject,
      saveLabel: saveLabel,
      onSave: () => save(
        () => ref
            .read(jobCardActionsProvider)
            .verify(
              job.id,
              followUp ? 'approve' : _decision,
              notes: _notes.text,
              followUpTitle: followUp ? _followTitle.text : null,
              followUpDescription: followUp ? _followDescription.text : null,
              followUpPriority: followUp ? _followPriority : null,
            ),
        done: done,
      ),
      children: [
        if (latest != null)
          SubmissionDetails(submission: latest)
        else ...[
          KeyValue('Completion summary', job.s('completion_summary')),
          const SizedBox(height: Space.sm),
          KeyValue('Corrective action', job.s('corrective_action')),
        ],
        if (question != null &&
            question.decision == 'request_info' &&
            question.answeredAt != null) ...[
          const SizedBox(height: Space.sm),
          KeyValue(
            'Your question: ${question.notes ?? ''}',
            'Answer from ${question.answeredBy ?? 'the technician'}: '
                '${question.answer}',
          ),
        ],
        const SizedBox(height: Space.md),
        if (widget.selfReview)
          Container(
            margin: const EdgeInsets.only(bottom: Space.md),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: const Text(
              'You worked on this job. Approving your own work needs the self-approval '
              'permission and is recorded as self-approved.',
            ),
          ),
        ChoiceField<String>(
          label: 'Decision',
          value: _decision,
          onChanged: (v) => setState(() => _decision = v),
          options: const [
            (
              'approve',
              'Approve closure',
              Icons.verified_outlined,
              AppColors.success,
            ),
            (
              'follow_up',
              'Approve and raise a follow-up job',
              Icons.playlist_add_rounded,
              AppColors.success,
            ),
            (
              'reject',
              'Return for more work',
              Icons.undo_rounded,
              AppColors.warning,
            ),
            (
              'request_info',
              'Ask a question',
              Icons.help_outline_rounded,
              AppColors.info,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: switch (_decision) {
              'reject' => 'What still needs to be done? *',
              'request_info' => 'Your question *',
              _ => 'Verification notes',
            },
          ),
          validator: reject || ask
              ? Valid.length(
                  2,
                  2000,
                  reject ? 'What needs doing' : 'The question',
                )
              : null,
        ),
        if (followUp) ...[
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _followTitle,
            decoration: const InputDecoration(
              labelText: 'Follow-up job card title *',
            ),
            validator: Valid.length(3, 120, 'The title'),
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _followDescription,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'What is outstanding',
              hintText: latest?.outstandingDefects,
            ),
          ),
          const SizedBox(height: Space.sm),
          ChoiceField<String>(
            label: 'Follow-up priority (default: same as this job)',
            value: _followPriority,
            onChanged: (v) => setState(() => _followPriority = v),
            options: [
              for (final p in Priority.values)
                (p.code, '${p.code} ${p.name}', p.icon, p.color),
            ],
          ),
        ],
      ],
    );
  }
}

/// One closure submission, as the reviewer and the Closure tab show it.
class SubmissionDetails extends StatelessWidget {
  const SubmissionDetails({super.key, required this.submission});

  final Submission submission;

  @override
  Widget build(BuildContext context) {
    final s = submission;
    final labour = s.labourHours == null
        ? 'Not given'
        : '${s.labourHours} h reported · ${fmtMinutes(s.recordedLabourMinutes)} recorded';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 260,
          children: [
            KeyValue('Completion summary', s.summary),
            KeyValue('Fault cause or findings', s.findings),
            KeyValue('Corrective action', s.correctiveAction),
            KeyValue(
              'Equipment after the work',
              humanize(s.equipmentStateAfter),
            ),
            KeyValue('Functional tests', s.functionalTests),
            KeyValue('Electrical tests', s.electricalTests),
            KeyValue('Materials used', s.materialsUsed),
            KeyValue('Labour', labour),
            KeyValue('Outstanding defects', s.outstandingDefects),
            KeyValue('Recommendations', s.recommendations),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Submitted by ${s.submittedBy} · ${fmtDateTime(s.submittedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Work log entry
// ---------------------------------------------------------------------------
class WorkRecordSheet extends ConsumerStatefulWidget {
  const WorkRecordSheet({super.key, required this.job});

  final JobCard job;

  @override
  ConsumerState<WorkRecordSheet> createState() => _WorkRecordSheetState();
}

class _WorkRecordSheetState extends ConsumerState<WorkRecordSheet>
    with _Saving {
  String _kind = 'work_performed';
  final _body = TextEditingController();
  final _readings =
      <(TextEditingController, TextEditingController, TextEditingController)>[];

  void _addReading() => setState(
    () => _readings.add((
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    )),
  );

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: 'Add to work log',
      onSave: () {
        final readings = [
          for (final (n, v, u) in _readings)
            if (n.text.trim().isNotEmpty || v.text.trim().isNotEmpty)
              Reading(n.text.trim(), v.text.trim(), u.text.trim()).toJson(),
        ];
        if (_body.text.trim().isEmpty && readings.isEmpty) {
          showSnack(context, 'Write what was found or done, or add readings.');
          return;
        }
        save(
          () => ref
              .read(jobCardActionsProvider)
              .addWorkRecord(
                widget.job.id,
                kind: _kind,
                body: _body.text,
                readings: readings,
              ),
          done: 'Added to the work log',
        );
      },
      children: [
        DropdownField<String>(
          label: 'Type of entry',
          value: _kind,
          items: workRecordKinds,
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        const SizedBox(height: Space.sm),
        TextFormField(
          controller: _body,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Details'),
          validator: (v) =>
              (v?.length ?? 0) > 4000 ? 'Up to 4000 characters' : null,
        ),
        const SizedBox(height: Space.md),
        Text('Readings', style: Theme.of(context).textTheme.titleSmall),
        for (final (i, (n, v, u)) in _readings.indexed)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: n,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'What',
                      hintText: 'L1-N voltage',
                    ),
                    validator: (x) =>
                        v.text.trim().isNotEmpty && (x ?? '').trim().isEmpty
                        ? 'Name it'
                        : null,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: v,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Value',
                    ),
                    validator: (x) =>
                        n.text.trim().isNotEmpty && (x ?? '').trim().isEmpty
                        ? 'Value?'
                        : null,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: TextFormField(
                    controller: u,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Unit',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove reading',
                  onPressed: () => setState(() => _readings.removeAt(i)),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _readings.length >= 50 ? null : _addReading,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a reading'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Time corrections (engineers): fix a session, or enter missed time
// ---------------------------------------------------------------------------
class CorrectTimeSheet extends ConsumerStatefulWidget {
  const CorrectTimeSheet({
    super.key,
    required this.job,
    this.session,
    this.people = const [],
  });

  final JobCard job;

  /// The session to correct; null to enter time that was never started.
  final WorkSession? session;

  /// People who were on the job (for entering missed time).
  final List<(String, String)> people;

  @override
  ConsumerState<CorrectTimeSheet> createState() => _CorrectTimeSheetState();
}

class _CorrectTimeSheetState extends ConsumerState<CorrectTimeSheet>
    with _Saving {
  late DateTime? _start = widget.session?.startedAt;
  late DateTime? _end = widget.session?.endedAt;
  late String? _user = widget.session?.userId;
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: s == null ? 'Add the time' : 'Save correction',
      onSave: () {
        if (_start == null || (s == null && (_end == null || _user == null))) {
          showSnack(context, 'Give the person, start and end.');
          return;
        }
        final actions = ref.read(jobCardActionsProvider);
        save(
          () => s == null
              ? actions.addSession(
                  widget.job.id,
                  userId: _user!,
                  startedAt: _start!,
                  endedAt: _end!,
                  reason: _reason.text,
                )
              : actions.correctSession(
                  s.id,
                  startedAt: _start!,
                  endedAt: _end,
                  reason: _reason.text,
                ),
          done: 'Work time saved; the change is in the audit trail',
        );
      },
      children: [
        Text(
          s == null
              ? 'Enter work that was done but never started on the app.'
              : 'Correct ${s.name}\'s session. The original times are kept.',
        ),
        const SizedBox(height: Space.md),
        if (s == null) ...[
          DropdownField<String>(
            label: 'Person',
            required: true,
            value: _user,
            items: widget.people,
            onChanged: (v) => setState(() => _user = v),
          ),
          const SizedBox(height: Space.sm),
        ],
        DateTimeField(
          label: 'Started',
          value: _start,
          allowClear: false,
          lastDate: SiteTime.now(),
          onChanged: (v) => setState(() => _start = v),
        ),
        const SizedBox(height: Space.sm),
        DateTimeField(
          label: s != null && s.running
              ? 'Ended (leave empty if still working)'
              : 'Ended',
          value: _end,
          allowClear: s != null && s.running,
          lastDate: SiteTime.now(),
          onChanged: (v) => setState(() => _end = v),
        ),
        const SizedBox(height: Space.sm),
        TextFormField(
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason for the correction *',
          ),
          validator: Valid.length(5, 2000, 'The reason'),
        ),
      ],
    );
  }
}
