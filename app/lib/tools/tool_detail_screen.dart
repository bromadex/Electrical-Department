import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../ui/form_sheet.dart';
import '../ui/time.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/signature_pad.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/record_hero.dart';
import '../ui/surfaces.dart';
import 'issue_forms_repository.dart';
import 'tools_repository.dart';
import 'tools_screen.dart';
import '../widgets/app_back_button.dart';

/// One tool: the shared record header, quick actions (lend or take back),
/// then Who had it · Jobs · Details.
class ToolDetailScreen extends ConsumerStatefulWidget {
  const ToolDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ToolDetailScreen> createState() => _ToolDetailScreenState();
}

enum _Tab { history, jobs, details }

class _ToolDetailScreenState extends ConsumerState<ToolDetailScreen> {
  _Tab _tab = _Tab.history;

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final tool = ref.watch(toolProvider(id)).value;
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final canIssue =
        tool != null && session.can('tools.issue', siteId: tool.siteId);
    final dates = MaterialLocalizations.of(context);

    Future<void> edit() async {
      final kept = await showFormSheet<bool>(context, ToolForm(tool: tool));
      if (kept == false && context.mounted) context.pop();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/equipment?side=tools'),
        title: Text(tool?.code ?? 'Tool'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: tool == null
            ? const Center(
                child: EmptyState(
                  icon: CupertinoIcons.wrench,
                  title: 'Tool not found',
                  message: 'It may have been removed from the register.',
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  Space.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _hero(tool, me, people, dates).entrance(context),
                          const SizedBox(height: Space.sm),
                          QuickActions(
                            actions: [
                              if (!toolOut(tool))
                                (
                                  icon: CupertinoIcons.arrow_right_circle_fill,
                                  label: 'Lend',
                                  onTap:
                                      canIssue &&
                                          !calibrationExpired(tool) &&
                                          !{
                                            'damaged',
                                            'lost',
                                          }.contains(tool.condition)
                                      ? () => showFormSheet(
                                          context,
                                          _IssueSheet(tool: tool),
                                        )
                                      : null,
                                  color: BrandColors.maroon,
                                )
                              else
                                (
                                  icon: CupertinoIcons.arrow_down_circle_fill,
                                  label: 'Take back',
                                  onTap: canIssue
                                      ? () => showFormSheet(
                                          context,
                                          _ReturnSheet(tool: tool),
                                        )
                                      : null,
                                  color: BrandColors.success,
                                ),
                              (
                                icon: CupertinoIcons.checkmark_square,
                                label: 'Count',
                                onTap: canIssue
                                    ? () => context.push('/tools/count')
                                    : null,
                                color: BrandColors.info,
                              ),
                              (
                                icon: CupertinoIcons.pencil,
                                label: 'Edit',
                                onTap: canIssue ? edit : null,
                                color: null,
                              ),
                            ],
                          ).entrance(context, index: 1),
                          const SizedBox(height: Space.md),
                          GlassSegmented<_Tab>(
                            value: _tab,
                            segments: const {
                              _Tab.history: 'Who had it',
                              _Tab.jobs: 'Jobs',
                              _Tab.details: 'Details',
                            },
                            onChanged: (t) => setState(() => _tab = t),
                          ),
                          const SizedBox(height: Space.md),
                          if (_tab == _Tab.history)
                            _history(context, people, dates, theme)
                          else if (_tab == _Tab.jobs)
                            _jobs(context, theme)
                          else
                            RecordDetails(
                              rows: [
                                ('Code', tool.code),
                                ('Name', tool.name),
                                ('Kind', tool.kind),
                                ('Serial number', tool.serialNo),
                                (
                                  'Condition',
                                  ToolCondition.parse(tool.condition).label,
                                ),
                                (
                                  'Calibration due',
                                  tool.calibrationDue == null
                                      ? null
                                      : dates.formatMediumDate(
                                          tool.calibrationDue!,
                                        ),
                                ),
                                (
                                  'Last counted',
                                  tool.lastCountedAt == null
                                      ? null
                                      : dates.formatMediumDate(
                                          tool.lastCountedAt!,
                                        ),
                                ),
                                ('Notes', tool.notes),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _hero(
    LocalTool tool,
    String? me,
    Map<String, String> people,
    MaterialLocalizations dates,
  ) {
    final condition = ToolCondition.parse(tool.condition);
    final overdue = toolOverdue(tool);
    final holder = tool.holderId != null && tool.holderId == me
        ? 'you'
        : toolHolder(tool, people);
    final formId = tool.formId;
    return RecordHero(
      icon: CupertinoIcons.wrench_fill,
      code: tool.code,
      title: tool.name,
      pills: [
        Pill(
          label: condition.label,
          color: conditionColor(condition),
          dense: true,
        ),
        if (tool.kind != null) Pill(label: tool.kind!, dense: true),
        if (formId != null)
          GestureDetector(
            onTap: () => context.push('/tools/forms/$formId'),
            child: const Pill(
              label: 'On an issue form',
              icon: CupertinoIcons.doc_text,
              dense: true,
            ),
          ),
        if (tool.pending)
          const Pill(
            label: 'Waiting to sync',
            icon: CupertinoIcons.cloud_upload,
            dense: true,
          ),
      ],
      facts: [
        (
          icon: !toolOut(tool)
              ? CupertinoIcons.cube_box
              : CupertinoIcons.person_fill,
          text: !toolOut(tool)
              ? 'In store'
              : 'With ${holder ?? 'someone'} since '
                    '${relativeTime(tool.issuedAt ?? DateTime.now())}',
          color: null,
        ),
        if (tool.dueBack != null)
          (
            icon: CupertinoIcons.calendar,
            text: overdue
                ? 'Overdue: was due back ${dates.formatMediumDate(tool.dueBack!)}'
                : 'Due back ${dates.formatMediumDate(tool.dueBack!)}',
            color: overdue ? Colors.red : null,
          ),
        if (tool.calibrationDue != null)
          (
            icon: CupertinoIcons.gauge,
            text: calibrationExpired(tool)
                ? 'Calibration expired '
                      '${dates.formatMediumDate(tool.calibrationDue!)}: '
                      'it cannot go out'
                : 'Calibration due '
                      '${dates.formatMediumDate(tool.calibrationDue!)}',
            color: calibrationExpired(tool)
                ? Colors.red
                : calibrationDue(tool)
                ? Colors.orange
                : null,
          ),
      ],
    );
  }

  Widget _history(
    BuildContext context,
    Map<String, String> people,
    MaterialLocalizations dates,
    ThemeData theme,
  ) {
    return ref
        .watch(toolHistoryProvider(widget.id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            AppError.from(e).isRetryable
                ? 'History loads when you are online.'
                : AppError.from(e).message,
            style: theme.textTheme.bodySmall,
          ),
          data: (rows) => rows.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.person_2,
                  title: 'Never lent yet',
                  message:
                      'Each time it goes out shows here, with the '
                      'signature.',
                )
              : SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          onTap: r.formId == null
                              ? null
                              : () => context.push('/tools/forms/${r.formId}'),
                          leading: AppAvatar(
                            name: people[r.issuedTo] ?? r.recipientName ?? '?',
                            size: 36,
                          ),
                          title: Text(
                            [
                              people[r.issuedTo] ??
                                  r.recipientName ??
                                  'Someone',
                              ?r.company,
                            ].join(' · '),
                          ),
                          subtitle: Text(
                            [
                              ?r.formCode,
                              'Out ${dates.formatShortMonthDay(r.issuedAt)}',
                              if (r.returnedAt != null)
                                'back ${dates.formatShortMonthDay(r.returnedAt!)} · ${ToolCondition.parse(r.returnCondition ?? 'good').label.toLowerCase()}'
                              else
                                'still out',
                              ?r.returnNote,
                            ].join(' · '),
                          ),
                          trailing: r.signaturePath == null
                              ? null
                              : IconButton(
                                  tooltip: 'See signature',
                                  icon: const Icon(CupertinoIcons.signature),
                                  onPressed: () =>
                                      _showSignature(context, r.signaturePath!),
                                ),
                        ),
                    ],
                  ),
                ),
        );
  }

  Widget _jobs(BuildContext context, ThemeData theme) {
    return ref
        .watch(toolJobCardsProvider(widget.id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            AppError.from(e).isRetryable
                ? 'Jobs load when you are online.'
                : AppError.from(e).message,
            style: theme.textTheme.bodySmall,
          ),
          data: (rows) => rows.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.hammer,
                  title: 'Not on any job card yet',
                  message:
                      'Add it under Tools on a job card, or issue it on a '
                      'form for a job card.',
                )
              : SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    children: [
                      for (final j in rows)
                        ListTile(
                          leading: const Icon(CupertinoIcons.hammer),
                          title: Text('${j.number} · ${j.title}'),
                          subtitle: Text(j.status.replaceAll('_', ' ')),
                          trailing: const Icon(CupertinoIcons.chevron_right),
                          onTap: () => context.push('/jobs/${j.number}'),
                        ),
                    ],
                  ),
                ),
        );
  }

  void _showSignature(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Consumer(
            builder: (context, ref, _) => ref
                .watch(toolFileUrlProvider(path))
                .when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const Text('Signature loads when online.'),
                  data: (url) => Image.network(url),
                ),
          ),
        ),
      ),
    );
  }
}

