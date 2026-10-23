import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../services/notifications_controller.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = AppScope.of(context).notifications;

    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final items = notifications.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (notifications.unread > 0)
                TextButton(
                  onPressed: () => notifications.markRead(),
                  child: const Text('Mark all read'),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: notifications.refresh,
            child: items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          notifications.error?.message ??
                              'No notifications yet.',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _NotificationTile(
                      notification: items[i],
                      onTap: () => notifications.markRead([items[i].id]),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  static const _icons = {
    'assigned': Icons.assignment_ind_outlined,
    'mentioned': Icons.alternate_email,
    'overdue': Icons.schedule,
    'reminder': Icons.alarm,
    'approval': Icons.task_alt,
    'low_stock': Icons.inventory_2_outlined,
    'meeting': Icons.groups_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.isRead;

    return ListTile(
      onTap: unread ? onTap : null,
      leading: Icon(
        _icons[notification.type] ?? Icons.notifications_outlined,
        color: unread ? theme.colorScheme.primary : null,
      ),
      title: Text(
        notification.title,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: notification.body == null ? null : Text(notification.body!),
      trailing: Text(
        _ago(notification.createdAt),
        style: theme.textTheme.bodySmall,
      ),
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
