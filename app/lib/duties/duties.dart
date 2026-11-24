import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart';
import '../ui/form_sheet.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import '../widgets/site_picker.dart';

/// Daily duties (migration 0059): everyday operations shared by a team
/// without job cards. Each day every duty goes to someone (a fixed person,
/// or the team in turn, so if Geri reads the meters today Nyasha checks the
/// generator, and tomorrow they swap). People tick their duties done.
/// There are no notifications: your duties show on Home.

/// One duty on one day.
class Duty {
  Duty.fromJson(Map<String, dynamic> j)
    : rotaId = j['rota_id'] as String,
      rotaName = j['rota_name'] as String,
      siteId = j['site_id'] as String,
      taskId = j['task_id'] as String,
      title = j['title'] as String,
      personId = j['person_id'] as String?,
      doneBy = j['done_by'] as String?,
      doneAt = j['done_at'] == null
          ? null
          : DateTime.parse(j['done_at'] as String).toLocal(),
      note = j['note'] as String?;

  final String rotaId;
  final String rotaName;
  final String siteId;
  final String taskId;
  final String title;
  final String? personId;
  final String? doneBy;
  final DateTime? doneAt;
  final String? note;

  bool get done => doneBy != null;
}

String dutyDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

typedef DutyQuery = ({String? site, String day});

/// The duties on a day (site null: every site). The last list for the day
/// is kept on the phone for when there is no signal.
final dutiesProvider = FutureProvider.autoDispose.family<List<Duty>, DutyQuery>(
  (ref, q) async {
    final prefs = ref.watch(sharedPrefsProvider);
    final key = 'duties:${q.site ?? 'all'}:${q.day}';
    List rows;
    try {
      rows =
          await ref
                  .watch(supabaseProvider)
                  .rpc('fn_duties', params: {'p_site': q.site, 'p_day': q.day})
                  .timeout(const Duration(seconds: 15))
              as List;
      unawaited(
        prefs.setString(key, jsonEncode(rows)).catchError((_) => false),
      );
    } catch (_) {
      final kept = prefs.getString(key);
      if (kept == null) rethrow;
      rows = jsonDecode(kept) as List;
    }
    return [for (final r in rows) Duty.fromJson(Map<String, dynamic>.from(r))];
  },
);

/// Ticks made on this phone that the server may not have yet, by
/// "task|day": shown straight away, even without signal.
final localTicksProvider = NotifierProvider<LocalTicks, Map<String, bool>>(
  LocalTicks.new,
);

class LocalTicks extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String task, String day, bool done) =>
      state = {...state, '$task|$day': done};
}

/// Whether the duty is done, counting ticks not yet sent.
bool dutyDone(Duty d, String day, Map<String, bool> local) =>
    local['${d.taskId}|$day'] ?? d.done;

/// Ticks a duty done (or not). Queued, so it works without signal.
Future<void> markDuty(WidgetRef ref, Duty d, String day, bool done) async {
  HapticFeedback.selectionClick();
  ref.read(localTicksProvider.notifier).set(d.taskId, day, done);
  final outbox = ref.read(outboxProvider);
  await outbox.enqueue('fn_mark_duty', {
    'p_task': d.taskId,
    'p_day': day,
    'p_done': done,
  }, flushNow: false);
  await outbox.flush();
}

/// A duty list as saved, for editing.
class DutyRota {
  DutyRota.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      name = j['name'] as String,
      every = j['every'] as String,
      people = [for (final p in (j['people'] as List? ?? const [])) '$p'],
      tasks = [
        for (final t in (j['duty_tasks'] as List? ?? const []))
          if (t['is_archived'] != true)
            (
              title: t['title'] as String,
              personId: t['person_id'] as String?,
              position: (t['position'] as num?)?.toInt() ?? 0,
            ),
      ]..sort((a, b) => a.position.compareTo(b.position));

  final String id;
  final String siteId;
  final String name;
  final String every;
  final List<String> people;
  final List<({String title, String? personId, int position})> tasks;
}

final dutyRotaProvider = FutureProvider.autoDispose.family<DutyRota?, String>((
  ref,
  id,
) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('duty_rotas')
      .select('*, duty_tasks(title, person_id, position, is_archived)')
      .eq('id', id)
      .maybeSingle();
  return row == null ? null : DutyRota.fromJson(row);
});

/// My duties today that are not ticked yet (Home's "Needs you").
final myDutiesTodayProvider = Provider.autoDispose<List<Duty>>((ref) {
  final me = ref.watch(authUserIdProvider);
  final day = dutyDay(_today());
  final list =
      ref.watch(dutiesProvider((site: null, day: day))).value ?? const [];
  final local = ref.watch(localTicksProvider);
  return [
    for (final d in list)
      if (d.personId == me && !dutyDone(d, day, local)) d,
  ];
});

/// Today's duties (or another day's), list by list, with ticks.
class DutiesScreen extends ConsumerStatefulWidget {
  const DutiesScreen({super.key});

  @override
  ConsumerState<DutiesScreen> createState() => _DutiesScreenState();
}

