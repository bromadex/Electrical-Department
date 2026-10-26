import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/activity_screen.dart';
import 'admin/targets_screen.dart';
import 'admin/users_screen.dart';
import 'assets/asset_detail_screen.dart';
import 'assets/assets_screen.dart';
import 'chat/chat_list_screen.dart';
import 'chat/conversation_screen.dart';
import 'checklists/checklist_run_screen.dart';
import 'checklists/checklists_screen.dart';
import 'documents/document_detail_screen.dart';
import 'documents/documents_screen.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/recurring_screen.dart';
import 'screens/board_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/store_screen.dart';
import 'screens/today_screen.dart';
import 'reports/daily_report_screen.dart';
import 'requests/requests_screen.dart';
import 'services/core_providers.dart';
import 'tools/tool_detail_screen.dart';
import 'tools/tools_screen.dart';
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
    '/chat': const ChatListScreen(),
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
        path: '/jobs/recurring',
        builder: (_, _) => const RecurringScreen(),
      ),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, s) => JobDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ConversationScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
      GoRoute(path: '/admin/targets', builder: (_, _) => const TargetsScreen()),
      GoRoute(path: '/requests', builder: (_, _) => const RequestsScreen()),
      GoRoute(path: '/reports', builder: (_, _) => const DailyReportScreen()),
      GoRoute(
        path: '/admin/activity',
        builder: (_, _) => const ActivityScreen(),
      ),
      GoRoute(path: '/assets', builder: (_, _) => const AssetsScreen()),
      GoRoute(path: '/tools', builder: (_, _) => const ToolsScreen()),
      GoRoute(path: '/checklists', builder: (_, _) => const ChecklistsScreen()),
      GoRoute(
        path: '/checklists/:id',
        builder: (_, s) => ChecklistRunScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/documents', builder: (_, _) => const DocumentsScreen()),
      GoRoute(
        path: '/documents/:id',
        builder: (_, s) => DocumentDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/tools/count', builder: (_, _) => const ToolCountScreen()),
      GoRoute(
        path: '/tools/:id',
        builder: (_, s) => ToolDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/assets/:id',
        builder: (_, s) => AssetDetailScreen(id: s.pathParameters['id']!),
      ),
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
