import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reference/reference_data.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/media.dart';
import '../ui/status.dart';
import 'models.dart';
import 'repository.dart';

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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
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
// Stage 4: holds
// ---------------------------------------------------------------------------
class HoldSheet extends ConsumerStatefulWidget {
  const HoldSheet({super.key, required this.job});

  final JobCard job;

  @override
  ConsumerState<HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends ConsumerState<HoldSheet> with _Saving {
  late String? _status = widget.job.status.isHold ? widget.job.status.db : null;
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: 'Put on hold',
      onSave: () {
        if (_status == null) {
          showSnack(context, 'Choose what the job is waiting for.');
          return;
        }
        save(
          () => ref
              .read(jobCardActionsProvider)
              .setStatus(widget.job.id, _status!, reason: _reason.text),
          done: 'Job card on hold',
        );
      },
      children: [
        ChoiceField<String>(
          label: 'What is the job waiting for? *',
          value: _status,
          onChanged: (v) => setState(() => _status = v),
          options: [
            for (final s in JobStatus.holds) (s.db, s.label, s.icon, s.color),
          ],
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _reason,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'e.g. Waiting for 63 A MCB from stores',
          ),
          validator: Valid.length(2, 2000, 'A reason'),
        ),
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
  late String? _after = widget.job.s('equipment_state_after');
  bool _checks = false;
  List<PickedFile> _files = const [];

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      formKey: formKey,
      busy: busy,
      saveLabel: 'Submit for review',
      onSave: () {
        if (_after == null) {
          showSnack(context, 'Record the equipment condition after the work.');
          return;
        }
        if (!_checks) {
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
          await actions.submit(
            widget.job.id,
            summary: _summary.text,
            findings: _findings.text,
            correctiveAction: _action.text,
            equipmentStateAfter: _after!,
            checksConfirmed: _checks,
          );
        }, done: 'Submitted for engineering review');
      },
      children: [
        TextFormField(
          controller: _summary,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Work completion summary *',
          ),
          validator: Valid.length(5, 4000, 'The summary'),
        ),
        const SizedBox(height: Space.sm),
        TextFormField(
          controller: _findings,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Fault cause or findings *',
          ),
          validator: Valid.length(2, 4000, 'The findings'),
        ),
        const SizedBox(height: Space.sm),
        TextFormField(
          controller: _action,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Corrective action taken *',
          ),
          validator: Valid.length(2, 4000, 'The corrective action'),
        ),
        const SizedBox(height: Space.md),
        ChoiceField<String>(
          label: 'Equipment condition after the work *',
          value: _after,
          onChanged: (v) => setState(() => _after = v),
          options: const [
            ('operational', 'Operational', null, AppColors.success),
            ('degraded', 'Degraded', null, AppColors.warning),
            ('out_of_service', 'Out of service', null, AppColors.critical),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(
          'After photos and test sheets',
          style: Theme.of(context).textTheme.titleSmall,
        ),
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
            'I confirm the required checks and the applicable safety procedures '
            '(isolation, permits, test before touch, safe reinstatement) were completed.',
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

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final reject = _decision == 'reject';
    return _FormBody(
      formKey: formKey,
      busy: busy,
      danger: reject,
      saveLabel: reject ? 'Return for more work' : 'Approve and close',
      onSave: () => save(
        () => ref
            .read(jobCardActionsProvider)
            .review(job.id, _decision, notes: _notes.text),
        done: reject ? 'Returned to the technician' : 'Job card closed',
      ),
      children: [
        KeyValue('Completion summary', job.s('completion_summary')),
        const SizedBox(height: Space.sm),
        KeyValue('Fault cause or findings', job.s('findings')),
        const SizedBox(height: Space.sm),
        KeyValue('Corrective action', job.s('corrective_action')),
        const SizedBox(height: Space.sm),
        KeyValue(
          'Equipment after the work',
          humanize(job.s('equipment_state_after')),
        ),
        const SizedBox(height: Space.sm),
        KeyValue('Submitted', fmtDateTime(job.t('submitted_at'))),
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
              'reject',
              'Return for more work',
              Icons.undo_rounded,
              AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: reject
                ? 'What still needs to be done? *'
                : 'Verification notes',
          ),
          validator: reject ? Valid.length(2, 2000, 'What needs doing') : null,
        ),
      ],
    );
  }
}
