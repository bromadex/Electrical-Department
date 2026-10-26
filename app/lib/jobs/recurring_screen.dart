import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'job_editor.dart';
import 'job_rules.dart';
import 'jobs_repository.dart';

const _everyLabels = {
  'daily': 'Daily',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
};

/// Supervisors manage jobs that repeat (e.g. weekly lighting check). The
/// database creates each job at 06:00 Harare time on its next run date.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recurrencesProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Recurring jobs · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(CupertinoIcons.add),
        label: const Text('New recurring job'),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(recurrencesProvider),
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => ListView(
              children: [
                SizedBox(height: top + Space.xl),
                const Center(
                  child: EmptyState(
                    icon: CupertinoIcons.wifi_slash,
                    title: 'Offline',
                    message: 'Recurring jobs load when you are connected.',
                  ),
                ),
              ],
            ),
            data: (rows) => ListView(
              padding: EdgeInsets.fromLTRB(
                Space.md,
                top + Space.md,
                Space.md,
                120,
              ),
              children: [
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xl),
                    child: Center(
                      child: EmptyState(
                        icon: CupertinoIcons.repeat,
                        title: 'No recurring jobs',
                        message:
                            'Set up rounds that repeat, like a weekly lighting '
                            'check. Each one is posted automatically at 06:00.',
                      ),
                    ),
                  ),
                for (final (i, r) in rows.indexed)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: SurfaceCard(
                          onTap: () => _edit(context, ref, r),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                                child: Icon(
                                  CupertinoIcons.repeat,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['title'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    Text(
                                      [
                                        _everyLabels[r['every']] ?? r['every'],
                                        'next ${r['next_run']}',
                                        ?areaNames[r['area_id']],
                                        if (r['assignee_id'] != null)
                                          'to ${people[r['assignee_id']] ?? 'someone'}',
                                      ].join(' · '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              Pill(
                                label: JobPriority.parse(
                                  r['priority'] as String,
                                ).label,
                                color: JobPriority.parse(
                                  r['priority'] as String,
                                ).color,
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ).entrance(context, index: i.clamp(0, 8)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, Map<String, dynamic>? r) {
    showFormSheet(context, _RecurrenceForm(existing: r));
  }
}

class _RecurrenceForm extends ConsumerStatefulWidget {
  const _RecurrenceForm({this.existing});

  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_RecurrenceForm> createState() => _RecurrenceFormState();
}

class _RecurrenceFormState extends ConsumerState<_RecurrenceForm> {
  late final _title = TextEditingController(
    text: widget.existing?['title'] as String?,
  );
  late final _description = TextEditingController(
    text: widget.existing?['description'] as String?,
  );
  late JobPriority _priority = JobPriority.parse(
    (widget.existing?['priority'] as String?) ?? 'normal',
  );
  late String _every = (widget.existing?['every'] as String?) ?? 'weekly';
  late String? _areaId = widget.existing?['area_id'] as String?;
  late String? _assigneeId = widget.existing?['assignee_id'] as String?;
  late int _dueDays = (widget.existing?['due_days'] as num?)?.toInt() ?? 1;
  late DateTime _nextRun = widget.existing == null
      ? DateTime.now().add(const Duration(days: 1))
      : DateTime.parse(widget.existing!['next_run'] as String);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    if (_title.text.trim().length < 3) {
      setState(() => _error = 'Describe the job in a few words');
      return;
    }
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    HapticFeedback.mediumImpact();
    await ref
        .read(jobActionsProvider)
        .saveRecurrence(
          id: widget.existing?['id'] as String?,
          siteId: site.id,
          areaId: _areaId,
          title: _title.text,
          description: _description.text,
          priority: _priority,
          every: _every,
          nextRun: _nextRun,
          dueDays: _dueDays,
          assigneeId: _assigneeId,
          archived: archive,
        );
    // Give the queued save a moment to reach the server, then reload.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    ref.invalidate(recurrencesProvider);
    if (mounted) Navigator.pop(context);
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
            widget.existing == null
                ? 'New recurring job'
                : 'Edit recurring job',
            style: theme.textTheme.headlineSmall,
          ),
          label('What needs doing?'),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Weekly lighting check',
            ),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Details (optional)'),
          ),
          label('Repeats'),
          Center(
            child: GlassSegmented<String>(
              value: _every,
              segments: _everyLabels,
              onChanged: (v) => setState(() => _every = v),
            ),
          ),
          label('Priority'),
          Center(
            child: GlassSegmented<JobPriority>(
              value: _priority,
              segments: {for (final p in JobPriority.values) p: p.label},
              onChanged: (p) => setState(() => _priority = p),
            ),
          ),
          label('Next run and time allowed'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: Text(
                    MaterialLocalizations.of(context)
                        .formatMediumDate(_nextRun),
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _nextRun,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _nextRun = d);
                  },
                ),
              ),
              const SizedBox(width: Space.sm),
              DropdownButton<int>(
                value: _dueDays,
                items: [
                  for (final d in const [0, 1, 2, 3, 5, 7, 14])
                    DropdownMenuItem(
                      value: d,
                      child: Text(
                        d == 0
                            ? 'Due same day'
                            : d == 1
                            ? 'Due in 1 day'
                            : 'Due in $d days',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _dueDays = v ?? 1),
              ),
            ],
          ),
          if (areas.isNotEmpty) ...[
            label('Area'),
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
            ),
          ],
          label('Assign to'),
          people.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Connect to pick someone.'),
            data: (list) => DropdownButtonFormField<String?>(
              initialValue: _assigneeId,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Leave on the board'),
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
          if (widget.existing != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Stop repeating'),
            ),
          ],
        ],
      ),
    );
  }
}
