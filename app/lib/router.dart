import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin/audit_screen.dart';
import 'admin/settings_screen.dart';
import 'admin/users_screen.dart';
import 'assets/asset_form_screen.dart';
import 'assets/asset_screen.dart';
import 'assets/assets_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'jobcards/job_card_screen.dart';
import 'jobcards/job_cards_screen.dart';
import 'jobcards/register_screen.dart';
import 'my_jobs/my_jobs_screen.dart';
import 'navigation.dart';
import 'requests/incoming_requests_screen.dart';
import 'requests/my_requests_screen.dart';
import 'requests/request_screen.dart';
import 'requests/submit_request_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/core_providers.dart';
import 'services/session_controller.dart';
import 'ui/bits.dart';
import 'widgets/app_shell.dart';

GoRouter buildRouter(WidgetRef ref) {
  final signedIn = ValueNotifier(ref.read(authUserIdProvider) != null);
  ref.listenManual(authUserIdProvider, (_, id) => signedIn.value = id != null);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!signedIn.value) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const _Home()),
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/job-cards',
            builder: (_, s) => JobCardsScreen(query: s.uri.queryParameters),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) => RegisterJobCardScreen(
                  requestId: s.uri.queryParameters['request'],
                ),
              ),
              GoRoute(
                path: ':ref',
                builder: (_, s) => JobCardScreen(
                  reference: s.pathParameters['ref']!,
                  initialTab: s.uri.queryParameters['tab'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/requests',
            builder: (_, _) => const IncomingRequestsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => RequestScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/my-requests',
            builder: (_, _) => const MyRequestsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const SubmitRequestScreen(),
              ),
            ],
          ),
          GoRoute(path: '/my-jobs', builder: (_, _) => const MyJobsScreen()),
          GoRoute(
            path: '/assets',
            builder: (_, _) => const AssetsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const AssetFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) => AssetScreen(id: s.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (_, s) => AssetFormScreen(id: s.pathParameters['id']),
              ),
            ],
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsScreen(),
          ),
          GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
          GoRoute(path: '/admin/audit', builder: (_, _) => const AuditScreen()),
          GoRoute(
            path: '/admin/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}

/// Sends people to the first screen their permissions allow.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.permissions != null && !session.perms.isEmpty) {
      final target = homePath(session.perms);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(target);
      });
    }
    return const LoadingPanel();
  }
}
