import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/page.dart';
import 'repository.dart';
import 'request_tile.dart';

class MyRequestsScreen extends ConsumerWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myRequestsProvider);
    return AppPage(
      title: 'My Requests',
      subtitle: 'Electrical faults and work you have asked for',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/v2/my-requests/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New request'),
        ),
      ],
      child: AsyncView(
        value: requests,
        onRetry: () => ref.invalidate(myRequestsProvider),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.outbox_outlined,
                title: 'No requests yet',
                message: 'Report an electrical fault or ask for work, and follow it here.',
                action: FilledButton.icon(
                  onPressed: () => context.go('/v2/my-requests/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New request'),
                ),
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
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
