import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/activity_screen.dart';
import 'admin/sites_screen.dart';
import 'admin/users_screen.dart';
import 'assets/asset_detail_screen.dart';
import 'assets/equipment_screen.dart';
import 'chat/call_screen.dart';
import 'chat/chat_list_screen.dart';
import 'chat/conversation_screen.dart';
import 'checklists/checklist_run_screen.dart';
import 'checklists/checklists_screen.dart';
import 'documents/document_detail_screen.dart';
import 'documents/documents_screen.dart';
import 'maintenance/planned_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'meetings/meeting_screen.dart';
import 'screens/more_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'reports/daily_report_screen.dart';
import 'services/core_providers.dart';
import 'tools/issue_form_detail_screen.dart';
import 'tools/issue_form_screen.dart';
import 'tools/tool_detail_screen.dart';
import 'tools/tools_screen.dart';
import 'v2/jobs_tab.dart';
import 'v2/routes.dart';
import 'widgets/app_shell.dart';

/// The bottom-bar / side-menu tabs, in order.
const shellTabs = [
  ShellTab('/home', 'Home', CupertinoIcons.house, CupertinoIcons.house_fill),
  ShellTab('/jobs', 'Jobs', CupertinoIcons.hammer, CupertinoIcons.hammer_fill),
  ShellTab(
    '/chat',
    'Chat',
    CupertinoIcons.chat_bubble_2,
    CupertinoIcons.chat_bubble_2_fill,
  ),
  ShellTab(
    '/menu',
    'Menu',
    CupertinoIcons.square_grid_2x2,
    CupertinoIcons.square_grid_2x2_fill,
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
    '/home': const HomeScreen(),
    '/chat': const ChatListScreen(),
    '/menu': const MoreScreen(),
  };

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      // Old tab addresses, kept for bookmarks.
      GoRoute(path: '/today', redirect: (_, _) => '/home'),
      GoRoute(path: '/board', redirect: (_, _) => '/jobs'),
      GoRoute(path: '/store', redirect: (_, _) => '/equipment?side=tools'),
      GoRoute(path: '/more', redirect: (_, _) => '/menu'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/jobs/recurring',
        builder: (_, _) => const RecurringScreen(),
      ),
      ...jobCardRoutes,
      jobCardDetailRoute,
      GoRoute(
        path: '/chat/:id/call',
        builder: (_, s) => CallScreen(
          conversationId: s.pathParameters['id']!,
          join: s.uri.queryParameters['join'] == '1',
          video: s.uri.queryParameters['video'] == '1',
          ringId: s.uri.queryParameters['ring'],
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ConversationScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
      GoRoute(path: '/admin/sites', builder: (_, _) => const SitesScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/meetings/:id',
        builder: (_, s) => MeetingScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/reports', builder: (_, _) => const DailyReportScreen()),
      GoRoute(
        path: '/admin/activity',
        builder: (_, _) => const ActivityScreen(),
      ),
      // Equipment and tools share one page; the old addresses open a side.
      GoRoute(
        path: '/equipment',
        builder: (_, s) => EquipmentScreen(
          side: switch (s.uri.queryParameters['side']) {
            'tools' => EquipmentSide.tools,
            'equipment' => EquipmentSide.equipment,
            _ => null,
          },
          mine: s.uri.queryParameters['mine'] == '1',
        ),
      ),
      GoRoute(path: '/assets', redirect: (_, _) => '/equipment?side=equipment'),
      GoRoute(
        path: '/tools',
        redirect: (_, s) => s.uri.queryParameters['mine'] == '1'
            ? '/equipment?side=tools&mine=1'
            : '/equipment?side=tools',
      ),
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
      // Tool issue forms: /tools/forms/new?tools=<id>,<id>&job=<job card id>
      GoRoute(
        path: '/tools/forms',
        builder: (_, _) => const IssueFormsScreen(),
      ),
      GoRoute(
        path: '/tools/forms/new',
        builder: (_, s) => IssueFormScreen(
          toolIds: [
            for (final id in (s.uri.queryParameters['tools'] ?? '').split(','))
              if (id.isNotEmpty) id,
          ],
          jobCardId: s.uri.queryParameters['job'],
        ),
      ),
      GoRoute(
        path: '/tools/forms/:id',
        builder: (_, s) => IssueFormDetailScreen(id: s.pathParameters['id']!),
      ),
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
                GoRoute(
                  path: tab.path,
                  // The Jobs tab keeps its filters in the address.
                  builder: (_, s) => tab.path == '/jobs'
                      ? JobsTab(query: s.uri.queryParameters)
                      : screens[tab.path]!,
                ),
              ],
            ),
        ],
      ),
    ],
  );
}
