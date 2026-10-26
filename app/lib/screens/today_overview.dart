import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../checklists/checklists_repository.dart';
import '../data/local_db.dart';
import '../documents/documents_repository.dart';
import '../jobs/job_rules.dart';
import '../jobs/jobs_repository.dart';
import '../requests/requests_screen.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../tools/tools_repository.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _closed(LocalJob j) => j.status == 'done' || j.status == 'cancelled';

/// What needs someone now, as tappable chips: urgent jobs nobody holds,
/// overdue jobs, rounds due today, tools overdue or due calibration, SOPs to
/// sign. Hidden when everything is in order.
class NeedsAttention extends ConsumerWidget {
  const NeedsAttention({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final status = ref.watch(checklistStatusProvider).value ?? const {};
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final toSign = ref.watch(toSignCountProvider);
    final requests = ref.watch(newRequestCountProvider);
    final now = DateTime.now();

    final open = jobs.where((j) => !_closed(j));
    final urgentFree = open
        .where((j) => j.priority == 'urgent' && j.assigneeId == null)
        .length;
    final overdue = open.where(isOverdue).length;
    final roundsDue = status.values
        .where((s) => !s.done && _sameDay(s.dueBy, now))
        .length;
    final toolsLate = tools.where(toolOverdue).length;
    final calibrate = tools.where(calibrationDue).length;

    final items = [
      if (requests > 0)
        (
          CupertinoIcons.tray_arrow_down_fill,
          requests == 1
              ? '1 request to decide'
              : '$requests requests to decide',
          BrandColors.info,
          '/requests',
        ),
      if (urgentFree > 0)
        (
          CupertinoIcons.exclamationmark_octagon_fill,
          urgentFree == 1
              ? '1 urgent job unassigned'
              : '$urgentFree urgent jobs unassigned',
          Colors.red,
          '/jobs',
        ),
      if (overdue > 0)
        (
          CupertinoIcons.alarm_fill,
          overdue == 1 ? '1 job overdue' : '$overdue jobs overdue',
          Colors.red,
          '/jobs',
        ),
      if (roundsDue > 0)
        (
          CupertinoIcons.checkmark_rectangle,
          roundsDue == 1 ? '1 round due today' : '$roundsDue rounds due today',
          Colors.orange,
          '/checklists',
        ),
      if (toolsLate > 0)
        (
          CupertinoIcons.wrench_fill,
          toolsLate == 1 ? '1 tool overdue' : '$toolsLate tools overdue',
          Colors.orange,
          '/tools',
        ),
      if (calibrate > 0)
        (
          CupertinoIcons.gauge,
          calibrate == 1 ? '1 calibration due' : '$calibrate calibrations due',
          BrandColors.info,
          '/tools',
        ),
      if (toSign > 0)
        (
          CupertinoIcons.signature,
          toSign == 1 ? '1 SOP to sign' : '$toSign SOPs to sign',
          BrandColors.info,
          '/documents',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.md,
          Space.sm,
        ),
        child: Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.bell_circle_fill,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Space.xs),
                  Text('Needs attention', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            for (final (icon, label, color, route) in items)
              ActionChip(
                avatar: Icon(icon, size: 16, color: color),
                label: Text(label),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                backgroundColor: color.withValues(alpha: 0.10),
                side: BorderSide(color: color.withValues(alpha: 0.35)),
                onPressed: () => context.push(route),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ten numbers a supervisor wants at a glance, each opening its list.
class TodayKpis extends ConsumerWidget {
  const TodayKpis({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(siteJobsProvider).value ?? const <LocalJob>[];
    final status = ref.watch(checklistStatusProvider).value ?? const {};
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    final toSign = ref.watch(toSignCountProvider);
    final me = ref.watch(authUserIdProvider);
    final now = DateTime.now();

    final open = jobs.where((j) => !_closed(j)).toList();
    final roundsToday = status.values.where((s) => _sameDay(s.dueBy, now));
    final kpis = [
      (
        CupertinoIcons.tray_full,
        'Open jobs',
        '${open.length}',
        BrandColors.maroon,
        '/jobs',
      ),
      (
        CupertinoIcons.exclamationmark_circle,
        'Urgent',
        '${open.where((j) => j.priority == 'urgent').length}',
        Colors.red,
        '/jobs',
      ),
      (
        CupertinoIcons.alarm,
        'Overdue',
        '${open.where(isOverdue).length}',
        Colors.red,
        '/jobs',
      ),
      (
        CupertinoIcons.person_crop_circle_badge_xmark,
        'Unassigned',
        '${open.where((j) => j.assigneeId == null).length}',
        Colors.orange,
        '/jobs',
      ),
      (
        CupertinoIcons.person_crop_circle_badge_checkmark,
        'My jobs',
        '${open.where((j) => j.assigneeId == me).length}',
        BrandColors.info,
        '/jobs',
      ),
      (
        CupertinoIcons.checkmark_seal,
        'Done today',
        '${jobs.where((j) => j.status == 'done' && j.closedAt != null && _sameDay(j.closedAt!, now)).length}',
        BrandColors.success,
        '/jobs',
      ),
      (
        CupertinoIcons.checkmark_rectangle,
        'Rounds today',
        '${roundsToday.where((s) => s.done).length}/${roundsToday.length}',
        BrandColors.success,
        '/checklists',
      ),
      (
        CupertinoIcons.wrench,
        'Tools out',
        '${tools.where((t) => t.holderId != null).length}',
        BrandColors.coral,
        '/tools',
      ),
      (
        CupertinoIcons.gauge,
        'Calibration due',
        '${tools.where(calibrationDue).length}',
        Colors.orange,
        '/tools',
      ),
      (
        CupertinoIcons.signature,
        'SOPs to sign',
        '$toSign',
        BrandColors.info,
        '/documents',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 980 ? 5 : (c.maxWidth >= 560 ? 3 : 2);
        const gap = Space.sm;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, (icon, label, value, color, route)) in kpis.indexed)
              SizedBox(
                width: w,
                child: _Kpi(
                  icon: icon,
                  label: label,
                  value: value,
                  color: color,
                  onTap: () => context.push(route),
                ).entrance(context, index: i.clamp(0, 8)),
              ),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      radius: Radii.lg + 2,
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.sm,
        Space.sm,
        Space.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(height: 1.1),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