class _IssueSheet extends ConsumerStatefulWidget {
  const _IssueSheet({required this.tool});

  final LocalTool tool;

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  final _signature = SignatureController();
  String? _to;
  DateTime? _dueBack;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  Future<void> _issue() async {
    if (_to == null) {
      setState(() => _error = 'Pick who is taking it');
      return;
    }
    final png = await _signature.toPng();
    if (png == null) {
      setState(() => _error = 'Ask them to sign');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref
        .read(toolActionsProvider)
        .issue(widget.tool, userId: _to!, dueBack: _dueBack, signature: png);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = ref.watch(toolPeopleProvider(widget.tool.siteId));
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
          Text(
            'Issue ${widget.tool.code ?? widget.tool.name}',
            style: theme.textTheme.headlineSmall,
          ),
          label('Who is taking it?'),
          people.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Connect to pick someone.'),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _to,
              isExpanded: true,
              hint: const Text('Pick a person'),
              items: [
                for (final p in list)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name.isEmpty ? 'Unnamed' : p.name),
                  ),
              ],
              onChanged: (v) => setState(() {
                _to = v;
                _error = null;
              }),
            ),
          ),
          label('Back by (optional)'),
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.calendar),
            label: Text(
              _dueBack == null
                  ? 'No return date'
                  : MaterialLocalizations.of(context)
                        .formatMediumDate(_dueBack!),
            ),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _dueBack ?? now.add(const Duration(days: 1)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 180)),
              );
              if (d != null) setState(() => _dueBack = d);
            },
          ),
          label('Signature of the person taking it'),
          SignaturePad(controller: _signature),
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
            onPressed: _busy ? null : _issue,
            icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
            label: const Text('Issue tool'),
          ),
        ],
      ),
    );
  }
}

