import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../procurement/procurement_repository.dart';
import '../services/session_controller.dart';
import '../store/store_repository.dart' show qtyText, openJobCardsProvider;
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'projects_repository.dart';

void _say(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppError.from(e).isRetryable
              ? 'Connect to the internet for that.'
              : AppError.from(e).message,
        ),
      ),
    );

/// A ring showing how far a project is.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 52});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: size / 9,
              backgroundColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.1,
              ),
              color: value >= 1
                  ? BrandColors.success
                  : theme.colorScheme.primary,
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(fontSize: size / 4.2, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Projects at the current site.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final canManage = ref
        .watch(sessionProvider)
        .can('projects.manage', siteId: site?.id);
    final projects = ref.watch(projectsProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Projects · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showFormSheet<void>(context, const ProjectForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New project'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(projectsProvider),
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
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: projects.when(
                      loading: () => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      error: (e, _) => [
                        EmptyState(
                          icon: CupertinoIcons.wifi_slash,
                          title: 'Could not load projects',
                          message: AppError.from(e).message,
                        ),
                      ],
                      data: (list) => [
                        if (list.isEmpty)
                          const EmptyState(
                            icon: CupertinoIcons.flag,
                            title: 'No projects yet',
                            message:
                                'Supervisors group job cards, materials and a '
                                'BOQ into projects here.',
                          ),
                        for (final (i, p) in list.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: SurfaceCard(
                              onTap: () => context.push('/projects/${p.id}'),
                              child: Row(
                                children: [
                                  ProgressRing(value: p.progress),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            RecordCode(p.code),
                                            const SizedBox(width: Space.xs),
                                            Expanded(
                                              child: Text(
                                                p.name,
                                                style:
                                                    theme.textTheme.titleSmall,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            '${p.jobsDone} of ${p.jobsTotal} job cards done',
                                            if (p.targetDate != null)
                                              'due ${dates.formatShortMonthDay(p.targetDate!)}',
                                          ].join(' · '),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: p.overdue(today)
                                                    ? Colors.red
                                                    : null,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (p.status != 'active')
                                    Pill(
                                      label: projectStatuses[p.status]!,
                                      dense: true,
                                    ),
                                ],
                              ),
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

/// One project: progress, team, job cards, materials and its BOQ.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(projectProvider(id));
    final p = project.value;
    final session = ref.watch(sessionProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final canManage =
        p != null && session.can('projects.manage', siteId: p.siteId);
    final canLink =
        canManage || (p != null && session.can('jc.assign', siteId: p.siteId));
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/projects'),
        title: Text(p?.code ?? 'Project'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Edit project',
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () =>
                  showFormSheet<void>(context, ProjectForm(project: p)),
            ),
        ],
      ),
      body: MeshBackground(
        child: p == null
            ? Center(
                child: project.isLoading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        icon: CupertinoIcons.flag,
                        title: 'Project not found',
                        message: 'It may have been archived.',
                      ),
              )
            : RefreshIndicator(
                edgeOffset: top,
                onRefresh: () async {
                  ref.invalidate(projectProvider(id));
                  ref.invalidate(projectJobsProvider(id));
                  ref.invalidate(projectMaterialsProvider(id));
                  ref.invalidate(boqProvider(id));
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Space.md,
                    top + Space.md,
                    Space.md,
                    Space.xl,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SurfaceCard(
                              padding: const EdgeInsets.all(Space.lg),
                              child: Row(
                                children: [
                                  ProgressRing(value: p.progress, size: 76),
                                  const SizedBox(width: Space.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: theme.textTheme.headlineSmall,
                                        ),
                                        const SizedBox(height: Space.xs),
                                        Wrap(
                                          spacing: Space.xs,
                                          runSpacing: Space.xs,
                                          children: [
                                            Pill(
                                              label: projectStatuses[p.status]!,
                                            ),
                                            if (p.targetDate != null)
                                              Pill(
                                                label:
                                                    'Due ${dates.formatShortMonthDay(p.targetDate!)}',
                                              ),
                                            Pill(
                                              label:
                                                  '${p.jobsDone}/${p.jobsTotal} job cards',
                                            ),
                                          ],
                                        ),
                                        if (p.ownerId != null &&
                                            people[p.ownerId] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: Space.xs,
                                            ),
                                            child: Text(
                                              'Led by ${people[p.ownerId]}',
                                              style:
                                                  theme.textTheme.labelMedium,
                                            ),
                                          ),
                                        if (p.description != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: Space.xs,
                                            ),
                                            child: Text(p.description!),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (p.memberIds.isNotEmpty) ...[
                              const SizedBox(height: Space.md),
                              Panel(
                                icon: CupertinoIcons.person_2,
                                title: 'Team',
                                child: Wrap(
                                  spacing: Space.sm,
                                  runSpacing: Space.sm,
                                  children: [
                                    for (final m in p.memberIds)
                                      Chip(
                                        avatar: AppAvatar(
                                          name: people[m] ?? '?',
                                          size: 24,
                                        ),
                                        label: Text(people[m] ?? 'Someone'),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: Space.md),
                            _ProjectJobs(project: p, canLink: canLink),
                            const SizedBox(height: Space.md),
                            _ProjectMaterials(project: p),
                            const SizedBox(height: Space.md),
                            BoqPanel(project: p, canManage: canManage),
                          ],
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

class _ProjectJobs extends ConsumerWidget {
  const _ProjectJobs({required this.project, required this.canLink});

  final Project project;
  final bool canLink;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final jobs = await ref.read(openJobCardsProvider.future);
    if (!context.mounted) return;
    final pick = await showFormSheet<String>(context, _JobPicker(jobs: jobs));
    if (pick == null || !context.mounted) return;
    try {
      await ref.read(projectActionsProvider).setJobProject(pick, project.id);
    } catch (e) {
      if (context.mounted) _say(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(projectJobsProvider(project.id));
    return Panel(
      icon: CupertinoIcons.doc_text,
      title: 'Job cards',
      actions: [
        if (canLink)
          TextButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: const Text('Add'),
          ),
      ],
      child: jobs.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(AppError.from(e).message),
        data: (list) => list.isEmpty
            ? Text(
                'Add the job cards that make up this project; progress '
                'follows them.',
                style: Theme.of(context).textTheme.labelMedium,
              )
            : Column(
                children: [
                  for (final j in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onTap: () => context.push('/jobs/${j.number}'),
                      leading: Icon(
                        j.status == 'closed'
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color: j.status == 'closed'
                            ? BrandColors.success
                            : null,
                      ),
                      title: Text('${j.number} · ${j.title}'),
                      subtitle: Text(j.status.replaceAll('_', ' ')),
                      trailing: canLink
                          ? IconButton(
                              tooltip: 'Take off the project',
                              icon: const Icon(CupertinoIcons.minus_circle),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(projectActionsProvider)
                                      .setJobProject(
                                        j.id,
                                        null,
                                        previous: project.id,
                                      );
                                } catch (e) {
                                  if (context.mounted) _say(context, e);
                                }
                              },
                            )
                          : null,
                    ),
                ],
              ),
      ),
    );
  }
}

class _JobPicker extends StatefulWidget {
  const _JobPicker({required this.jobs});

  final List<({String id, String number, String title})> jobs;

  @override
  State<_JobPicker> createState() => _JobPickerState();
}

class _JobPickerState extends State<_JobPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final shown = [
      for (final j in widget.jobs)
        if (q.isEmpty ||
            j.number.toLowerCase().contains(q) ||
            j.title.toLowerCase().contains(q))
          j,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a job card',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.sm),
          CupertinoSearchTextField(onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: Space.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final j in shown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${j.number} · ${j.title}'),
                    onTap: () => Navigator.pop(context, j.id),
                  ),
                if (shown.isEmpty) const Text('No open job cards match.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMaterials extends ConsumerWidget {
  const _ProjectMaterials({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materials = ref.watch(projectMaterialsProvider(project.id));
    final requests = ref.watch(materialRequestsProvider(project.id));
    final canRequest = ref
        .watch(sessionProvider)
        .can('mr.create', siteId: project.siteId);
    return Panel(
      icon: CupertinoIcons.cube_box,
      title: 'Materials',
      actions: [
        if (canRequest)
          TextButton.icon(
            onPressed: () =>
                context.push('/materials/new?project=${project.id}'),
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: const Text('Request'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...materials.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(AppError.from(e).message)],
            data: (list) => [
              if (list.isEmpty)
                Text(
                  'Nothing issued from inventory yet.',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              for (final m in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(m.name),
                  trailing: Text('${qtyText(m.qty)} ${m.unit} issued'),
                ),
            ],
          ),
          ...?requests.value?.map(
            (r) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(CupertinoIcons.doc_plaintext),
              title: Text('${r.code} · ${r.lines.length} lines'),
              subtitle: Text(mrStatuses[r.status] ?? r.status),
              onTap: () => context.push('/materials/${r.id}'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The project's bill of quantities against what was issued, requested,
/// ordered and in stock; import from a spreadsheet and request the shortfall.
class BoqPanel extends ConsumerWidget {
  const BoqPanel({super.key, required this.project, required this.canManage});

  final Project project;
  final bool canManage;

  Future<void> _shortfall(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref
          .read(procurementActionsProvider)
          .shortfallToRequest(project.id);
      if (!context.mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing is short: all requested.')),
        );
      } else {
        context.push('/materials/$id');
      }
    } catch (e) {
      if (context.mounted) _say(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final boq = ref.watch(boqProvider(project.id));
    final canRequest = ref
        .watch(sessionProvider)
        .can('mr.create', siteId: project.siteId);
    final short = boq.value?.where((b) => b.toRequest > 0).length ?? 0;
    return Panel(
      icon: CupertinoIcons.list_number,
      title: 'Bill of quantities',
      actions: [
        if (canManage)
          TextButton.icon(
            onPressed: () =>
                showFormSheet<void>(context, BoqImportSheet(project: project)),
            icon: const Icon(CupertinoIcons.arrow_down_doc, size: 18),
            label: const Text('Import'),
          ),
      ],
      child: boq.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(AppError.from(e).message),
        data: (lines) => lines.isEmpty
            ? Text(
                'Import the BOQ from a spreadsheet to compare it with what '
                'was issued, ordered and in stock.',
                style: theme.textTheme.labelMedium,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: _BoqRow(line: b),
                    ),
                  if (short > 0 && canRequest)
                    FilledButton.icon(
                      onPressed: () => _shortfall(context, ref),
                      icon: const Icon(CupertinoIcons.cart_badge_plus),
                      label: Text(
                        'Request the shortfall ($short '
                        '${short == 1 ? 'line' : 'lines'})',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _BoqRow extends StatelessWidget {
  const _BoqRow({required this.line});

  final BoqLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = line;
    final covered = b.qty == 0
        ? 1.0
        : ((b.issued + b.requested + b.onOrder) / b.qty).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                b.description,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${qtyText(b.issued)} / ${qtyText(b.qty)} ${b.unit}',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: covered,
            minHeight: 6,
            color: b.toRequest > 0 ? Colors.orange : BrandColors.success,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (b.requested > 0) '${qtyText(b.requested)} requested',
            if (b.onOrder > 0) '${qtyText(b.onOrder)} on order',
            if (b.itemId != null) '${qtyText(b.inStock)} in inventory',
            if (b.toRequest > 0) '${qtyText(b.toRequest)} short' else 'covered',
          ].join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
            color: b.toRequest > 0 ? Colors.orange : null,
          ),
        ),
      ],
    );
  }
}

/// Paste the BOQ from a spreadsheet, or pick a CSV file.
class BoqImportSheet extends ConsumerStatefulWidget {
  const BoqImportSheet({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<BoqImportSheet> createState() => _BoqImportSheetState();
}

class _BoqImportSheetState extends ConsumerState<BoqImportSheet> {
  final _text = TextEditingController();
  bool _replace = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt', 'tsv'],
    );
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    setState(() => _text.text = String.fromCharCodes(bytes));
  }

  Future<void> _import() async {
    final lines = parseBoq(_text.text);
    if (lines.isEmpty) {
      setState(() => _error = 'No lines with a quantity found');
      return;
    }
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(procurementActionsProvider)
          .importBoq(widget.project.id, lines, replace: _replace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$n BOQ lines loaded')));
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = parseBoq(_text.text).length;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Import BOQ', style: theme.textTheme.headlineSmall),
          Text(
            'Copy three columns from Excel (description, unit, quantity) and '
            'paste them here, or pick a CSV file. Names that match inventory '
            'items are linked to them.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '2.5mm twin and earth\tm\t500\nIsolator 63A\tpcs\t4',
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickCsv,
                icon: const Icon(CupertinoIcons.doc),
                label: const Text('CSV file'),
              ),
              const Spacer(),
              Text(
                '$found ${found == 1 ? 'line' : 'lines'} found',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Replace the current BOQ'),
            value: _replace,
            onChanged: (v) => setState(() => _replace = v),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _busy || found == 0 ? null : _import,
            child: Text('Load $found ${found == 1 ? 'line' : 'lines'}'),
          ),
        ],
      ),
    );
  }
}

/// Creates or edits a project.
class ProjectForm extends ConsumerStatefulWidget {
  const ProjectForm({super.key, this.project});

  final Project? project;

  @override
  ConsumerState<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<ProjectForm> {
  late final _name = TextEditingController(text: widget.project?.name);
  late final _description = TextEditingController(
    text: widget.project?.description,
  );
  late DateTime? _target = widget.project?.targetDate;
  late String? _owner = widget.project?.ownerId;
  late String _status = widget.project?.status ?? 'active';
  late final Set<String> _members = {...?widget.project?.memberIds};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_name.text.trim().length < 3) {
      setState(() => _error = 'Name the project');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final id = await ref
          .read(projectActionsProvider)
          .save(
            project: widget.project,
            siteId: widget.project?.siteId ?? site.id,
            name: _name.text,
            description: _description.text,
            targetDate: _target,
            ownerId: _owner,
            status: _status,
            members: _members.toList(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      if (widget.project == null) context.push('/projects/$id');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = ref.watch(peopleProvider).value ?? const {};
    final names = people.entries.where((e) => e.value.isNotEmpty).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final dates = MaterialLocalizations.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.project == null
                ? 'New project'
                : 'Edit ${widget.project!.code}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Substation 3 upgrade',
            ),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What it covers'),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _target ?? now.add(const Duration(days: 30)),
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365 * 3)),
              );
              if (d != null) setState(() => _target = d);
            },
            icon: const Icon(CupertinoIcons.calendar),
            label: Text(
              _target == null
                  ? 'Target date (optional)'
                  : 'Due ${dates.formatMediumDate(_target!)}',
            ),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<String?>(
            initialValue: _owner,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Led by'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Nobody yet')),
              for (final p in names)
                DropdownMenuItem(value: p.key, child: Text(p.value)),
            ],
            onChanged: (v) => setState(() => _owner = v),
          ),
          if (widget.project != null) ...[
            label('Status'),
            Wrap(
              spacing: Space.xs,
              children: [
                for (final s in projectStatuses.entries)
                  ChoiceChip(
                    label: Text(s.value),
                    selected: _status == s.key,
                    onSelected: (_) => setState(() => _status = s.key),
                  ),
              ],
            ),
          ],
          label('Team'),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final p in names)
                FilterChip(
                  label: Text(p.value),
                  selected: _members.contains(p.key),
                  onSelected: (on) => setState(
                    () => on ? _members.add(p.key) : _members.remove(p.key),
                  ),
                ),
            ],
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
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.project == null ? 'Create project' : 'Save'),
          ),
        ],
      ),
    );
  }
}
