import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/notifications_controller.dart';
import '../theme/tokens.dart';

/// Bell with an unread badge that pops when the count changes.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));
    Widget badge = Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: const Icon(Icons.notifications_none_rounded),
    );
    if (unread > 0 && !Motion.reduced(context)) {
      badge = badge
          .animate(key: ValueKey(unread))
          .scaleXY(begin: 0.8, end: 1, duration: 450.ms, curve: Motion.spring)
          .then()
          .shake(hz: 3, rotation: 0.06, duration: 400.ms);
    }
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
      onPressed: () => context.push('/notifications'),
      icon: badge,
    );
  }
}