class _ReturnSheet extends ConsumerStatefulWidget {
  const _ReturnSheet({required this.tool});

  final LocalTool tool;

  @override
  ConsumerState<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<_ReturnSheet> {
  final _note = TextEditingController();
  ToolCondition _condition = ToolCondition.good;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _return() async {
    if (_condition != ToolCondition.good && _note.text.trim().isEmpty) {
      setState(() => _error = 'Say what is wrong with it');
      return;
    }
    HapticFeedback.mediumImpact();
    await ref
        .read(toolActionsProvider)
        .takeBack(widget.tool, condition: _condition, note: _note.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text(
            'Take back ${widget.tool.code ?? widget.tool.name}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          Text('Condition', style: theme.textTheme.labelLarge),
          const SizedBox(height: Space.xs),
          ConditionPicker(
            value: _condition,
            onChanged: (c) => setState(() {
              _condition = c;
              _error = null;
            }),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _condition == ToolCondition.good
                  ? 'Note (optional)'
                  : 'What is wrong with it?',
            ),
          ),
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
            style: FilledButton.styleFrom(backgroundColor: BrandColors.success),
            onPressed: _return,
            icon: const Icon(CupertinoIcons.arrow_down_circle_fill),
            label: const Text('Take back'),
          ),
        ],
      ),
    );
  }
}
