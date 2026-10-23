import 'package:flutter/cupertino.dart';
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
  ShellTab(
    '/board',
    'Board',
    CupertinoIcons.square_grid_2x2,
    CupertinoIcons.square_grid_2x2_fill,
  ),
  ShellTab(
    '/chat',
    'Chat',
    CupertinoIcons.chat_bubble_2,
    CupertinoIcons.chat_bubble_2_fill,
  ),
  ShellTab(
    '/today',
    'Today',
    CupertinoIcons.sun_max,
    CupertinoIcons.sun_max_fill,
  ),
  ShellTab(
    '/store',
    'Store',
    CupertinoIcons.cube_box,
    CupertinoIcons.cube_box_fill,
  ),
  ShellTab(
    '/more',
    'More',
    CupertinoIcons.person_crop_circle,
    CupertinoIcons.person_crop_circle_fill,
  ),
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
    initialLocation: '/today',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/') return '/today';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) =>
            AppShell(shell: shell, children: children),
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
