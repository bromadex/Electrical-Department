import 'admin/errors_screen.dart';
import 'admin/permissions_screen.dart';
import 'screens/outbox_screen.dart';
import 'procurement/materials_screen.dart';
import 'reports/reports_archive_screen.dart';
import 'store/stock_stats_screen.dart';
import 'projects/calendar_screen.dart';
import 'projects/projects_screen.dart';
import 'projects/roster_screen.dart';
import 'tools/tool_stats_screen.dart';
import 'store/store_count_screen.dart';
import 'store/store_counts_screen.dart';
import 'search/search_screen.dart';
import 'screens/first_password_screen.dart';
import 'store/store_screen.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/activity_screen.dart';
import 'admin/sites_screen.dart';
import 'admin/users_screen.dart';
import 'assets/asset_detail_screen.dart';
import 'assets/equipment_screen.dart';
import 'chat/call_screen.dart';
import 'chat/calls_screen.dart';
import 'chat/wallpaper.dart';
import 'chat/guest_call_screen.dart';
import 'chat/group_info_screen.dart';
import 'meetings/meetings_list_screen.dart';
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
import 'reminders/reminders_screen.dart';
import 'tools/holders_screen.dart';
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
  // Chat is not a tab: it opens from the floating button (chat_fab.dart).
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
  // Someone with an admin's temporary password chooses their own first.
  final auth = ref.read(supabaseProvider).auth;
  final mustChange = ValueNotifier(mustChangePassword(auth.currentUser));
  // The router lives as long as the app, so this listener does too.
  auth.onAuthStateChange.listen(
    (s) => mustChange.value = mustChangePassword(s.session?.user),
    onError: (_) {},
  );

  final screens = <String, Widget>{
    '/home': const HomeScreen(),
    '/menu': const MoreScreen(),
  };

  return GoRouter(
    initialLocation: '/home',
    // An address the app does not know (an old bookmark, or what is left
    // of an emailed sign-in link such as "#sb") opens Home instead of an
    // error page. The redirect then sends you to sign in or choose a
    // password if needed.
    onException: (_, _, router) => router.go('/home'),
    refreshListenable: Listenable.merge([signedIn, mustChange]),
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      final atFirst = state.matchedLocation == '/first-password';
      // Guests join a call by link without an account.
      if (state.matchedLocation.startsWith('/guest/')) return null;
      if (!signedIn.value) return atLogin ? null : '/login';
      if (mustChange.value) return atFirst ? null : '/first-password';
      if (atLogin || atFirst || state.matchedLocation == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/first-password',
        builder: (_, _) => const FirstPasswordScreen(),
      ),
      // Old tab addresses, kept for bookmarks.
      GoRoute(path: '/today', redirect: (_, _) => '/home'),
      GoRoute(path: '/board', redirect: (_, _) => '/jobs'),
      GoRoute(path: '/inventory', builder: (_, _) => const StoreScreen()),
      GoRoute(path: '/outbox', builder: (_, _) => const OutboxScreen()),
      GoRoute(
        path: '/admin/errors',
        builder: (_, _) => const AppErrorsScreen(),
      ),
      GoRoute(path: '/projects', builder: (_, _) => const ProjectsScreen()),
      GoRoute(
        path: '/projects/:id',
        builder: (_, s) => ProjectScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(
        path: '/roster',
        builder: (_, s) => RosterScreen(
          day: DateTime.tryParse(s.uri.queryParameters['day'] ?? ''),
        ),
      ),
      GoRoute(path: '/materials', builder: (_, _) => const MaterialsScreen()),
      GoRoute(
        path: '/materials/new',
        builder: (_, s) => MaterialRequestForm(
          jobCardId: s.uri.queryParameters['job'],
          projectId: s.uri.queryParameters['project'],
          siteId: s.uri.queryParameters['site'],
        ),
      ),
      GoRoute(
        path: '/materials/:id',
        builder: (_, s) => MaterialRequestScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/purchases',
        builder: (_, _) => const MaterialsScreen(purchases: true),
      ),
      GoRoute(
        path: '/purchases/new',
        builder: (_, s) => PurchaseForm(mrId: s.uri.queryParameters['mr']),
      ),
      GoRoute(
        path: '/purchases/:id',
        builder: (_, s) => PurchaseScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/tools/stats', builder: (_, _) => const ToolStatsScreen()),
      // Store was renamed Inventory; old links still open.
      GoRoute(
        path: '/store/:id',
        redirect: (_, s) => '/inventory/${s.pathParameters['id']}',
      ),
      GoRoute(path: '/store', redirect: (_, _) => '/inventory'),
      GoRoute(
        path: '/inventory/stats',
        builder: (_, _) => const StockStatsScreen(),
      ),
      GoRoute(
        path: '/admin/permissions',
        builder: (_, _) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/reports/archive',
        builder: (_, _) => const ReportsArchiveScreen(),
      ),
      GoRoute(
        path: '/inventory/count',
        builder: (_, _) => const StoreCountScreen(),
      ),
      GoRoute(
        path: '/inventory/counts',
        builder: (_, _) => const StoreCountsScreen(),
      ),
      GoRoute(
        path: '/inventory/:id',
        builder: (_, s) => StoreItemScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/more', redirect: (_, _) => '/menu'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/jobs/recurring',
        builder: (_, _) => const RecurringScreen(),
      ),
      ...jobCardRoutes,
      jobCardDetailRoute,
      GoRoute(
        path: '/calls',
        builder: (_, _) => const ChatThemed(child: CallsScreen()),
      ),
      // The chat list, opened from the floating chat button.
      GoRoute(path: '/chat', builder: (_, _) => const ChatHomeScreen()),
      GoRoute(
        path: '/guest/:token',
        builder: (_, s) => GuestCallScreen(token: s.pathParameters['token']!),
      ),
      GoRoute(path: '/meetings', builder: (_, _) => const MeetingsListScreen()),
      GoRoute(
        path: '/starred',
        builder: (_, _) => const ChatThemed(child: StarredScreen()),
      ),
      GoRoute(
        path: '/chat/:id/info',
        builder: (_, s) =>
            ChatThemed(child: GroupInfoScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/chat/:id/starred',
        builder: (_, s) => ChatThemed(
          child: StarredScreen(conversationId: s.pathParameters['id']!),
        ),
      ),
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
        builder: (_, s) =>
            ChatThemed(child: ConversationScreen(id: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
      GoRoute(path: '/admin/sites', builder: (_, _) => const SitesScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/meetings/:id',
        builder: (_, s) => MeetingScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, s) => DailyReportScreen(
          day: DateTime.tryParse(s.uri.queryParameters['date'] ?? ''),
        ),
      ),
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
      GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
      GoRoute(
        path: '/tools/holders',
        builder: (_, _) => const ToolHoldersScreen(),
      ),
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
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
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

/// The page on top, including pages pushed over another (a chat, a call),
/// which `currentConfiguration.uri` leaves out: that is only the page
/// underneath. Used to hide the chat button and call bar where they would
/// cover a chat or call, and to light the side bar.
String topPath(GoRouter router) {
  try {
    final config = router.routerDelegate.currentConfiguration;
    if (config.isEmpty) return '';
    return Uri.parse(config.last.matchedLocation).path;
  } catch (_) {
    return '';
  }
}
