import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/session_controller.dart';
import 'admin/audit_screen.dart';
import 'admin/settings_screen.dart';
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
import 'shell.dart';
import 'ui/bits.dart';

/// Job Cards Version 2: every screen lives under /v2, inside its own shell.
final v2Routes = ShellRoute(
  builder: (context, state, child) => V2Shell(child: child),
  routes: [
    GoRoute(path: '/v2', builder: (_, _) => const _Home()),
    GoRoute(path: '/v2/dashboard', builder: (_, _) => const DashboardScreen()),
    GoRoute(
      path: '/v2/job-cards',
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
      path: '/v2/requests',
      builder: (_, _) => const IncomingRequestsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, s) => RequestScreen(id: s.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/v2/my-requests',
      builder: (_, _) => const MyRequestsScreen(),
      routes: [
        GoRoute(path: 'new', builder: (_, _) => const SubmitRequestScreen()),
      ],
    ),
    GoRoute(path: '/v2/my-jobs', builder: (_, _) => const MyJobsScreen()),
    GoRoute(path: '/v2/audit', builder: (_, _) => const AuditScreen()),
    GoRoute(path: '/v2/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

/// Opens the first Version 2 screen the person's permissions allow.
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
