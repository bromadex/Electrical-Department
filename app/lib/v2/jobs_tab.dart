import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_controller.dart';
import 'jobcards/job_cards_screen.dart';
import 'requests/my_requests_screen.dart';

/// The Jobs tab: job cards for the electrical team; for people who only
/// request work, the requests they have sent.
class JobsTab extends ConsumerWidget {
  const JobsTab({super.key, required this.query});

  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(currentSiteProvider);
    final canView = ref.watch(
      sessionProvider.select((s) => s.can('jc.view', siteId: site?.id)),
    );
    return canView ? JobCardsScreen(query: query) : const MyRequestsScreen();
  }
}
