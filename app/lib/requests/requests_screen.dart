import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../jobs/job_editor.dart';
import '../jobs/job_rules.dart';
import '../jobs/jobs_repository.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// A work request from outside the electrical team (API.md section 15).
class WorkRequest {
  WorkRequest.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      areaId = j['area_id'] as String?,
      code = j['code'] as String,
      title = j['title'] as String,
      description = j['description'] as String?,
      department = j['department'] as String?,
      priority = j['priority'] as String,
      status = j['status'] as String,
      requestedBy = j['requested_by'] as String,
      declineReason = j['decline_reason'] as String?,
      jobId = j['job_id'] as String?,
      createdAt = DateTime.parse(j['created_at'] as String).toLocal();

  final String id;
  final String siteId;
  final String? areaId;
  final String code;
  final String title;
  final String? description;
  final String? department;
  final String priority;
  final String status;
  final String requestedBy;
  final String? declineReason;
  final String? jobId;
  final DateTime createdAt;
}

/// Requests at the current site I can see: my own, plus every request if I
/// handle them (jobs.assign).
final requestsProvider = FutureProvider<List<WorkRequest>>((ref) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('job_requests')
      .select()
      .eq('site_id', site)
      .order('created_at', ascending: false)
      .limit(200);
  return [for (final r in rows) WorkRequest.fromJson(r)];
});

/// New requests waiting for a supervisor at the current site.
final newRequestCountProvider = Provider<int>((ref) {
  final session = ref.watch(sessionProvider);
  final site = ref.watch(currentSiteProvider);
  if (site == null || !session.can('jobs.assign', siteId: site.id)) return 0;
  return ref
          .watch(requestsProvider)
          .value
          ?.where((r) => r.status == 'new')
          .length ??
      0;
});

Color _statusColor(String s) => switch (s) {
  'accepted' => BrandColors.success,
  'declined' => Colors.red,
  _ => Colors.orange,
};

