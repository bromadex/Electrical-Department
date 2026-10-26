import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/surfaces.dart';
import 'job_rules.dart';
import 'jobs_repository.dart';
import 'media.dart';
import '../ui/form_sheet.dart';

export '../ui/form_sheet.dart';

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    required this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          ...children,
          const SizedBox(height: Space.lg),
          action,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// New job, or edit [job]. [assetId] starts a new job on that asset;
/// [title] and [description] prefill a new job (e.g. from a chat message).
Future<void> showJobEditor(
  BuildContext context, {
  LocalJob? job,
  String? assetId,
  String? title,
  String? description,
}) {
  return showFormSheet(
    context,
    _JobEditor(
      job: job,
      assetId: assetId,
      title: title,
      description: description,
    ),
  );
}

class _JobEditor extends ConsumerStatefulWidget {
  const _JobEditor({this.job, this.assetId, this.title, this.description});

  final LocalJob? job;
  final String? assetId;
  final String? title;
  final String? description;

  @override
  ConsumerState<_JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends ConsumerState<_JobEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.job?.title ?? widget.title,
  );
  late final _description = TextEditingController(
    text: widget.job?.description ?? widget.description,
  );
  late JobPriority _priority = JobPriority.parse(
    widget.job?.priority ?? 'normal',
  );
  late String? _areaId = widget.job?.areaId;
  late DateTime? _due = widget.job?.dueAt;
  (double, double)? _location;
  bool _locating = false;
  List<Uint8List> _photos = [];
  String? _assigneeId;
  late String? _assetId = widget.job?.assetId ?? widget.assetId;
  late bool _preventive = widget.job?.maintenanceType == 'preventive';
  late bool _isolation = widget.job?.isolationRequired ?? false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _due ?? now.add(const Duration(hours: 4)),
      ),
    );
    if (!mounted) return;
    setState(() {
      _due = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 17,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final loc = await currentLocation(context);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _location = loc ?? _location;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    final actions = ref.read(jobActionsProvider);
    HapticFeedback.mediumImpact();
    if (widget.job == null) {
      await actions.create(
        siteId: site.id,
        areaId: _areaId,
        title: _title.text,
        description: _description.text,
        priority: _priority,
        dueAt: _due,
        lat: _location?.$1,
        lng: _location?.$2,
        photos: _photos,
        assigneeId: _assigneeId,
        assetId: _assetId,
        preventive: _preventive,
        isolationRequired: _isolation,
      );
    } else {
      await actions.edit(
        widget.job!,
        title: _title.text,
        description: _description.text,
        areaId: _areaId,
        priority: _priority,
        dueAt: _due,
        assetId: _assetId,
        preventive: _preventive,
        isolationRequired: _isolation,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.job != null;
    final assets = ref.watch(siteAssetsProvider).value ?? const [];

    return Form(
      key: _form,
      child: _SheetFrame(
        title: editing ? 'Edit ${widget.job!.code ?? 'job'}' : 'New job',
        action: FilledButton.icon(
          onPressed: _save,
          icon: Icon(
            editing
                ? CupertinoIcons.check_mark
                : CupertinoIcons.paperplane_fill,
          ),
          label: Text(editing ? 'Save changes' : 'Post job'),
        ),
        children: [
          if (site != null && !editing)
            Align(
              alignment: Alignment.centerLeft,
              child: Pill(
                label: site.name,
                icon: CupertinoIcons.location_solid,
              ),
            ),
          const _Label('What needs doing?'),
          TextFormField(
            controller: _title,
            autofocus: !editing,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'e.g. Replace isolator on MCC panel 3',
              counterText: '',
            ),
            validator: (v) => (v ?? '').trim().length < 3
                ? 'Describe the job in a few words'
                : null,
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Details (optional)'),
          ),
          const _Label('Priority'),
          Center(
            child: GlassSegmented<JobPriority>(
              value: _priority,
              segments: {for (final p in JobPriority.values) p: p.label},
              onChanged: (p) => setState(() => _priority = p),
            ),
          ),
          if (areas.isNotEmpty) ...[
            const _Label('Area'),
            DropdownButtonFormField<String?>(
              initialValue: _areaId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('No specific area'),
                ),
                for (final a in areas)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _areaId = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.map_pin_ellipse),
              ),
            ),
          ],
          if (assets.isNotEmpty) ...[
            const _Label('Asset'),
            DropdownButtonFormField<String?>(
              initialValue: assets.any((a) => a.id == _assetId)
                  ? _assetId
                  : null,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('No asset')),
                for (final a in assets)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.tag} · ${a.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _assetId = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.gear_alt),
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: 4,
            ),
            child: Column(
              children: [
                _SwitchRow(
                  icon: CupertinoIcons.lock_fill,
                  label: 'Isolation (lock-out) required',
                  value: _isolation,
                  onChanged: (v) => setState(() => _isolation = v),
                ),
                _SwitchRow(
                  icon: CupertinoIcons.calendar_badge_plus,
                  label: 'Planned maintenance',
                  value: _preventive,
                  onChanged: (v) => setState(() => _preventive = v),
                ),
              ],
            ),
          ),
          if (!editing &&
              site != null &&
              session.can('jobs.assign', siteId: site.id)) ...[
            const _Label('Assign to'),
            ref
                .watch(assigneesProvider(site.id))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text(
                    'Connect to pick someone; you can assign it later.',
                  ),
                  data: (people) => DropdownButtonFormField<String?>(
                    initialValue: _assigneeId,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Leave on the board for anyone'),
                      ),
                      for (final p in people)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.name.isEmpty ? 'Unnamed' : p.name}'
                            ' · ${p.openJobs} open',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _assigneeId = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(CupertinoIcons.person_badge_plus),
                    ),
                  ),
                ),
          ],
          const _Label('Due'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(CupertinoIcons.calendar),
                  label: Text(
                    _due == null
                        ? 'No due date'
                        : '${MaterialLocalizations.of(context).formatMediumDate(_due!)} '
                              '${TimeOfDay.fromDateTime(_due!).format(context)}',
                  ),
                ),
              ),
              if (_due != null)
                IconButton(
                  tooltip: 'Clear due date',
                  onPressed: () => setState(() => _due = null),
                  icon: const Icon(CupertinoIcons.clear_circled),
                ),
            ],
          ),
          if (!editing) ...[
            const _Label('Photos'),
            PhotoStrip(
              photos: _photos,
              onChanged: (p) => setState(() => _photos = p),
            ),
            const SizedBox(height: Space.sm),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: 4,
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.location_fill,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      _location == null
                          ? 'Attach my location'
                          : 'Location attached (${_location!.$1.toStringAsFixed(5)}, '
                                '${_location!.$2.toStringAsFixed(5)})',
                    ),
                  ),
                  if (_locating)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    CupertinoSwitch(
                      value: _location != null,
                      activeTrackColor: scheme.primary,
                      onChanged: (on) =>
                          on ? _locate() : setState(() => _location = null),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary, size: 20),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(label)),
        CupertinoSwitch(
          value: value,
          activeTrackColor: scheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Asks for a short reason (waiting for…, cancel because…).
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String action,
  bool required = true,
}) {
  final controller = TextEditingController();
  return showFormSheet<String>(
    context,
    _SheetFrame(
      title: title,
      action: FilledButton(
        onPressed: () {
          if (required && controller.text.trim().isEmpty) return;
          Navigator.pop(context, controller.text.trim());
        },
        child: Text(action),
      ),
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    ),
  );
}

