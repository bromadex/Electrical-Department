import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/app_services.dart';

/// Bell icon with the unread count; opens the notifications screen.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = AppScope.of(context).notifications;

    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final unread = notifications.unread;
        return IconButton(
          tooltip: unread == 0
              ? 'Notifications'
              : '$unread unread notifications',
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}
