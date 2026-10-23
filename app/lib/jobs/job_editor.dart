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

/// Opens a sheet (phone) or dialog (desktop) with [child].
Future<T?> showFormSheet<T>(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        insetPadding: const EdgeInsets.all(Space.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: child,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    ),
  );
}

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

/// New job (no [job]) or edit an existing one.
Future<void> showJobEditor(BuildContext context, {LocalJob? job}) {
  return showFormSheet(context, _JobEditor(job: job));
}

class _JobEditor extends ConsumerStatefulWidget {
  const _JobEditor({this.job});

  final LocalJob? job;

  @override
  ConsumerState<_JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends ConsumerState<_JobEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.job?.title);
  late final _description = TextEditingController(
    text: widget.job?.description,
  );
  late JobPriority _priority = JobPriority.parse(
    widget.job?.priority ?? 'normal',
  );
  late String? _areaId = widget.job?.areaId;
  late DateTime? _due = widget.job?.dueAt;
  (double, double)? _location;
  bool _locating = false;
  List<Uint8List> _photos = [];

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
      );
    } else {
      await actions.edit(
        widget.job!,
        title: _title.text,
        description: _description.text,
        areaId: _areaId,
        priority: _priority,
        dueAt: _due,
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
