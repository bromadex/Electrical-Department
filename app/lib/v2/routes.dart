import 'package:go_router/go_router.dart';

import 'admin/audit_screen.dart';
import 'admin/settings_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'job_page.dart';
import 'jobcards/job_card_screen.dart';
import 'jobcards/register_screen.dart';
import 'my_jobs/my_jobs_screen.dart';
import 'requests/incoming_requests_screen.dart';
import 'requests/my_requests_screen.dart';
import 'requests/request_screen.dart';
import 'requests/submit_request_screen.dart';

/// Job card screens opened on top of the tabs. The job cards list itself is
/// the Jobs tab (see router.dart). Listed before `/jobs/:ref` so the fixed
/// paths win.
final jobCardRoutes = <RouteBase>[
  GoRoute(
    path: '/jobs/mine',
    builder: (_, _) => const JobPage(title: 'My jobs', child: MyJobsScreen()),
  ),
  GoRoute(
    path: '/jobs/new',
    builder: (_, s) => JobPage(
      title: 'New job card',
      child: RegisterJobCardScreen(
        requestId: s.uri.queryParameters['request'],
        title: s.uri.queryParameters['title'],
        description: s.uri.queryParameters['description'],
        assetId: s.uri.queryParameters['asset'],
      ),
    ),
  ),
  GoRoute(
    path: '/requests',
    builder: (_, _) =>
        const JobPage(title: 'Requests', child: IncomingRequestsScreen()),
  ),
  GoRoute(
    path: '/requests/:id',
    builder: (_, s) => JobPage(
      title: 'Request',
      fallback: '/requests',
      child: RequestScreen(id: s.pathParameters['id']!),
    ),
  ),
  GoRoute(
    path: '/my-requests',
    builder: (_, _) => const JobPage(
      title: 'My requests',
      fallback: '/home',
      child: MyRequestsScreen(),
    ),
  ),
  GoRoute(
    path: '/my-requests/new',
    builder: (_, _) => const JobPage(
      title: 'Request work',
      fallback: '/my-requests',
      child: SubmitRequestScreen(),
    ),
  ),
  GoRoute(
    path: '/job-stats',
    builder: (_, _) => const JobPage(
      title: 'Job statistics',
      fallback: '/menu',
      child: DashboardScreen(),
    ),
  ),
  GoRoute(
    path: '/admin/job-settings',
    builder: (_, _) => const JobPage(
      title: 'Job card settings',
      fallback: '/menu',
      child: SettingsScreen(),
    ),
  ),
  GoRoute(
    path: '/admin/audit',
    builder: (_, _) => const JobPage(
      title: 'Activity log',
      fallback: '/menu',
      child: AuditScreen(),
    ),
  ),
  // Old Job Cards Version 2 addresses, kept for links in notifications.
  GoRoute(path: '/v2', redirect: (_, _) => '/jobs'),
  GoRoute(path: '/v2/dashboard', redirect: (_, _) => '/job-stats'),
  GoRoute(path: '/v2/my-jobs', redirect: (_, _) => '/jobs/mine'),
  GoRoute(path: '/v2/audit', redirect: (_, _) => '/admin/audit'),
  GoRoute(path: '/v2/settings', redirect: (_, _) => '/admin/job-settings'),
  GoRoute(path: '/v2/my-requests', redirect: (_, _) => '/my-requests'),
  GoRoute(path: '/v2/my-requests/new', redirect: (_, _) => '/my-requests/new'),
  GoRoute(path: '/v2/requests', redirect: (_, _) => '/requests'),
  GoRoute(
    path: '/v2/requests/:id',
    redirect: (_, s) => '/requests/${s.pathParameters['id']}',
  ),
  GoRoute(
    path: '/v2/job-cards',
    redirect: (_, s) => Uri(
      path: '/jobs',
      query: s.uri.hasQuery ? s.uri.query : null,
    ).toString(),
  ),
  GoRoute(
    path: '/v2/job-cards/new',
    redirect: (_, s) => Uri(
      path: '/jobs/new',
      query: s.uri.hasQuery ? s.uri.query : null,
    ).toString(),
  ),
  GoRoute(
    path: '/v2/job-cards/:ref',
    redirect: (_, s) => Uri(
      path: '/jobs/${s.pathParameters['ref']}',
      query: s.uri.hasQuery ? s.uri.query : null,
    ).toString(),
  ),
];

/// One job card; listed after every fixed `/jobs/...` path.
final jobCardDetailRoute = GoRoute(
  path: '/jobs/:ref',
  builder: (_, s) => JobPage(
    // Notification links carry the id; the title then reads "Job card".
    title: s.pathParameters['ref']!.length == 36
        ? 'Job card'
        : s.pathParameters['ref']!,
    child: JobCardScreen(
      reference: s.pathParameters['ref']!,
      initialTab: s.uri.queryParameters['tab'],
    ),
  ),
);