/// Close a job: after photos (at least one) and a note.
Future<bool?> showCloseJob(BuildContext context, LocalJob job) {
  return showFormSheet<bool>(context, _CloseJob(job: job));
}

class _CloseJob extends ConsumerStatefulWidget {
  const _CloseJob({required this.job});

  final LocalJob job;

  @override
  ConsumerState<_CloseJob> createState() => _CloseJobState();
}

class _CloseJobState extends ConsumerState<_CloseJob> {
  final _note = TextEditingController();
  List<Uint8List> _photos = [];
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final hasServerAfter =
        ref
            .read(jobDetailProvider(widget.job.id))
            .value
            ?.photos
            .any((p) => p.kind == 'after') ??
        false;
    if (_photos.isEmpty && !hasServerAfter) {
      setState(() => _error = 'Add at least one after photo');
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Say what was done');
      return;
    }
    HapticFeedback.heavyImpact();
    await ref
        .read(jobActionsProvider)
        .close(widget.job, note: _note.text, afterPhotos: _photos);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SheetFrame(
      title: 'Close ${widget.job.code ?? 'job'}',
      action: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: BrandColors.success),
        onPressed: _close,
        icon: const Icon(CupertinoIcons.checkmark_seal_fill),
        label: const Text('Mark as done'),
      ),
      children: [
        const _Label('After photos'),
        PhotoStrip(
          photos: _photos,
          label: 'Add after photo',
          onChanged: (p) => setState(() {
            _photos = p;
            _error = null;
          }),
        ),
        const _Label('What was done?'),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
          decoration: const InputDecoration(
            hintText: 'e.g. Replaced isolator, tested and energised',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }
}

