import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../jobcards/action_sheets.dart' show askReason;
import '../jobcards/repository.dart';
import '../../services/core_providers.dart';
import '../../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/format.dart';
import '../ui/forms.dart';
import '../ui/media.dart';
import '../ui/page.dart';
import '../ui/panels.dart';
import '../ui/status.dart';
import 'models.dart';
import 'repository.dart';
import 'request_tile.dart';

/// A request with its progress. Requesters see the job card's public state
/// and the updates the department shares; staff can register or triage it.
class RequestScreen extends ConsumerWidget {
  const RequestScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(requestTrackingProvider(id)),
      onRetry: () => ref.invalidate(requestTrackingProvider(id)),
      data: (t) => _RequestView(tracking: t),
    );
  }
}

class _RequestView extends ConsumerStatefulWidget {
  const _RequestView({required this.tracking});

  final RequestTracking tracking;

  @override
  ConsumerState<_RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends ConsumerState<_RequestView> {
  final _comment = TextEditingController();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracking;
    final r = t.request;
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final mine = r.requestedBy == me;
    final canTriage = session.can('req.triage', siteId: r.siteId);
    final canSeeJob = session.can('jc.view', siteId: r.siteId);
    final job = t.job;
    final theme = Theme.of(context);

    return AppPage(
      title: r.requestNo,
      subtitle: r.title,
      maxWidth: 1000,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    RequestStatusPill(r.status),
                    if (r.impact != null)
                      Pill(
                        label: r.impact!.label,
                        color: r.impact!.color,
                        dense: true,
                        solid: r.urgent,
                      ),
                  ],
                ),
                if (r.statusReason != null &&
                    r.status != RequestStatus.submitted) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    'Electrical department: “${r.statusReason}”',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: Space.md),
                KeyValue(
                  'What is wrong',
                  null,
                  child: CopyableText(r.description),
                ),
                const SizedBox(height: Space.md),
                ResponsiveGrid(
                  minItemWidth: 200,
                  children: [
                    KeyValue('Reported by', r.reporterName),
                    KeyValue('Department', r.departmentName),
                    KeyValue(
                      'Where',
                      [r.siteName, r.place].whereType<String>().join(' · '),
                    ),
                    KeyValue('Equipment', r.equipment),
                    KeyValue('Contact', r.contact),
                    KeyValue('Submitted', fmtDateTime(r.submittedAt)),
                    if (r.clarificationNote != null)
                      KeyValue('Your answer', r.clarificationNote),
                  ],
                ),
                if (t.attachments.isNotEmpty) ...[
                  const SectionHeader('Photos'),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final a in t.attachments)
                        _RequestPhoto(
                          path: a['path'] as String,
                          name: a['file_name'] as String?,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          if (job != null)
            Panel(
              title: 'Job card ${job['number']}',
              icon: Icons.assignment_outlined,
              actions: [
                if (canSeeJob)
                  TextButton(
                    onPressed: () => context.push('/jobs/${job['number']}'),
                    child: const Text('Open job card'),
                  ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t.jobStatus != null) StatusPill(t.jobStatus!),
                  const SizedBox(height: Space.sm),
                  ResponsiveGrid(
                    minItemWidth: 200,
                    children: [
                      KeyValue(
                        'Being worked on by',
                        job['responsible_name'] as String?,
                      ),
                      KeyValue(
                        'Accepted',
                        fmtDateTime(parseTime(job['accepted_at'])),
                      ),
                      KeyValue(
                        'Target completion',
                        fmtDateTime(parseTime(job['target_completion_at'])),
                      ),
                      KeyValue(
                        'Completed',
                        fmtDateTime(parseTime(job['closed_at'])),
                      ),
                    ],
                  ),
                  const SectionHeader('Updates from the electrical department'),
                  if (t.updates.isEmpty) const Text('No updates yet.'),
                  for (final u in t.updates)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AppAvatar(
                        name: u['author'] as String? ?? '?',
                        size: 32,
                      ),
                      title: Text(u['body'] as String),
                      subtitle: Text(
                        '${u['author']} · ${fmtDateTime(parseTime(u['created_at']))}',
                      ),
                    ),
                  if (mine && (t.jobStatus?.isOpen ?? false)) ...[
                    const SizedBox(height: Space.xs),
                    TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Add a note for the electrical department',
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final body = _comment.text.trim();
                                if (body.isEmpty) return;
                                await _run(
                                  () => ref
                                      .read(jobCardActionsProvider)
                                      .comment(job['id'] as String, body),
                                  'Note sent',
                                );
                                _comment.clear();
                              },
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (mine && r.status == RequestStatus.returned) _Resubmit(request: r),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              if (canTriage &&
                  r.status == RequestStatus.submitted &&
                  session.can('jc.register', siteId: r.siteId))
                FilledButton.icon(
                  onPressed: () => context.push('/jobs/new?request=${r.id}'),
                  icon: const Icon(Icons.assignment_add),
                  label: const Text('Register job card'),
                ),
              if (canTriage && r.status == RequestStatus.submitted) ...[
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await askReason(
                            context,
                            title: 'Ask for more information',
                            label: 'What do you need to know?',
                            confirm: 'Send back',
                          );
                          if (reason != null) {
                            await _run(
                              () => ref
                                  .read(requestActionsProvider)
                                  .triage(r.id, 'return', reason),
                              'Sent back',
                            );
                          }
                        },
                  icon: const Icon(Icons.reply_rounded),
                  label: const Text('Ask for information'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.critical,
                  ),
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await askReason(
                            context,
                            title: 'Do not accept the request',
                            label: 'Reason',
                            confirm: 'Reject',
                            danger: true,
                          );
                          if (reason != null) {
                            await _run(
                              () => ref
                                  .read(requestActionsProvider)
                                  .triage(r.id, 'reject', reason),
                              'Rejected',
                            );
                          }
                        },
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Reject'),
                ),
              ],
              if (mine &&
                  (r.status == RequestStatus.submitted ||
                      r.status == RequestStatus.returned))
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await askReason(
                            context,
                            title: 'Withdraw request',
                            label: 'Why are you withdrawing it?',
                            confirm: 'Withdraw',
                          );
                          if (reason != null) {
                            await _run(
                              () => ref
                                  .read(requestActionsProvider)
                                  .withdraw(r.id, reason),
                              'Request withdrawn',
                            );
                          }
                        },
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Withdraw'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestPhoto extends ConsumerWidget {
  const _RequestPhoto({required this.path, this.name});

  final String path;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(requestActionsProvider).fileUrl(path),
      builder: (context, snap) => FileThumb(
        url: snap.data,
        name: name,
        isImage: PickedFile.contentTypeFor(path).startsWith('image/'),
        onTap: snap.data == null
            ? null
            : () => showImage(context, url: snap.data),
      ),
    );
  }
}

