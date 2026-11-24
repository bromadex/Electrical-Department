import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../ui/form_sheet.dart';
import '../data/site_data.dart';
import '../widgets/app_back_button.dart';
import '../widgets/site_picker.dart';
import 'closures.dart';

const everyLabels = {
  'daily': 'Every day',
  'weekdays': 'Weekdays (Mon–Fri)',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
  'quarterly': 'Every 3 months',
  'yearly': 'Yearly',
};

/// Who does a planned job: nobody in particular (assigned by hand), one
/// person, or people taking turns.
enum _Who { anyone, one, turns }

/// "Takes turns: Tendai → Farai → Kuda (next: Farai)".
String turnsText(List<String> ids, int next, Map<String, String> people) {
  if (ids.isEmpty) return '';
  String name(String id) => (people[id] ?? 'someone').split(' ').first;
  final who = ids.map(name).join(' → ');
  return 'turns: $who (next ${name(ids[next % ids.length])})';
}

/// Supervisors manage jobs that repeat (e.g. weekly lighting check). The
/// database creates each job at 06:00 Harare time on its next run date.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recurrencesProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final areaNames = {for (final a in session.areas) a.id: a.name};
    final assetTags = {
      for (final a in ref.watch(siteAssetsProvider).value ?? const [])
        a.id: a.tag,
    };
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/jobs'),
        title: const Text('Planned maintenance'),
        actions: [
          const SiteFilterChip(),
          IconButton(
            tooltip: 'Shutdowns and holidays',
            icon: const Icon(CupertinoIcons.moon_zzz),
            onPressed: () => context.push('/closures'),
          ),
          const SizedBox(width: Space.xs),
        ],
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(CupertinoIcons.add),
        label: const Text('New planned job'),
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
                    message:
                        'Planned maintenance loads when you are connected.',
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
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ClosureNotice(
                      site: ref.watch(siteFilterProvider),
                      planned: true,
                    ),
                  ),
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xl),
                    child: Center(
                      child: EmptyState(
                        icon: CupertinoIcons.repeat,
                        title: 'No planned maintenance yet',
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
                                        everyLabels[r['every']] ?? r['every'],
                                        'next ${r['next_run']}',
                                        ?areaNames[r['area_id']],
                                        ?assetTags[r['asset_id']],
                                        if ((r['rotation'] as List?)
                                                ?.isNotEmpty ??
                                            false)
                                          turnsText(
                                            [
                                              for (final u
                                                  in r['rotation'] as List)
                                                '$u',
                                            ],
                                            (r['rotation_next'] as num?)
                                                    ?.toInt() ??
                                                0,
                                            people,
                                          )
                                        else if (r['assignee_id'] != null)
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
                                label: PlanPriority.parse(
                                  r['priority'] as String,
                                ).label,
                                color: PlanPriority.parse(
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
  late PlanPriority _priority = PlanPriority.parse(
    (widget.existing?['priority'] as String?) ?? 'normal',
  );
  late String _every = (widget.existing?['every'] as String?) ?? 'weekly';
  late String? _areaId = widget.existing?['area_id'] as String?;
  late String? _siteId =
      widget.existing?['site_id'] as String? ??
      ref.read(currentSiteProvider)?.id;
  late String? _assigneeId = widget.existing?['assignee_id'] as String?;

  /// People taking turns, in order.
  late final List<String> _turns = [
    for (final u in (widget.existing?['rotation'] as List?) ?? const []) '$u',
  ];
  late _Who _who = _turns.isNotEmpty
      ? _Who.turns
      : _assigneeId != null
      ? _Who.one
      : _Who.anyone;
  late int _dueDays = (widget.existing?['due_days'] as num?)?.toInt() ?? 1;
  late String? _assetId = widget.existing?['asset_id'] as String?;
  late bool _isolation =
      (widget.existing?['isolation_required'] as bool?) ?? false;
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
    if (!archive && _who == _Who.one && _assigneeId == null) {
      setState(() => _error = 'Pick who does it');
      return;
    }
    if (!archive && _who == _Who.turns && _turns.length < 2) {
      setState(() => _error = 'Pick at least two people to take turns');
      return;
    }
    final site = _siteId;
    if (site == null) return;
    HapticFeedback.mediumImpact();
    await ref
        .read(siteActionsProvider)
        .saveRecurrence(
          id: widget.existing?['id'] as String?,
          siteId: site,
          areaId: _areaId,
          title: _title.text,
          description: _description.text,
          priority: _priority.name,
          every: _every,
          nextRun: _nextRun,
          dueDays: _dueDays,
          assigneeId: _who == _Who.one ? _assigneeId : null,
          archived: archive,
          assetId: _assetId,
          isolationRequired: _isolation,
          rotation: _who == _Who.turns ? _turns : const [],
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
    final site = _siteId;
    final areas = site == null ? <LocalArea>[] : session.areasAt(site);
    final people = site == null
        ? const AsyncValue<List<Assignee>>.data([])
        : ref.watch(assigneesProvider(site));
    final assets = ref.watch(assetsAtProvider(site)).value ?? const [];
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
            widget.existing == null ? 'New planned job' : 'Edit planned job',
            style: theme.textTheme.headlineSmall,
          ),
          if (widget.existing == null) ...[
            const SizedBox(height: Space.md),
            SiteField(
              value: _siteId,
              onChanged: (v) => setState(() {
                _siteId = v;
                _areaId = null;
                _assigneeId = null;
                _turns.clear();
                _assetId = null;
              }),
            ),
          ],
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
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final e in everyLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _every == e.key,
                  onSelected: (_) => setState(() => _every = e.key),
                ),
            ],
          ),
          if (_every == 'daily' || _every == 'weekdays')
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Skipped on shutdowns and holidays'
                '${_every == 'weekdays' ? ' and at weekends' : ''}.',
                style: theme.textTheme.labelSmall,
              ),
            ),
          label('Priority'),
          Center(
            child: GlassSegmented<PlanPriority>(
              value: _priority,
              segments: {for (final p in PlanPriority.values) p: p.label},
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
          if (assets.isNotEmpty) ...[
            label('Asset (makes it planned maintenance)'),
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
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Isolation (lock-out) required'),
            value: _isolation,
            onChanged: (v) => setState(() => _isolation = v),
          ),
          label('Who does it'),
          Center(
            child: GlassSegmented<_Who>(
              value: _who,
              segments: const {
                _Who.anyone: 'By hand',
                _Who.one: 'One person',
                _Who.turns: 'Take turns',
              },
              onChanged: (w) => setState(() => _who = w),
            ),
          ),
          const SizedBox(height: Space.sm),
          if (_who == _Who.anyone)
            Text(
              'Each job waits on the board for a supervisor to assign.',
              style: theme.textTheme.labelSmall,
            )
          else
            people.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Connect to pick people.'),
              data: (list) => _who == _Who.one
                  ? DropdownButtonFormField<String?>(
                      initialValue: list.any((p) => p.id == _assigneeId)
                          ? _assigneeId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Assigned to',
                      ),
                      items: [
                        for (final p in list)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name.isEmpty ? 'Unnamed' : p.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _assigneeId = v),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Tap people in the order they take turns. Each job '
                          'goes to the next one; anyone off or on leave in '
                          'the roster that day is skipped.',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: Space.xs),
                        Wrap(
                          spacing: Space.xs,
                          runSpacing: Space.xs,
                          children: [
                            for (final p in list)
                              FilterChip(
                                avatar: _turns.contains(p.id)
                                    ? CircleAvatar(
                                        child: Text(
                                          '${_turns.indexOf(p.id) + 1}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      )
                                    : null,
                                showCheckmark: false,
                                label: Text(
                                  p.name.isEmpty ? 'Unnamed' : p.name,
                                ),
                                selected: _turns.contains(p.id),
                                onSelected: (on) => setState(() {
                                  on ? _turns.add(p.id) : _turns.remove(p.id);
                                }),
                              ),
                          ],
                        ),
                      ],
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

/// A plan's priority; job cards it raises get P2 (urgent), P3 or P4 (low).
enum PlanPriority {
  low('Low', Color(0xFF8C8FA3)),
  normal('Normal', BrandColors.info),
  urgent('Urgent', Color(0xFFE5484D));

  const PlanPriority(this.label, this.color);

  final String label;
  final Color color;

  static PlanPriority parse(String s) =>
      PlanPriority.values.firstWhere((v) => v.name == s, orElse: () => normal);
}
