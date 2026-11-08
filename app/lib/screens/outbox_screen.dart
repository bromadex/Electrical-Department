import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/outbox_service.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// "fn_create_mr" → "Create mr": a readable name for a queued action.
String actionLabel(String action) {
  const names = {
    'fn_create_mr': 'Material request',
    'fn_issue_stock': 'Stock issued',
    'fn_receive_stock': 'Stock received',
    'fn_return_stock': 'Stock taken back',
    'fn_adjust_stock': 'Stock adjusted',
    'fn_submit_count': 'Stock count',
    'fn_comment_job_card': 'Job card note',
    'fn_add_work_record': 'Work log entry',
    'fn_add_job_attachment': 'Job card file',
    'fn_send_message': 'Chat message',
    'fn_submit_checklist': 'Checklist',
    'fn_add_report_update': 'Daily report update',
    'fn_issue_tools': 'Tool issue form',
    'fn_return_tools': 'Tools taken back',
    'fn_set_roster': 'Roster',
    'fn_save_project': 'Project',
    'fn_create_reminder': 'Reminder',
  };
  final known = names[action];
  if (known != null) return known;
  final words = action.replaceFirst('fn_', '').replaceAll('_', ' ');
  return words.isEmpty ? action : words[0].toUpperCase() + words.substring(1);
}

String _size(int b) => b < 1024 * 1024
    ? '${(b / 1024).ceil()} KB'
    : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Everything made on this device that has not reached the server: files
/// first, then actions in order. Failed ones can be retried or discarded.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outbox = ref.watch(outboxProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const Text('Waiting to send'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          TextButton.icon(
            onPressed: () => outbox.flush(force: true),
            icon: const Icon(CupertinoIcons.arrow_up_circle),
            label: const Text('Send now'),
          ),
        ],
      ),
      body: MeshBackground(
        child: StreamBuilder(
          stream: outbox.watchAllUploads(),
          builder: (context, uploadsSnap) => StreamBuilder<List<OutboxEntry>>(
            stream: outbox.watchAll(),
            builder: (context, actionsSnap) {
              final uploads = uploadsSnap.data ?? const [];
              final actions = actionsSnap.data ?? const <OutboxEntry>[];
              final wait = outbox.waitUntil;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (uploads.isEmpty && actions.isEmpty)
                            const EmptyState(
                              icon: CupertinoIcons.checkmark_circle,
                              title: 'Everything is sent',
                              message:
                                  'Work done without signal waits here and '
                                  'sends by itself when the phone is back '
                                  'online.',
                            )
                          else
                            Text(
                              wait != null && DateTime.now().isBefore(wait)
                                  ? 'No signal: trying again at '
                                        '${TimeOfDay.fromDateTime(wait).format(context)}, '
                                        'or tap Send now.'
                                  : 'Sends by itself when there is signal. '
                                        'Nothing here is lost when the app '
                                        'closes.',
                              style: theme.textTheme.labelMedium,
                            ),
                          const SizedBox(height: Space.md),
                          if (uploads.isNotEmpty)
                            Panel(
                              icon: CupertinoIcons.photo_on_rectangle,
                              title: 'Files',
                              child: Column(
                                children: [
                                  for (final u in uploads)
                                    _Row(
                                      title: u.path.split('/').last,
                                      subtitle: _size(u.size),
                                      error: u.error,
                                      failed: u.tries >= OutboxService.maxTries,
                                      onRetry: () => outbox.retryUpload(u.id),
                                      onDiscard: () =>
                                          outbox.discardUpload(u.id),
                                    ),
                                ],
                              ),
                            ),
                          if (actions.isNotEmpty) ...[
                            const SizedBox(height: Space.md),
                            Panel(
                              icon: CupertinoIcons.list_bullet,
                              title: 'Changes',
                              child: Column(
                                children: [
                                  for (final a in actions)
                                    _Row(
                                      title: actionLabel(a.action),
                                      subtitle: a.clientRef.substring(0, 8),
                                      error: a.lastError,
                                      failed: a.tries >= OutboxService.maxTries,
                                      onRetry: () => outbox.retry(a.clientRef),
                                      onDiscard: () =>
                                          outbox.dismiss(a.clientRef),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.error,
    required this.failed,
    required this.onRetry,
    required this.onDiscard,
  });

  final String title;
  final String subtitle;
  final String? error;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        failed ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.clock,
        color: failed ? theme.colorScheme.error : null,
      ),
      title: Text(title),
      subtitle: Text(
        [
          subtitle,
          if (failed)
            'not saved: ${error ?? 'refused'}'
          else if (error != null)
            'waiting for signal',
        ].join(' · '),
        style: TextStyle(color: failed ? theme.colorScheme.error : null),
      ),
      trailing: failed
          ? Wrap(
              children: [
                IconButton(
                  tooltip: 'Try again',
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  onPressed: onRetry,
                ),
                IconButton(
                  tooltip: 'Discard',
                  icon: const Icon(CupertinoIcons.trash),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Discard this change?'),
                        content: const Text(
                          'It was never saved on the server and will be lost.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Keep'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) onDiscard();
                  },
                ),
              ],
            )
          : null,
    );
  }
}
