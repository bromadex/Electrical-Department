import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/board_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/store_screen.dart';
import 'screens/today_screen.dart';
import 'services/core_providers.dart';
import 'widgets/app_shell.dart';

/// The bottom-bar / side-menu tabs, in order.
const shellTabs = [
  ShellTab('/board', 'Board', Icons.view_kanban_outlined, Icons.view_kanban),
  ShellTab('/chat', 'Chat', Icons.forum_outlined, Icons.forum),
  ShellTab('/today', 'Today', Icons.today_outlined, Icons.today),
  ShellTab('/store', 'Store', Icons.inventory_2_outlined, Icons.inventory_2),
  ShellTab('/more', 'More', Icons.menu, Icons.menu_open),
];

class ShellTab {
  const ShellTab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

GoRouter buildRouter(WidgetRef ref) {
  final signedIn = ValueNotifier(ref.read(authUserIdProvider) != null);
  ref.listenManual(authUserIdProvider, (_, id) => signedIn.value = id != null);

  final screens = <String, Widget>{
    '/board': const BoardScreen(),
    '/chat': const ChatScreen(),
    '/today': const TodayScreen(),
    '/store': const StoreScreen(),
    '/more': const MoreScreen(),
  };

  return GoRouter(
    initialLocation: '/board',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/') return '/board';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/board'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          for (final tab in shellTabs)
            StatefulShellBranch(
              routes: [
                GoRoute(path: tab.path, builder: (_, _) => screens[tab.path]!),
              ],
            ),
        ],
      ),
    ],
  );
}