/// Supervisor picks who does the job.
Future<void> showAssignJob(BuildContext context, LocalJob job) {
  return showFormSheet(context, _AssignJob(job: job));
}

class _AssignJob extends ConsumerWidget {
  const _AssignJob({required this.job});

  final LocalJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(assigneesProvider(job.siteId));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign ${job.code ?? 'job'}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          Flexible(
            child: people.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  const Text('Could not load the team. Check your connection.'),
              data: (list) => ListView(
                shrinkWrap: true,
                children: [
                  if (job.assigneeId != null)
                    ListTile(
                      leading: const Icon(
                        CupertinoIcons.person_crop_circle_badge_xmark,
                      ),
                      title: const Text('Unassign'),
                      onTap: () {
                        ref.read(jobActionsProvider).assign(job, null);
                        Navigator.pop(context);
                      },
                    ),
                  for (final p in list)
                    ListTile(
                      leading: AppAvatar(name: p.name, size: 36),
                      title: Text(p.name.isEmpty ? 'Unnamed' : p.name),
                      subtitle: Text(
                        p.openJobs == 1
                            ? '1 open job'
                            : '${p.openJobs} open jobs',
                      ),
                      trailing: p.id == job.assigneeId
                          ? Icon(
                              CupertinoIcons.checkmark_alt,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(jobActionsProvider).assign(job, p.id);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pre-work safety check items; they match `_safety_items()` in
/// migration 0009.
const safetyItems = [
  'Hazards identified',
  'Correct PPE worn',
  'Work area made safe',
  'Isolation points identified and agreed',
  'Lockout/tagout applied',
  'Isolation verified',
  'Tested before touch',
];

/// Before starting a job that needs isolation: tick every item and give the
/// lock or permit number. Returns true when recorded.
Future<bool?> showSafetyCheck(BuildContext context, LocalJob job) {
  return showFormSheet<bool>(context, _SafetyCheck(job: job));
}

class _SafetyCheck extends ConsumerStatefulWidget {
  const _SafetyCheck({required this.job});

  final LocalJob job;

  @override
  ConsumerState<_SafetyCheck> createState() => _SafetyCheckState();
}

class _SafetyCheckState extends ConsumerState<_SafetyCheck> {
  final _ticked = <String>{};
  final _reference = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_ticked.length < safetyItems.length) {
      setState(() => _error = 'Confirm every item');
      return;
    }
    if (_reference.text.trim().isEmpty) {
      setState(() => _error = 'Enter the lock or permit number');
      return;
    }
    HapticFeedback.heavyImpact();
    await ref
        .read(jobActionsProvider)
        .recordSafetyCheck(
          widget.job,
          items: safetyItems,
          reference: _reference.text,
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SheetFrame(
      title: 'Safety check · ${widget.job.code ?? 'job'}',
      action: FilledButton.icon(
        onPressed: _confirm,
        icon: const Icon(CupertinoIcons.lock_shield_fill),
        label: const Text('Confirm and start'),
      ),
      children: [
        Text(
          'This job needs isolation. Confirm each step before work starts.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.sm),
        for (final item in safetyItems)
          CheckboxListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _ticked.contains(item),
            title: Text(item),
            onChanged: (v) => setState(() {
              v == true ? _ticked.add(item) : _ticked.remove(item);
              _error = null;
            }),
          ),
        const _Label('Lock or permit number'),
        TextField(
          controller: _reference,
          decoration: const InputDecoration(
            hintText: 'e.g. Lock 12 / PTW-0456',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }
}