/// The requester answers the department's question and resubmits.
class _Resubmit extends ConsumerStatefulWidget {
  const _Resubmit({required this.request});

  final ServiceRequest request;

  @override
  ConsumerState<_Resubmit> createState() => _ResubmitState();
}

class _ResubmitState extends ConsumerState<_Resubmit> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.request.title);
  late final _description = TextEditingController(
    text: widget.request.description,
  );
  late String? _impact = widget.request.impact?.db;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Panel(
        title: 'Answer and send back',
        icon: Icons.reply_rounded,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Your answer *'),
                validator: Valid.length(2, 2000, 'Your answer'),
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: Valid.length(3, 120, 'The title'),
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'What is wrong?'),
                validator: Valid.length(5, 4000, 'The description'),
              ),
              const SizedBox(height: Space.sm),
              ChoiceField<String>(
                label: 'Effect on operations',
                value: _impact,
                onChanged: (v) => setState(() => _impact = v),
                options: [
                  for (final i in Impact.values) (i.db, i.label, null, i.color),
                ],
              ),
              const SizedBox(height: Space.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!_form.currentState!.validate() ||
                              _impact == null) {
                            return;
                          }
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(requestActionsProvider)
                                .resubmit(
                                  widget.request.id,
                                  title: _title.text,
                                  description: _description.text,
                                  impact: _impact!,
                                  note: _note.text,
                                );
                            if (context.mounted) {
                              showSnack(
                                context,
                                'Sent back to the electrical department',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
