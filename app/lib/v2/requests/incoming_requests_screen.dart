import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobcards/action_sheets.dart' show askReason;
import '../../services/session_controller.dart';
import '../site_filter.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/page.dart';
import 'models.dart';
import 'repository.dart';
import 'request_tile.dart';

/// The electrical department's queue of requests from other departments.
/// A request becomes a job card only when someone registers it here.
class IncomingRequestsScreen extends ConsumerStatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  ConsumerState<IncomingRequestsScreen> createState() =>
      _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState
    extends ConsumerState<IncomingRequestsScreen> {
  bool _includeReturned = false;

  Future<void> _triage(ServiceRequest r, String action) async {
    final reason = await askReason(
      context,
      title: action == 'return'
          ? 'Ask for more information'
          : 'Do not accept the request',
      label: action == 'return'
          ? 'What do you need to know? (the requester sees this)'
          : 'Reason (the requester sees this)',
      confirm: action == 'return' ? 'Send back' : 'Reject',
      danger: action == 'reject',
    );
    if (reason == null) return;
    try {
      await ref.read(requestActionsProvider).triage(r.id, action, reason);
      if (mounted) {
        showSnack(
          context,
          action == 'return'
              ? '${r.requestNo} sent back to the requester'
              : '${r.requestNo} rejected',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteFilterProvider);
    final requests = ref.watch(
      incomingRequestsProvider((site, _includeReturned)),
    );
    final canRegister = ref.watch(
      sessionProvider.select((s) => s.perms.can('jc.register')),
    );
    return AppPage(
      title: 'Incoming Requests',
      subtitle: 'Faults and work requested by other departments, waiting to be registered',
      actions: [
        FilterChip(
          label: const Text('Show returned'),
          selected: _includeReturned,
          onSelected: (v) => setState(() => _includeReturned = v),
        ),
      ],
      child: AsyncView(
        value: requests,
        onRetry: () =>
            ref.invalidate(incomingRequestsProvider((site, _includeReturned))),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No requests waiting',
                message: 'New requests from other departments appear here.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: RequestTile(
                        request: r,
                        onTap: () => context.go('/v2/requests/${r.id}'),
                        actions: r.status != RequestStatus.submitted
                            ? const []
                            : [
                                if (canRegister)
                                  FilledButton.icon(
                                    onPressed: () => context.go(
                                      '/v2/job-cards/new?request=${r.id}',
                                    ),
                                    icon: const Icon(Icons.assignment_add),
                                    label: const Text('Register job card'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => _triage(r, 'return'),
                                  icon: const Icon(Icons.reply_rounded),
                                  label: const Text('Ask for information'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.critical,
                                  ),
                                  onPressed: () => _triage(r, 'reject'),
                                  icon: const Icon(Icons.block_rounded),
                                  label: const Text('Reject'),
                                ),
                              ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
