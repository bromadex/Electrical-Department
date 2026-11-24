import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'zim_holidays.dart';

/// Days the department is closed (migration 0058): a shutdown or a public
/// holiday, at every site (siteId null) or one. Planned jobs are not
/// raised on those days, and checklist alerts and the evening daily
/// reports pause while every site is closed.
class Closure {
  Closure.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String?,
      startsOn = DateTime.parse(j['starts_on'] as String),
      endsOn = DateTime.parse(j['ends_on'] as String),
      reason = j['reason'] as String,
      kind = (j['kind'] as String?) ?? 'shutdown',
      message = j['message'] as String?;

  final String id;
  final String? siteId;
  final DateTime startsOn;
  final DateTime endsOn;
  final String reason;

  /// 'shutdown' or 'holiday' (migration 0059).
  final String kind;

  /// A greeting for the team, shown on Home just before and during it.
  final String? message;

  bool get holiday => kind == 'holiday';

  /// Whether [day] (a date) falls in this closure.
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startsOn) && !d.isAfter(endsOn);
  }

  /// The day work starts again.
  DateTime get reopens => endsOn.add(const Duration(days: 1));

  /// Whether it applies to [site] (null: only closures for every site).
  bool at(String? site) => siteId == null || (site != null && siteId == site);
}

/// Closures that have not ended, soonest first (online).
final closuresProvider = FutureProvider.autoDispose<List<Closure>>((ref) async {
  final now = DateTime.now();
  final today =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final rows = await ref
      .watch(supabaseProvider)
      .from('work_closures')
      .select('id, site_id, starts_on, ends_on, reason, kind, message')
      .eq('is_archived', false)
      .gte('ends_on', today)
      .order('starts_on', ascending: true);
  return [for (final r in rows) Closure.fromJson(r)];
});

/// The closure on today or coming up, for [site] (or every site), if any:
/// what Home and Planned maintenance mention. A shutdown shows from [days]
/// days before (a month), a public holiday from a week before.
Closure? closureSoon(List<Closure> list, String? site, {int days = 31}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final c in list) {
    if (!c.at(site)) continue;
    if (c.covers(today)) return c;
    final ahead = c.holiday ? 7 : days;
    if (!c.startsOn.isAfter(today.add(Duration(days: ahead)))) return c;
  }
  return null;
}

