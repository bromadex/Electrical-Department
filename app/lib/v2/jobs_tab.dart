import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/session_controller.dart';
import '../ui/charts.dart';
import 'jobcards/job_cards_screen.dart';
import 'my_jobs/my_jobs_screen.dart';
import 'requests/my_requests_screen.dart';

/// The Jobs tab. People who do the work switch between their own jobs and
/// every job card with a glass switch at the top; technicians start on
/// their own, supervisors on all. People who only request work see their
/// requests. `?mine=1` or `?mine=0` in the address picks the side.
class JobsTab extends ConsumerWidget {
  const JobsTab({super.key, required this.query});

  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    bool can(String code) => session.can(code, siteId: site?.id);
    if (!can('jc.view')) return const MyRequestsScreen();
    if (!can('jc.execute')) return JobCardsScreen(query: query);

    final mine = switch (query['mine']) {
      '1' => true,
      '0' => false,
      _ => !can('jc.assign'),
    };
    final count = ref.watch(myJobsProvider).value?.length;
    final toggle = GlassSegmented<bool>(
      value: mine,
      segments: {
        true: count == null || count == 0 ? 'My jobs' : 'My jobs · $count',
        false: 'All job cards',
      },
      onChanged: (m) => context.go('/jobs?mine=${m ? 1 : 0}'),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      // Top-aligned: the default centres a short page, leaving a gap above.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: mine
          ? MyJobsScreen(key: const ValueKey('mine'), leading: toggle)
          : JobCardsScreen(
              key: const ValueKey('all'),
              query: query,
              leading: toggle,
              keepQuery: const {'mine': '0'},
            ),
    );
  }
}
