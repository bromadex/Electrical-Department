import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/outbox_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';

/// Strips under the top bar: offline, changes waiting to sync, and changes
/// the server rejected. Nothing shows when everything is in order.
class SyncBanner extends ConsumerStatefulWidget {
  const SyncBanner({super.key});

  @override
  ConsumerState<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends ConsumerState<SyncBanner> {
  late OutboxService _outbox;
  late Stream<int> _pending;
  late Stream<List<OutboxEntry>> _failed;

  @override
  void initState() {
    super.initState();
    _outbox = ref.read(outboxProvider);
    _pending = _outbox.watchPending();
    _failed = _outbox.watchFailed();
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(
      sessionProvider.select((s) => s.error != null && s.profile != null),
    );
    return StreamBuilder<int>(
      stream: _pending,
      builder: (context, pendingSnap) => StreamBuilder<List<OutboxEntry>>(
        stream: _failed,
        builder: (context, failedSnap) {
          final pending = pendingSnap.data ?? 0;
          final failed = failedSnap.data ?? const [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (offline)
                _Strip(
                  color: AppColors.warning,
                  icon: Icons.cloud_off_rounded,
                  text: 'Offline — showing saved data. Changes to job cards need a connection.',
                  action: 'Retry',
                  onAction: ref.read(sessionProvider.notifier).refresh,
                ),
              if (pending > 0)
                _Strip(
                  color: AppColors.info,
                  icon: Icons.sync_rounded,
                  text: pending == 1
                      ? '1 change waiting to sync'
                      : '$pending changes waiting to sync',
                  action: 'Sync now',
                  onAction: _outbox.flush,
                ),
              for (final entry in failed)
                _Strip(
                  color: AppColors.critical,
                  icon: Icons.error_outline_rounded,
                  text: 'Not saved: ${entry.lastError ?? 'unknown error'}',
                  action: 'Dismiss',
                  onAction: () => _outbox.dismiss(entry.clientRef),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
