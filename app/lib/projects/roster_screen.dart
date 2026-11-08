import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'projects_repository.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekday(DateTime d) => _days[d.weekday - 1];

/// The next shift in the cycle a supervisor taps through: empty → day →
/// night → off → leave → empty.
String? nextShift(String? s) => switch (s) {
  null => 'day',
  'day' => 'night',
  'night' => 'off',
  'off' => 'leave',
  _ => null,
};

Color shiftColor(String? s) => switch (s) {
  'day' => BrandColors.info,
  'night' => const Color(0xFF5B4B8A),
  'off' => Colors.grey,
  'leave' => BrandColors.success,
  _ => Colors.transparent,
};

/// The weekly roster: my shifts on top; supervisors tap a cell to cycle
/// day, night, off and leave, long-press for standby, then save or publish.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key, this.day});

  /// A day in the week to open (from a notification).
  final DateTime? day;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  late DateTime _monday = mondayOf(widget.day ?? DateTime.now());

  /// Changes not saved yet: user → day → (shift, standby); shift null clears.
  final _edits = <String, Map<DateTime, ({String? shift, bool standby})>>{};
  bool _busy = false;

  ({String? shift, bool standby}) _cell(
    Map<(String, DateTime), RosterEntry> saved,
    String user,
    DateTime day,
  ) {
    final e = _edits[user]?[day];
    if (e != null) return e;
    final s = saved[(user, day)];
    return (shift: s?.shift, standby: s?.standby ?? false);
  }

  void _set(String user, DateTime day, ({String? shift, bool standby}) v) =>
      setState(() => (_edits[user] ??= {})[day] = v);

  Future<void> _save(String siteId, {required bool publish}) async {
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(projectActionsProvider).setRoster(siteId, _monday, [
        for (final u in _edits.entries)
          for (final d in u.value.entries)
            {
              'user_id': u.key,
              'day': isoDay(d.key),
              'shift': d.value.shift,
              'standby': d.value.standby,
            },
      ], publish: publish);
      if (!mounted) return;
      setState(() {
        _edits.clear();
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish ? 'Roster published; everyone on it is told' : 'Saved',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUserIdProvider);
    final canEdit = ref
        .watch(sessionProvider)
        .can('projects.manage', siteId: site?.id);
    final people = ref.watch(peopleProvider).value ?? const {};
    final week = site == null
        ? null
        : ref.watch(rosterWeekProvider((site: site.id, monday: _monday)));
    final saved = {
      for (final e in week?.value?.entries ?? const <RosterEntry>[])
        (e.userId, e.day): e,
    };
    final days = [for (var i = 0; i < 7; i++) _monday.add(Duration(days: i))];
    final dates = MaterialLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // Supervisors see everyone; others see who is on the roster.
    final rosterIds = {for (final e in saved.values) e.userId, ..._edits.keys};
    final names =
        [
          for (final p in people.entries)
            if (p.value.isNotEmpty && (canEdit || rosterIds.contains(p.key))) p,
        ]..sort((a, b) {
          if (a.key == me) return -1;
          if (b.key == me) return 1;
          return a.value.compareTo(b.value);
        });
    final mine = [
      for (final d in days)
        if (_cell(saved, me ?? '', d).shift != null)
          (day: d, cell: _cell(saved, me ?? '', d)),
    ];
    final published = week?.value?.publishedAt;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Roster · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      // The glass background runs under the button bar.
      extendBody: true,
      bottomNavigationBar: canEdit && site != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy || _edits.isEmpty
                            ? null
                            : () => _save(site.id, publish: false),
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _save(site.id, publish: true),
                        icon: const Icon(CupertinoIcons.paperplane, size: 18),
                        label: Text(
                          published == null ? 'Publish' : 'Publish again',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(Space.md, top + Space.md, Space.md, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous week',
                          icon: const Icon(CupertinoIcons.chevron_left),
                          onPressed: _edits.isNotEmpty
                              ? null
                              : () => setState(
                                  () => _monday = _monday.subtract(
                                    const Duration(days: 7),
                                  ),
                                ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Week of ${dates.formatShortMonthDay(_monday)}',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                published == null
                                    ? 'Not published'
                                    : 'Published ${dates.formatShortMonthDay(published)}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next week',
                          icon: const Icon(CupertinoIcons.chevron_right),
                          onPressed: _edits.isNotEmpty
                              ? null
                              : () => setState(
                                  () => _monday = _monday.add(
                                    const Duration(days: 7),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    Panel(
                      icon: CupertinoIcons.person,
                      title: 'My shifts',
                      child: mine.isEmpty
                          ? Text(
                              'You are not on this week\'s roster.',
                              style: theme.textTheme.labelMedium,
                            )
                          : Wrap(
                              spacing: Space.sm,
                              runSpacing: Space.sm,
                              children: [
                                for (final m in mine)
                                  Chip(
                                    avatar: m.cell.standby
                                        ? const Icon(
                                            CupertinoIcons.phone_fill,
                                            size: 16,
                                            color: Colors.red,
                                          )
                                        : null,
                                    label: Text(
                                      '${_weekday(m.day)} '
                                      '${m.day.day}: ${shifts[m.cell.shift]}'
                                      '${m.cell.standby ? ', standby' : ''}',
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: Space.md),
                    if (week?.isLoading ?? false)
                      const LinearProgressIndicator(),
                    if (week?.hasError ?? false)
                      EmptyState(
                        icon: CupertinoIcons.wifi_slash,
                        title: 'Could not load the roster',
                        message: AppError.from(week!.error!).message,
                      ),
                    if (canEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(
                          'Tap a day to cycle day, night, off and leave; '
                          'press and hold for standby.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    SurfaceCard(
                      padding: const EdgeInsets.all(Space.sm),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 130),
                                for (final d in days)
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      '${_weekday(d)}\n${d.day}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ),
                              ],
                            ),
                            for (final p in names)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      p.key == me ? '${p.value} (me)' : p.value,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ),
                                  for (final d in days)
                                    _ShiftCell(
                                      cell: _cell(saved, p.key, d),
                                      changed: _edits[p.key]?[d] != null,
                                      onTap: canEdit
                                          ? () {
                                              final c = _cell(saved, p.key, d);
                                              final s = nextShift(c.shift);
                                              _set(p.key, d, (
                                                shift: s,
                                                standby:
                                                    c.standby &&
                                                    (s == 'day' ||
                                                        s == 'night'),
                                              ));
                                            }
                                          : null,
                                      onLongPress: canEdit
                                          ? () {
                                              final c = _cell(saved, p.key, d);
                                              if (c.shift == null ||
                                                  c.shift == 'off' ||
                                                  c.shift == 'leave') {
                                                return;
                                              }
                                              HapticFeedback.selectionClick();
                                              _set(p.key, d, (
                                                shift: c.shift,
                                                standby: !c.standby,
                                              ));
                                            }
                                          : null,
                                    ),
                                ],
                              ),
                            if (names.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(Space.md),
                                child: Text(
                                  'Nobody is on this week\'s roster yet.',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.xs,
                      children: [
                        for (final s in shifts.entries)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: shiftColor(s.key),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(s.value, style: theme.textTheme.labelSmall),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.phone_fill,
                              size: 12,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text('Standby', style: theme.textTheme.labelSmall),
                          ],
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
    );
  }
}

class _ShiftCell extends StatelessWidget {
  const _ShiftCell({
    required this.cell,
    required this.changed,
    this.onTap,
    this.onLongPress,
  });

  final ({String? shift, bool standby}) cell;
  final bool changed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = shiftColor(cell.shift);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 60,
        height: 40,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cell.shift == null
              ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
              : color.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: changed
                ? theme.colorScheme.primary
                : cell.shift == null
                ? Colors.transparent
                : color,
            width: changed ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              cell.shift == null ? '' : shifts[cell.shift]!,
              style: theme.textTheme.labelSmall,
            ),
            if (cell.standby) ...[
              const SizedBox(width: 2),
              const Icon(
                CupertinoIcons.phone_fill,
                size: 11,
                color: Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
