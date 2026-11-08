import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/push_service.dart' show notificationPath;
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'projects_repository.dart';

/// How each kind of calendar entry looks.
({IconData icon, Color color, String label}) calendarLook(String kind) =>
    switch (kind) {
      'job' => (
        icon: CupertinoIcons.doc_text,
        color: BrandColors.coral,
        label: 'Job card due',
      ),
      'meeting' => (
        icon: CupertinoIcons.person_3,
        color: BrandColors.info,
        label: 'Meeting',
      ),
      'tool_return' => (
        icon: CupertinoIcons.arrow_uturn_left,
        color: Colors.orange,
        label: 'Tool back',
      ),
      'calibration' => (
        icon: CupertinoIcons.gauge,
        color: Colors.orange,
        label: 'Calibration',
      ),
      'planned' => (
        icon: CupertinoIcons.arrow_2_circlepath,
        color: BrandColors.success,
        label: 'Planned maintenance',
      ),
      'project' => (
        icon: CupertinoIcons.flag,
        color: BrandColors.blush,
        label: 'Project due',
      ),
      'standby' => (
        icon: CupertinoIcons.phone,
        color: Colors.red,
        label: 'My standby',
      ),
      'shift' => (
        icon: CupertinoIcons.time,
        color: BrandColors.info,
        label: 'My shift',
      ),
      _ => (
        icon: CupertinoIcons.alarm,
        color: BrandColors.blush,
        label: 'Reminder',
      ),
    };

/// One calendar for the site: job cards due, meetings, tool returns,
/// calibration, planned maintenance, project dates, my shifts and
/// reminders. A month grid with dots, and the chosen day's list.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    // The grid runs Monday to Sunday, whole weeks.
    final first = mondayOf(_month);
    final lastOfMonth = DateTime(_month.year, _month.month + 1, 0);
    final last = mondayOf(lastOfMonth).add(const Duration(days: 6));
    final events = site == null
        ? const AsyncValue<List<CalendarEvent>>.data([])
        : ref.watch(calendarProvider((site: site.id, from: first, to: last)));
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final e in events.value ?? const <CalendarEvent>[]) {
      (byDay[e.day] ??= []).add(e);
    }
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final dayEvents = byDay[_day] ?? const <CalendarEvent>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Calendar · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _day = todayDay;
              _month = DateTime(today.year, today.month);
            }),
            child: const Text('Today'),
          ),
        ],
      ),
      body: MeshBackground(
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceCard(
                      padding: const EdgeInsets.all(Space.sm),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous month',
                                icon: const Icon(CupertinoIcons.chevron_left),
                                onPressed: () => _shift(-1),
                              ),
                              Expanded(
                                child: Text(
                                  dates.formatMonthYear(_month),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next month',
                                icon: const Icon(CupertinoIcons.chevron_right),
                                onPressed: () => _shift(1),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              for (final d in const [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ])
                                Expanded(
                                  child: Text(
                                    d,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: Space.xs),
                          for (
                            var w = first;
                            !w.isAfter(last);
                            w = w.add(const Duration(days: 7))
                          )
                            Row(
                              children: [
                                for (var i = 0; i < 7; i++)
                                  Expanded(
                                    child: _DayCell(
                                      day: w.add(Duration(days: i)),
                                      inMonth:
                                          w.add(Duration(days: i)).month ==
                                          _month.month,
                                      selected:
                                          w.add(Duration(days: i)) == _day,
                                      today:
                                          w.add(Duration(days: i)) == todayDay,
                                      events:
                                          byDay[w.add(Duration(days: i))] ??
                                          const [],
                                      onTap: () => setState(
                                        () => _day = w.add(Duration(days: i)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          if (events.isLoading)
                            const LinearProgressIndicator(minHeight: 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      dates.formatFullDate(_day),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.sm),
                    if (events.hasError)
                      EmptyState(
                        icon: CupertinoIcons.wifi_slash,
                        title: 'Could not load the calendar',
                        message: AppError.from(events.error!).message,
                      )
                    else if (dayEvents.isEmpty)
                      Text(
                        'Nothing on this day.',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    for (final e in dayEvents)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: _EventTile(event: e),
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

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<CalendarEvent> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kinds = {for (final e in events) e.kind}.take(4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.22) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: today ? Border.all(color: scheme.primary) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: inMonth
                    ? null
                    : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: today ? FontWeight.w800 : null,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final k in kinds)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: calendarLook(k).color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = calendarLook(event.kind);
    final path = notificationPath(event.link);
    return SurfaceCard(
      onTap: path == null ? null : () => context.push(path),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Icon(look.icon, color: look.color, size: 22),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: theme.textTheme.titleSmall),
                Text(
                  [
                    look.label,
                    if (event.at != null)
                      TimeOfDay.fromDateTime(event.at!).format(context),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (path != null) const Icon(CupertinoIcons.chevron_right, size: 16),
        ],
      ),
    );
  }
}