class _DutiesScreenState extends ConsumerState<DutiesScreen> {
  DateTime _day = _today();
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(siteFilterProvider);
    final day = dutyDay(_day);
    final duties = ref.watch(dutiesProvider((site: site, day: day)));
    final local = ref.watch(localTicksProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final canManage = session.canAnywhere('jobs.assign');
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final today = _today();
    final tickable =
        !_day.isAfter(today) &&
        today.difference(_day) <= const Duration(days: 7);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Daily duties'),
        actions: const [
          SiteFilterChip(),
          SizedBox(width: Space.sm),
        ],
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showFormSheet<void>(context, const DutyRotaForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New duty list'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () =>
              ref.refresh(dutiesProvider((site: site, day: day)).future),
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
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Day before',
                            icon: const Icon(CupertinoIcons.chevron_left),
                            onPressed: () => setState(
                              () =>
                                  _day = _day.subtract(const Duration(days: 1)),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _day == today
                                  ? 'Today · ${dates.formatShortMonthDay(_day)}'
                                  : dates.formatFullDate(_day),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next day',
                            icon: const Icon(CupertinoIcons.chevron_right),
                            onPressed: () => setState(
                              () => _day = _day.add(const Duration(days: 1)),
                            ),
                          ),
                        ],
                      ),
                      Center(
                        child: GlassSegmented<bool>(
                          value: _mineOnly,
                          segments: const {false: 'Everyone', true: 'Mine'},
                          onChanged: (v) => setState(() => _mineOnly = v),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      ...duties.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load the duties',
                            message: AppError.from(e).message,
                          ),
                        ],
                        data: (all) {
                          final list = [
                            for (final d in all)
                              if (!_mineOnly || d.personId == me) d,
                          ];
                          if (list.isEmpty) {
                            return [
                              EmptyState(
                                icon: CupertinoIcons.check_mark_circled,
                                title: all.isEmpty
                                    ? 'No duties this day'
                                    : 'Nothing for you this day',
                                message: all.isEmpty
                                    ? (canManage
                                          ? 'Make a list of everyday duties '
                                                'and who shares them.'
                                          : 'Weekends, shutdowns and '
                                                'holidays have none.')
                                    : 'The others are on today.',
                              ),
                            ];
                          }
                          final byRota = <String, List<Duty>>{};
                          for (final d in list) {
                            (byRota[d.rotaId] ??= []).add(d);
                          }
                          return [
                            for (final group in byRota.values)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.md,
                                ),
                                child: Panel(
                                  title: group.first.rotaName,
                                  subtitle: [
                                    if (site == null)
                                      session
                                              .siteById(group.first.siteId)
                                              ?.code ??
                                          '',
                                    '${group.where((d) => dutyDone(d, day, local)).length}'
                                        ' of ${group.length} done',
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  actions: [
                                    if (session.can(
                                      'jobs.assign',
                                      siteId: group.first.siteId,
                                    ))
                                      IconButton(
                                        tooltip: 'Change the list',
                                        icon: const Icon(CupertinoIcons.pencil),
                                        onPressed: () => showFormSheet<void>(
                                          context,
                                          DutyRotaForm(
                                            rotaId: group.first.rotaId,
                                          ),
                                        ),
                                      ),
                                  ],
                                  child: Column(
                                    children: [
                                      for (final d in group)
                                        _DutyRow(
                                          duty: d,
                                          done: dutyDone(d, day, local),
                                          who: d.personId == null
                                              ? 'Anyone'
                                              : d.personId == me
                                              ? 'You'
                                              : people[d.personId] ?? 'Someone',
                                          mine: d.personId == me,
                                          doneBy:
                                              d.doneBy != null &&
                                                  d.doneBy != d.personId
                                              ? people[d.doneBy]
                                              : null,
                                          onTick: tickable
                                              ? (v) => markDuty(ref, d, day, v)
                                              : null,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ];
                        },
                      ),
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

class _DutyRow extends StatelessWidget {
  const _DutyRow({
    required this.duty,
    required this.done,
    required this.who,
    required this.mine,
    required this.onTick,
    this.doneBy,
  });

  final Duty duty;
  final bool done;
  final String who;
  final bool mine;
  final String? doneBy;
  final ValueChanged<bool>? onTick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: done,
      onChanged: onTick == null ? null : (v) => onTick!(v ?? false),
      title: Text(
        duty.title,
        style: theme.textTheme.titleSmall?.copyWith(
          decoration: done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        [
          who,
          if (doneBy != null) 'done by $doneBy',
          if (duty.note != null) duty.note!,
        ].join(' · '),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: mine ? FontWeight.w700 : null,
          color: mine ? theme.colorScheme.primary : null,
        ),
      ),
    );
  }
}

/// Makes or changes a duty list: its site, name, how often, the team in
/// the order they turn, and the duties (each for the team in turn or for
/// one person).
class DutyRotaForm extends ConsumerStatefulWidget {
  const DutyRotaForm({super.key, this.rotaId});

  final String? rotaId;

  @override
  ConsumerState<DutyRotaForm> createState() => _DutyRotaFormState();
}

class _Task {
  _Task(String title, this.personId)
    : text = TextEditingController(text: title);

  final TextEditingController text;
  String? personId;
}

class _DutyRotaFormState extends ConsumerState<DutyRotaForm> {
  final _name = TextEditingController();
  late String? _siteId = ref.read(currentSiteProvider)?.id;
  String _every = 'weekdays';
  final _team = <String>[];
  final _tasks = <_Task>[_Task('', null)];
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    for (final t in _tasks) {
      t.text.dispose();
    }
    super.dispose();
  }

  void _fill(DutyRota r) {
    if (_loaded) return;
    _loaded = true;
    _name.text = r.name;
    _siteId = r.siteId;
    _every = r.every;
    _team
      ..clear()
      ..addAll(r.people);
    for (final t in _tasks) {
      t.text.dispose();
    }
    _tasks
      ..clear()
      ..addAll([for (final t in r.tasks) _Task(t.title, t.personId)]);
    if (_tasks.isEmpty) _tasks.add(_Task('', null));
  }

  Future<void> _save({bool archive = false}) async {
    final site = _siteId;
    if (site == null) return;
    final tasks = [
      for (final t in _tasks)
        if (t.text.text.trim().length >= 2) t,
    ];
    if (!archive) {
      String? fail;
      if (_name.text.trim().length < 2) {
        fail = 'Name the list, e.g. Morning duties';
      } else if (tasks.isEmpty) {
        fail = 'Add at least one duty';
      } else if (_team.isEmpty && tasks.any((t) => t.personId == null)) {
        fail = 'Pick the team, or a person for each duty';
      }
      if (fail != null) {
        setState(() => _error = fail);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'fn_save_duty_rota',
            params: {
              'p_id': widget.rotaId,
              'p_site': site,
              'p_name': _name.text.trim(),
              'p_every': _every,
              'p_people': _team,
              'p_tasks': [for (final t in tasks) t.text.text.trim()],
              'p_people_for': [for (final t in tasks) t.personId],
              'p_archived': archive,
            },
          );
      ref.invalidate(dutiesProvider);
      if (widget.rotaId != null) {
        ref.invalidate(dutyRotaProvider(widget.rotaId!));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.rotaId != null) {
      final r = ref.watch(dutyRotaProvider(widget.rotaId!));
      if (r.value case final rota?) {
        _fill(rota);
      } else if (!_loaded) {
        return const Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Center(child: CircularProgressIndicator()),
        );
      }
    }
    final site = _siteId;
    final people = site == null
        ? const AsyncValue<List<Assignee>>.data([])
        : ref.watch(assigneesProvider(site));
    final names = {
      for (final p in people.value ?? const <Assignee>[]) p.id: p.name,
    };
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.rotaId == null ? 'New duty list' : 'Change the duty list',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          if (widget.rotaId == null) ...[
            SiteField(
              value: _siteId,
              onChanged: (v) => setState(() {
                _siteId = v;
                _team.clear();
                for (final t in _tasks) {
                  t.personId = null;
                }
              }),
            ),
            const SizedBox(height: Space.sm),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Morning duties, Substation',
            ),
          ),
          label('Days'),
          Center(
            child: GlassSegmented<String>(
              value: _every,
              segments: const {'weekdays': 'Weekdays', 'daily': 'Every day'},
              onChanged: (v) => setState(() => _every = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'None on shutdowns and public holidays.',
              style: theme.textTheme.labelSmall,
            ),
          ),
          label('The team'),
          Text(
            'Tap people in order. Each day the duties move one step round '
            'the team: if Geri has the first duty today, she has the second '
            'tomorrow. Anyone off or on leave in the roster is left out.',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: Space.xs),
          people.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Connect to pick people.'),
            data: (list) => Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final p in list)
                  FilterChip(
                    avatar: _team.contains(p.id)
                        ? CircleAvatar(
                            child: Text(
                              '${_team.indexOf(p.id) + 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          )
                        : null,
                    showCheckmark: false,
                    label: Text(p.name.isEmpty ? 'Unnamed' : p.name),
                    selected: _team.contains(p.id),
                    onSelected: (on) => setState(
                      () => on ? _team.add(p.id) : _team.remove(p.id),
                    ),
                  ),
              ],
            ),
          ),
          label('Duties'),
          for (final (i, t) in _tasks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: t.text,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Duty ${i + 1}',
                        hintText: i == 0 ? 'e.g. Read the meters' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      initialValue: names.containsKey(t.personId)
                          ? t.personId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Who'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('In turn'),
                        ),
                        for (final e in names.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value.isEmpty ? 'Unnamed' : e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => t.personId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(CupertinoIcons.minus_circle),
                    onPressed: _tasks.length == 1
                        ? null
                        : () =>
                              setState(() => _tasks.removeAt(i).text.dispose()),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _tasks.add(_Task('', null))),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Add a duty'),
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
            onPressed: _busy ? null : _save,
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Save'),
          ),
          if (widget.rotaId != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Stop this list'),
            ),
          ],
        ],
      ),
    );
  }
}
