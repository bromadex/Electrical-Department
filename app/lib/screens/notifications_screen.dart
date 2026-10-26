import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/notifications_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/page.dart';

/// Where a notification's link (`jobcard:<id>`, `request:<id>`) opens, or
/// null when it points at nothing that still exists (e.g. the retired jobs
/// board).
String? notificationPath(String? link) {
  if (link == null) return null;
  final i = link.indexOf(':');
  if (i < 0) return null;
  final id = link.substring(i + 1);
  return switch (link.substring(0, i)) {
    'jobcard' => '/job-cards/$id',
    'request' => '/requests/$id',
    _ => null,
  };
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static String _group(DateTime at) {
    final now = SiteTime.now();
    final local = SiteTime.local(at);
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(local.year, local.month, local.day)).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    final groups = <String, List<AppNotification>>{};
    for (final n in state.items) {
      groups.putIfAbsent(_group(n.createdAt), () => []).add(n);
    }

    return AppPage(
      title: 'Notifications',
      subtitle: state.unread == 0 ? 'Nothing unread' : '${state.unread} unread',
      maxWidth: 820,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: notifier.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (state.unread > 0)
          OutlinedButton.icon(
            onPressed: () => notifier.markRead(),
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('Mark all read'),
          ),
      ],
      child: state.items.isEmpty
          ? Card(
              child: EmptyState(
                icon: state.error == null
                    ? Icons.notifications_none_rounded
                    : Icons.cloud_off_rounded,
                title: state.error == null
                    ? 'All caught up'
                    : 'You are offline',
                message: state.error?.message ?? 'Assignments, critical faults, reviews and requests will appear here.',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final MapEntry(key: label, value: list)
                    in groups.entries) ...[
                  SectionHeader(label),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, n) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _NotificationTile(
                            key: ValueKey(n.id),
                            notification: n,
                            onTap: () {
                              if (!n.isRead) notifier.markRead([n.id]);
                              final path = notificationPath(n.link);
                              if (path != null) context.go(path);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  static const _style = {
    'registered': (Icons.fiber_new_outlined, AppColors.info),
    'request': (Icons.inbox_outlined, AppColors.info),
    'assigned': (Icons.assignment_ind_outlined, AppColors.info),
    'reassigned': (Icons.swap_horiz_rounded, AppColors.info),
    'critical': (Icons.report_rounded, AppColors.critical),
    'escalation': (Icons.campaign_rounded, AppColors.critical),
    'overdue': (Icons.alarm_rounded, AppColors.critical),
    'on_hold': (Icons.pause_circle_outline_rounded, AppColors.warning),
    'review': (Icons.fact_check_outlined, AppColors.review),
    'returned': (Icons.undo_rounded, AppColors.warning),
    'closed': (Icons.check_circle_outline_rounded, AppColors.success),
    'approval': (Icons.task_alt_rounded, AppColors.success),
    'mentioned': (Icons.alternate_email_rounded, AppColors.info),
    'reminder': (Icons.schedule_rounded, AppColors.warning),
    'low_stock': (Icons.inventory_2_outlined, AppColors.warning),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !notification.isRead;
    final (icon, color) =
        _style[notification.type] ??
        (Icons.notifications_outlined, AppColors.neutral);

    return Material(
      color: unread
          ? scheme.primary.withValues(alpha: 0.05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (notification.body != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      '${fmtRelative(notification.createdAt)} · ${fmtDateTime(notification.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: Space.xs, top: 6),
                  child: Semantics(
                    label: 'Unread',
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
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
