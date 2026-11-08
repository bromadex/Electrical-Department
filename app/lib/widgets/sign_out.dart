import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/core_providers.dart';

/// Signs out, but never silently loses work: if changes or files made on
/// this device have not reached the server yet, asks first.
Future<void> signOutWithCheck(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(authUserIdProvider.notifier);
  final left = await auth.signOut();
  if (left == 0 || !context.mounted) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        '$left ${left == 1 ? 'change has' : 'changes have'} not been sent',
      ),
      content: const Text(
        'They are only on this phone. Wait until there is signal and they '
        'send by themselves, or see what is waiting. Signing out now '
        'deletes them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'review'),
          child: const Text('See what is waiting'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Sign out and delete them'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Stay signed in'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'review':
      context.push('/outbox');
    case 'discard':
      await auth.signOut(discardUnsent: true);
  }
}
