import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/notifications_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static String _group(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final items = state.items;

    final groups = <String, List<AppNotification>>{};
    for (final n in items) {
      groups.putIfAbsent(_group(n.createdAt.toLocal()), () => []).add(n);
    }
    var index = 0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        edgeOffset: 120,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar.large(
              title: const Text('Notifications'),
              backgroundColor: theme.colorScheme.surface,
              actions: [
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: state.unread > 0
                      ? TextButton.icon(
                          key: const ValueKey('all'),
                          onPressed: () => notifier.markRead(),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('Mark all read'),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: Space.xs),
              ],
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Center(
                    child: EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: state.error == null ? 'All caught up' : 'Offline',
                      message:
                          state.error?.message ??
                          'New jobs, mentions and reminders will appear here.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  0,
                  Space.md,
                  Space.xl,
                ),
                sliver: SliverList.list(
                  children: [
                    for (final MapEntry(key: label, value: list)
                        in groups.entries) ...[
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SectionHeader(label),
                        ),
                      ),
                      for (final n in list)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _NotificationTile(
                              key: ValueKey(n.id),
                              notification: n,
                              onRead: () {
                                if (!n.isRead) notifier.markRead([n.id]);
                                final link = n.link;
                                if (link != null && link.startsWith('job:')) {
                                  context.push('/jobs/${link.substring(4)}');
                                }
                              },
                            ).entrance(context, index: index++),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.onRead,
  });

  final AppNotification notification;
  final VoidCallback onRead;

  static const _style = {
    'assigned': (Icons.assignment_ind_outlined, BrandColors.info),
    'mentioned': (Icons.alternate_email_rounded, BrandColors.coral),
    'overdue': (Icons.schedule_rounded, BrandColors.warning),
    'reminder': (Icons.alarm_rounded, BrandColors.warning),
    'approval': (Icons.task_alt_rounded, BrandColors.success),
    'low_stock': (Icons.inventory_2_outlined, BrandColors.coral),
    'meeting': (Icons.groups_outlined, BrandColors.info),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !notification.isRead;
    final (icon, color) =
        _style[notification.type] ??
        (Icons.notifications_outlined, scheme.primary);

    final tile = AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: unread
            ? scheme.primary.withValues(alpha: 0.06)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: unread
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      _ago(notification.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
              ],
            ),
          ),
          AnimatedScale(
            scale: unread ? 1 : 0,
            duration: Motion.of(context, Motion.medium),
            curve: Motion.spring,
            child: Padding(
              padding: const EdgeInsets.only(left: Space.xs, top: 6),
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
    );

    if (!unread) return GestureDetector(onTap: onRead, child: tile);
    return Dismissible(
      key: ValueKey('dismiss-${notification.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onRead();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: Space.xs),
        padding: const EdgeInsets.only(left: Space.lg),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: BrandColors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: const Row(
          children: [
            Icon(Icons.done_rounded, color: BrandColors.success),
            SizedBox(width: Space.xs),
            Text(
              'Mark read',
              style: TextStyle(
                color: BrandColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(onTap: onRead, child: tile),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
