import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../jobs/job_editor.dart';
import '../jobs/jobs_repository.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'checklists_repository.dart';
import '../widgets/app_back_button.dart';

/// Rounds at the current site: what is due, what is done, and (for
/// supervisors) building the templates.
class ChecklistsScreen extends ConsumerWidget {
  const ChecklistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(checklistTemplatesProvider);
    final status = ref.watch(checklistStatusProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canManage =
        site != null && session.can('checklists.manage', siteId: site.id);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Checklists · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showFormSheet(context, const ChecklistTemplateForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New checklist'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async {
            ref.invalidate(checklistTemplatesProvider);
            ref.invalidate(checklistStatusProvider);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: templates.when(
                      loading: () => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      error: (e, _) => [
                        EmptyState(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Could not load checklists',
                          message: AppError.from(e).message,
                        ),
                      ],
                      data: (list) => list.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.only(top: Space.xl),
                                child: EmptyState(
                                  icon: CupertinoIcons.checkmark_rectangle,
                                  title: 'No checklists yet',
                                  message: canManage
                                      ? 'Build rounds like a generator check or '
                                            'DB board inspection.'
                                      : 'A supervisor sets up the rounds.',
                                ),
                              ),
                            ]
                          : [
                              for (final (i, t) in list.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: Space.sm,
                                  ),
                                  child: ChecklistTile(
                                    template: t,
                                    status: status[t.id],
                                    onEdit: canManage
                                        ? () => showFormSheet(
                                            context,
                                            ChecklistTemplateForm(template: t),
                                          )
                                        : null,
                                  ),
                                ).entrance(context, index: i.clamp(0, 8)),
                            ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChecklistTile extends ConsumerWidget {
  const ChecklistTile({
    super.key,
    required this.template,
    this.status,
    this.onEdit,
  });

  final ChecklistTemplate template;
  final ChecklistStatus? status;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final people = ref.watch(peopleProvider).value ?? const {};
    final s = status;
    final dates = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final dueToday =
        s != null &&
        !s.done &&
        s.dueBy.year == now.year &&
        s.dueBy.month == now.month &&
        s.dueBy.day == now.day;

    return SurfaceCard(
      onTap: () => context.push('/checklists/${template.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (s?.done ?? false)
                  ? BrandColors.success.withValues(alpha: 0.14)
                  : scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(
              (s?.done ?? false)
                  ? CupertinoIcons.checkmark_alt
                  : CupertinoIcons.list_bullet,
              color: (s?.done ?? false) ? BrandColors.success : scheme.primary,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: theme.textTheme.titleSmall),
                Text(
                  [
                    frequencyLabels[template.frequency] ?? template.frequency,
                    '${template.items.length} items',
                    if (s?.done ?? false)
                      'done by ${people[s!.doneBy] ?? 'someone'}'
                    else if (template.assigneeId != null)
                      'for ${people[template.assigneeId] ?? 'someone'}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (s != null && s.done && s.failed > 0)
            Pill(label: '${s.failed} failed', color: Colors.red, dense: true)
          else if (s != null && s.done)
            const Pill(label: 'Done', color: BrandColors.success, dense: true)
          else if (dueToday)
            const Pill(label: 'Due today', color: Colors.orange, dense: true)
          else if (s != null)
            Pill(
              label: 'By ${dates.formatShortMonthDay(s.dueBy)}',
              dense: true,
            ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit checklist',
              icon: const Icon(CupertinoIcons.pencil, size: 20),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

/// Builds a checklist: name, how often, who, and its items.
class ChecklistTemplateForm extends ConsumerStatefulWidget {
  const ChecklistTemplateForm({super.key, this.template});

  final ChecklistTemplate? template;

  @override
  ConsumerState<ChecklistTemplateForm> createState() =>
      _ChecklistTemplateFormState();
}

class _ChecklistTemplateFormState extends ConsumerState<ChecklistTemplateForm> {
  late final _name = TextEditingController(text: widget.template?.name);
  late final _description = TextEditingController(
    text: widget.template?.description,
  );
  late String _frequency = widget.template?.frequency ?? 'daily';
  late String? _areaId = widget.template?.areaId;
  late String? _assigneeId = widget.template?.assigneeId;
  late final List<ChecklistItem> _items = [
    for (final i in widget.template?.items ?? const <ChecklistItem>[])
      ChecklistItem(
        id: i.id,
        label: i.label,
        kind: i.kind,
        unit: i.unit,
        min: i.min,
        max: i.max,
        photoRequired: i.photoRequired,
      ),
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_name.text.trim().length < 3) {
      setState(() => _error = 'Name the checklist');
      return;
    }
    final items = _items.where((i) => i.label.trim().length >= 2).toList();
    if (items.isEmpty && !archive) {
      setState(() => _error = 'Add at least one item');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await ref
          .read(checklistActionsProvider)
          .saveTemplate(
            id: widget.template?.id,
            siteId: widget.template?.siteId ?? site.id,
            areaId: _areaId,
            name: _name.text,
            description: _description.text,
            frequency: _frequency,
            assigneeId: _assigneeId,
            items: items,
            archived: archive,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    final people = site == null
        ? const AsyncValue<List<Assignee>>.data([])
        : ref.watch(assigneesProvider(site.id));
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );

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
          Text(
            widget.template == null ? 'New checklist' : 'Edit checklist',
            style: theme.textTheme.headlineSmall,
          ),
          label('Name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Generator daily round',
            ),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Instructions (optional)',
            ),
          ),
          label('How often'),
          Wrap(
            spacing: Space.xs,
            children: [
              for (final f in frequencyLabels.entries)
                ChoiceChip(
                  label: Text(f.value),
                  selected: _frequency == f.key,
                  onSelected: (_) => setState(() => _frequency = f.key),
                ),
            ],
          ),
          if (areas.isNotEmpty) ...[
            label('Area'),
            DropdownButtonFormField<String?>(
              initialValue: _areaId,
              items: [
                const DropdownMenuItem(value: null, child: Text('Whole site')),
                for (final a in areas)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ],
          label('Who does it'),
          people.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Connect to pick someone.'),
            data: (list) => DropdownButtonFormField<String?>(
              initialValue: list.any((p) => p.id == _assigneeId)
                  ? _assigneeId
                  : null,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Anyone on site'),
                ),
                for (final p in list)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name.isEmpty ? 'Unnamed' : p.name),
                  ),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
          ),
          label('Items'),
          for (final (i, item) in _items.indexed)
            Padding(
              key: ObjectKey(item),
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _ItemEditor(
                index: i,
                item: item,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _items.removeAt(i)),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _items.add(ChecklistItem(label: ''))),
            icon: const Icon(CupertinoIcons.add),
            label: const Text('Add item'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Save'),
          ),
          if (widget.template != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Stop this checklist'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final ChecklistItem item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _label = TextEditingController(text: widget.item.label);
  late final _unit = TextEditingController(text: widget.item.unit);
  late final _min = TextEditingController(
    text: widget.item.min?.toString() ?? '',
  );
  late final _max = TextEditingController(
    text: widget.item.max?.toString() ?? '',
  );

  @override
  void dispose() {
    for (final c in [_label, _unit, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, 0, Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${widget.index + 1}.'),
              const SizedBox(width: Space.xs),
              Expanded(
                child: TextField(
                  controller: _label,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Oil level OK',
                    isDense: true,
                  ),
                  onChanged: (v) => item.label = v,
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                icon: const Icon(CupertinoIcons.minus_circle),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          Wrap(
            spacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final k in const {
                'check': 'OK / not OK',
                'number': 'Reading',
                'text': 'Note',
              }.entries)
                ChoiceChip(
                  label: Text(k.value),
                  selected: item.kind == k.key,
                  onSelected: (_) {
                    item.kind = k.key;
                    widget.onChanged();
                  },
                ),
              FilterChip(
                label: const Text('Photo'),
                avatar: const Icon(CupertinoIcons.camera, size: 16),
                selected: item.photoRequired,
                onSelected: (v) {
                  item.photoRequired = v;
                  widget.onChanged();
                },
              ),
            ],
          ),
          if (item.kind == 'number')
            Padding(
              padding: const EdgeInsets.only(top: Space.xs, right: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _min,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Min',
                        isDense: true,
                      ),
                      onChanged: (v) => item.min = _num(v),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: TextField(
                      controller: _max,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Max',
                        isDense: true,
                      ),
                      onChanged: (v) => item.max = _num(v),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        hintText: 'Unit',
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          item.unit = v.trim().isEmpty ? null : v.trim(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