String _statusLabel(String s) => switch (s) {
  'accepted' => 'Accepted',
  'declined' => 'Declined',
  _ => 'Waiting',
};

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  bool _incoming = true;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(requestsProvider);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final me = ref.watch(authUserIdProvider);
    final handler = site != null && session.can('jobs.assign', siteId: site.id);
    final canRequest =
        site != null && session.can('req.create', siteId: site.id);
    final people = ref.watch(peopleProvider).value ?? const {};
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final incoming = handler && _incoming;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Work requests · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: canRequest
          ? FloatingActionButton.extended(
              onPressed: () => showFormSheet(context, const RequestForm()),
              icon: const Icon(CupertinoIcons.paperplane_fill),
              label: const Text('New request'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(requestsProvider),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              top + Space.md,
              Space.md,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (handler)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Wrap(
                            spacing: Space.xs,
                            children: [
                              ChoiceChip(
                                label: const Text('Incoming'),
                                selected: _incoming,
                                onSelected: (_) =>
                                    setState(() => _incoming = true),
                              ),
                              ChoiceChip(
                                label: const Text('Mine'),
                                selected: !_incoming,
                                onSelected: (_) =>
                                    setState(() => _incoming = false),
                              ),
                            ],
                          ),
                        ),
                      ...list.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load requests',
                            message: AppError.from(e).isRetryable
                                ? 'Requests load when you are connected.'
                                : AppError.from(e).message,
                          ),
                        ],
                        data: (rows) {
                          final shown =
                              [
                                for (final r in rows)
                                  if (incoming || r.requestedBy == me) r,
                              ]..sort((a, b) {
                                if (incoming && a.status != b.status) {
                                  return a.status == 'new' ? -1 : 1;
                                }
                                return b.createdAt.compareTo(a.createdAt);
                              });
                          if (shown.isEmpty) {
                            return [
                              Padding(
                                padding: const EdgeInsets.only(top: Space.xl),
                                child: EmptyState(
                                  icon: CupertinoIcons.tray,
                                  title: 'No requests',
                                  message: canRequest
                                      ? 'Need electrical work done? Send a '
                                            'request and track it here.'
                                      : 'Requests from other departments show '
                                            'here.',
                                ),
                              ),
                            ];
                          }
                          return [
                            for (final (i, r) in shown.indexed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: _RequestTile(
                                  request: r,
                                  who: people[r.requestedBy],
                                  handler: handler,
                                ),
                              ).entrance(context, index: i.clamp(0, 8)),
                          ];
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.who,
    required this.handler,
  });

  final WorkRequest request;
  final String? who;
  final bool handler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final priority = JobPriority.parse(r.priority);
    return SurfaceCard(
      onTap: () {
        if (r.jobId != null) {
          context.push('/jobs/${r.jobId}');
        } else if (handler && r.status == 'new') {
          showFormSheet(context, _DecideSheet(request: r));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RecordCode(r.code),
              const SizedBox(width: Space.xs),
              if (priority != JobPriority.normal)
                Pill(label: priority.label, color: priority.color, dense: true),
              const Spacer(),
              Pill(
                label: _statusLabel(r.status),
                color: _statusColor(r.status),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(r.title, style: theme.textTheme.titleSmall),
          if (r.description != null)
            Text(
              r.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            [
              ?who,
              ?r.department,
              relativeTime(r.createdAt),
              if (r.jobId != null) 'tap to open the job',
              if (r.status == 'new' && handler) 'tap to accept or decline',
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
          if (r.declineReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Declined: ${r.declineReason}',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class RequestForm extends ConsumerStatefulWidget {
  const RequestForm({super.key});

  @override
  ConsumerState<RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<RequestForm> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _department = TextEditingController();
  JobPriority _priority = JobPriority.normal;
  String? _areaId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _department.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_title.text.trim().length < 3) {
      setState(() => _error = 'Say what you need in a few words');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final outbox = ref.read(outboxProvider);
    final id = const Uuid().v4();
    await outbox.enqueue('fn_create_request', {
      'p_client_ref': id,
      'p_site': site.id,
      'p_area': _areaId,
      'p_title': _title.text.trim(),
      'p_description': _details.text.trim(),
      'p_department': _department.text.trim(),
      'p_priority': _priority.name,
    }, clientRef: id);
    await outbox.flush();
    ref.invalidate(requestsProvider);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request sent to the electrical team')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final areas = site == null ? <LocalArea>[] : session.areasAt(site.id);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New request', style: theme.textTheme.headlineSmall),
          label('What do you need?'),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Conveyor 2 motor not starting',
            ),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _details,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Details (optional)'),
          ),
          label('Your department'),
          TextField(
            controller: _department,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Production, Mining, Camp',
            ),
          ),
          label('How urgent?'),
          Wrap(
            spacing: Space.xs,
            children: [
              for (final p in JobPriority.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _priority == p,
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
          if (areas.isNotEmpty) ...[
            label('Where'),
            DropdownButtonFormField<String?>(
              initialValue: _areaId,
              items: [
                const DropdownMenuItem(value: null, child: Text('Not sure')),
                for (final a in areas)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(CupertinoIcons.paperplane_fill),
            label: const Text('Send request'),
          ),
        ],
      ),
    );
  }
}

/// A supervisor accepts (as a job, optionally assigned) or declines.
class _DecideSheet extends ConsumerStatefulWidget {
  const _DecideSheet({required this.request});

  final WorkRequest request;

  @override
  ConsumerState<_DecideSheet> createState() => _DecideSheetState();
}

class _DecideSheetState extends ConsumerState<_DecideSheet> {
  late JobPriority _priority = JobPriority.parse(widget.request.priority);
  String? _assignee;
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
      HapticFeedback.mediumImpact();
      ref.invalidate(requestsProvider);
      unawaited(ref.read(jobsSyncProvider.notifier).refresh());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    final db = ref.read(supabaseProvider);
    final people = ref.watch(assigneesProvider(r.siteId));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${r.code} · ${r.title}', style: theme.textTheme.headlineSmall),
          if (r.description != null) ...[
            const SizedBox(height: Space.xs),
            Text(r.description!),
          ],
          const SizedBox(height: Space.md),
          Text('Priority', style: theme.textTheme.labelLarge),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            children: [
              for (final p in JobPriority.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _priority == p,
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text('Assign to (optional)', style: theme.textTheme.labelLarge),
          const SizedBox(height: Space.xs),
          people.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Connect to pick someone.'),
            data: (list) => DropdownButtonFormField<String?>(
              initialValue: _assignee,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Leave on the board'),
                ),
                for (final p in list)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.name} · ${p.openJobs} open'),
                  ),
              ],
              onChanged: (v) => setState(() => _assignee = v),
            ),
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => db.rpc(
                      'fn_accept_request',
                      params: {
                        'p_request': r.id,
                        'p_priority': _priority.name,
                        'p_assignee': _assignee,
                      },
                    ),
                    '${r.code} is on the board',
                  ),
            icon: const Icon(CupertinoIcons.checkmark_alt),
            label: const Text('Accept as a job'),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(hintText: 'Reason, if declining'),
          ),
          const SizedBox(height: Space.xs),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _busy
                ? null
                : () {
                    if (_reason.text.trim().isEmpty) {
                      setState(() => _error = 'Say why it is declined');
                      return;
                    }
                    _run(
                      () => db.rpc(
                        'fn_decline_request',
                        params: {'p_request': r.id, 'p_reason': _reason.text},
                      ),
                      '${r.code} declined',
                    );
                  },
            icon: const Icon(CupertinoIcons.xmark),
            label: const Text('Decline'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}
