import 'package:flutter/material.dart';

import '../data/local_db.dart';
import '../services/app_services.dart';
import '../services/outbox_service.dart';

/// Shows unsent outbox entries and ones the server rejected.
class SyncBanner extends StatefulWidget {
  const SyncBanner({super.key});

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  late OutboxService _outbox;
  late Stream<int> _pending;
  late Stream<List<OutboxEntry>> _failed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outbox = AppScope.of(context).outbox;
    _pending = _outbox.watchPending();
    _failed = _outbox.watchFailed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<int>(
          stream: _pending,
          builder: (context, snap) {
            final pending = snap.data ?? 0;
            if (pending == 0) return const SizedBox.shrink();
            return MaterialBanner(
              leading: const Icon(Icons.cloud_upload_outlined),
              content: Text(
                pending == 1
                    ? '1 change is waiting to sync.'
                    : '$pending changes are waiting to sync.',
              ),
              actions: [
                TextButton(
                  onPressed: _outbox.flush,
                  child: const Text('Retry now'),
                ),
              ],
            );
          },
        ),
        StreamBuilder<List<OutboxEntry>>(
          stream: _failed,
          builder: (context, snap) {
            final failed = snap.data ?? const [];
            return Column(
              children: [
                for (final entry in failed)
                  MaterialBanner(
                    backgroundColor: theme.colorScheme.errorContainer,
                    leading: Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    content: Text(
                      'Could not sync: ${entry.lastError ?? 'unknown error'}',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => _outbox.dismiss(entry.clientRef),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
