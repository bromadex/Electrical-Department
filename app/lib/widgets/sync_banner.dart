import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/outbox_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';

/// Small floating pills under the top bar: offline, unsent changes, and
/// changes the server rejected.
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
    final scheme = Theme.of(context).colorScheme;
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
            children: [
              if (offline)
                _Toast(
                  key: const ValueKey('offline'),
                  icon: Icons.cloud_off_rounded,
                  text: 'Offline · showing saved data',
                  action: 'Retry',
                  onAction: ref.read(sessionProvider.notifier).refresh,
                ),
              if (pending > 0)
                _Toast(
                  key: const ValueKey('pending'),
                  icon: Icons.sync_rounded,
                  spin: true,
                  text: pending == 1
                      ? '1 change waiting to sync'
                      : '$pending changes waiting to sync',
                  action: 'Sync now',
                  onAction: _outbox.flush,
                ),
              for (final entry in failed)
                _Toast(
                  key: ValueKey(entry.clientRef),
                  icon: Icons.error_outline_rounded,
                  color: scheme.error,
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

class _Toast extends StatelessWidget {
  const _Toast({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    this.color,
    this.spin = false,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  final Color? color;
  final bool spin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onInverseSurface;
    Widget i = Icon(icon, size: 18, color: c);
    if (spin && !Motion.reduced(context)) {
      i = i.animate(onPlay: (a) => a.repeat()).rotate(duration: 1200.ms);
    }
    return Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Center(
            child: Material(
              color: color == null
                  ? scheme.inverseSurface
                  : scheme.errorContainer,
              borderRadius: BorderRadius.circular(Radii.pill),
              elevation: 6,
              shadowColor: Colors.black26,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    i,
                    const SizedBox(width: Space.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color == null
                              ? scheme.onInverseSurface
                              : scheme.onErrorContainer,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: color == null
                            ? scheme.inversePrimary
                            : scheme.onErrorContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(action),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: Motion.of(context, Motion.medium))
        .slideY(
          begin: -0.6,
          end: 0,
          duration: Motion.of(context, Motion.slow),
          curve: Motion.spring,
        );
  }
}