/// Whether the greeting shows: on the day(s), and the three days before.
bool showsMessage(Closure c, DateTime now) {
  if (c.message == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  return c.covers(today) ||
      !c.startsOn.isAfter(today.add(const Duration(days: 3)));
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String closureDates(BuildContext context, Closure c) {
  final dates = MaterialLocalizations.of(context);
  return c.startsOn == c.endsOn
      ? dates.formatMediumDate(c.startsOn)
      : '${dates.formatShortMonthDay(c.startsOn)} – '
            '${dates.formatMediumDate(c.endsOn)}';
}

/// "Closed from 19 Dec: Christmas shutdown. Back on 4 Jan." with a link to
/// the list. Nothing when no closure is on or near.
class ClosureNotice extends ConsumerWidget {
  const ClosureNotice({super.key, this.site, this.planned = false});

  final String? site;

  /// On Planned maintenance: say what happens to the plans.
  final bool planned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(closuresProvider).value ?? const <Closure>[];
    final c = closureSoon(list, site);
    if (c == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final on = c.covers(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SurfaceCard(
        onTap: () => context.push('/closures'),
        child: Row(
          children: [
            Icon(
              c.holiday ? CupertinoIcons.gift : CupertinoIcons.moon_zzz,
              color: BrandColors.warning,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    on
                        ? (c.holiday ? c.reason : 'Closed: ${c.reason}')
                        : '${c.holiday ? 'Holiday' : 'Closing'} '
                              '${dates.formatMediumDate(c.startsOn)}: '
                              '${c.reason}',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (showsMessage(c, now))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        c.message!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  Text(
                    [
                      'Work starts again ${dates.formatMediumDate(c.reopens)}',
                      if (planned)
                        'no planned jobs meanwhile; weekly and monthly ones '
                            'wait for that day',
                    ].join('; '),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Shutdowns and holidays: the list, and adding or changing them for
/// people who set up planned jobs.
class ClosuresScreen extends ConsumerWidget {
  const ClosuresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(closuresProvider);
    final session = ref.watch(sessionProvider);
    final canManage = session.canAnywhere('jobs.assign');
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/jobs/recurring'),
        title: const Text('Shutdowns and holidays'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showFormSheet<void>(context, const ClosureForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Add closed days'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => ref.refresh(closuresProvider.future),
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Text(
                          'While work is closed no planned jobs are raised: '
                          'everyday ones are skipped, weekly and monthly ones '
                          'wait for the day work starts again. When every '
                          'site is closed, checklist alerts and the evening '
                          'daily reports pause too.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (canManage &&
                          session.perms.canEverywhere('jobs.assign'))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: OutlinedButton.icon(
                            icon: const Icon(CupertinoIcons.gift),
                            label: const Text('Add public holidays for a year'),
                            onPressed: () => _addHolidays(context, ref),
                          ),
                        ),
                      ...list.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load closed days',
                            message: AppError.from(e).message,
                          ),
                        ],
                        data: (rows) => rows.isEmpty
                            ? [
                                const EmptyState(
                                  icon: CupertinoIcons.sun_max,
                                  title: 'No closed days coming up',
                                  message:
                                      'Add shutdowns and public holidays so '
                                      'planned jobs pause.',
                                ),
                              ]
                            : [
                                for (final c in rows)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: Space.sm,
                                    ),
                                    child: SurfaceCard(
                                      onTap: canManage
                                          ? () => showFormSheet<void>(
                                              context,
                                              ClosureForm(closure: c),
                                            )
                                          : null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            c.holiday
                                                ? CupertinoIcons.gift
                                                : CupertinoIcons.moon_zzz,
                                            color: c.covers(DateTime.now())
                                                ? BrandColors.warning
                                                : theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: Space.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  c.reason,
                                                  style: theme
                                                      .textTheme
                                                      .titleSmall,
                                                ),
                                                Text(
                                                  [
                                                    closureDates(context, c),
                                                    c.siteId == null
                                                        ? 'every site'
                                                        : session
                                                                  .siteById(
                                                                    c.siteId,
                                                                  )
                                                                  ?.name ??
                                                              'one site',
                                                  ].join(' · '),
                                                  style: theme
                                                      .textTheme
                                                      .labelSmall,
                                                ),
                                                if (c.message != null)
                                                  Text(
                                                    '“${c.message}”',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
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

/// Adds Zimbabwe's public holidays for a year the user picks, with their
/// messages, for every site; ones already there (or inside a shutdown)
/// are left alone.
Future<void> _addHolidays(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now().year;
  final year = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Public holidays for which year?'),
      children: [
        for (final y in [now, now + 1, now + 2])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, y),
            child: Text('$y'),
          ),
      ],
    ),
  );
  if (year == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final db = ref.read(supabaseProvider);
  try {
    final rows = await db
        .from('work_closures')
        .select('starts_on, ends_on')
        .eq('is_archived', false)
        .isFilter('site_id', null)
        .lte('starts_on', '$year-12-31')
        .gte('ends_on', '$year-01-01');
    bool covered(DateTime from, DateTime to) => rows.any(
      (r) =>
          !from.isBefore(DateTime.parse(r['starts_on'] as String)) &&
          !to.isAfter(DateTime.parse(r['ends_on'] as String)),
    );
    var added = 0;
    for (final h in zimbabweHolidays(year)) {
      if (covered(h.from, h.to)) continue;
      await db.rpc(
        'fn_save_closure',
        params: {
          'p_id': null,
          'p_site': null,
          'p_starts': _iso(h.from),
          'p_ends': _iso(h.to),
          'p_reason': h.reason,
          'p_archived': false,
          'p_kind': 'holiday',
          'p_message': h.message,
        },
      );
      added++;
    }
    ref.invalidate(closuresProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? "$year's public holidays are already in."
              : 'Added $added public holidays for $year. Remove any a site '
                    'works through.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
  }
}

/// Adds or changes closed days; a closure can be removed here too.
class ClosureForm extends ConsumerStatefulWidget {
  const ClosureForm({super.key, this.closure});

  final Closure? closure;

  @override
  ConsumerState<ClosureForm> createState() => _ClosureFormState();
}

class _ClosureFormState extends ConsumerState<ClosureForm> {
  late final _reason = TextEditingController(text: widget.closure?.reason);
  late final _message = TextEditingController(text: widget.closure?.message);
  late bool _holiday = widget.closure?.holiday ?? false;
  late DateTime _from = widget.closure?.startsOn ?? _today();
  late DateTime _to = widget.closure?.endsOn ?? _today();

  /// Null: every site.
  late String? _site = widget.closure?.siteId;
  bool _busy = false;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (!remove && _reason.text.trim().length < 2) {
      setState(() => _error = 'Say why, e.g. Christmas shutdown');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'fn_save_closure',
            params: {
              'p_id': widget.closure?.id,
              'p_site': _site,
              'p_starts': _iso(_from),
              'p_ends': _iso(_to),
              'p_reason': remove ? widget.closure!.reason : _reason.text.trim(),
              'p_archived': remove,
              'p_kind': _holiday ? 'holiday' : 'shutdown',
              // Empty clears it.
              'p_message': _message.text.trim(),
            },
          );
      ref.invalidate(closuresProvider);
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

  Future<void> _pick({required bool from}) async {
    final first = DateTime.now().subtract(const Duration(days: 30));
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d;
        if (_from.isAfter(d)) _from = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final dates = MaterialLocalizations.of(context);
    final canAll = session.perms.canEverywhere('jobs.assign');
    final sites = [
      for (final s in session.mySites)
        if (session.can('jobs.assign', siteId: s.id)) s,
    ];
    if (!canAll && _site == null && sites.isNotEmpty) _site = sites.first.id;
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
            widget.closure == null ? 'Add closed days' : 'Closed days',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Shutdown')),
                ButtonSegment(value: true, label: Text('Public holiday')),
              ],
              selected: {_holiday},
              onSelectionChanged: (v) => setState(() => _holiday = v.first),
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Why',
              hintText: 'e.g. Christmas shutdown, Heroes Day',
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: Text('From ${dates.formatShortMonthDay(_from)}'),
                  onPressed: () => _pick(from: true),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.calendar),
                  label: Text('To ${dates.formatShortMonthDay(_to)}'),
                  onPressed: () => _pick(from: false),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Both days are closed; work starts again '
              '${dates.formatMediumDate(_to.add(const Duration(days: 1)))}.',
              style: theme.textTheme.labelSmall,
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 5,
            maxLength: 400,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message for the team (optional)',
              hintText: 'Shown on Home on the day and the three days before',
            ),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<String?>(
            initialValue: _site,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Where',
              prefixIcon: Icon(Icons.place_rounded),
            ),
            items: [
              if (canAll)
                const DropdownMenuItem(value: null, child: Text('Every site')),
              for (final s in sites)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _site = v),
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
          if (widget.closure != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : () => _save(remove: true),
              icon: const Icon(CupertinoIcons.trash),
              label: const Text('Remove'),
            ),
          ],
        ],
      ),
    );
  }
}
