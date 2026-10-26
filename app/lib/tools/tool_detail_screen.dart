import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../ui/signature_pad.dart';
import '../ui/surfaces.dart';
import 'tools_repository.dart';
import 'tools_screen.dart';
import '../widgets/app_back_button.dart';

/// One tool: where it is, its condition and calibration, and who had it.
class ToolDetailScreen extends ConsumerWidget {
  const ToolDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider(id)).value;
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final canIssue =
        tool != null && session.can('tools.issue', siteId: tool.siteId);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(tool?.code ?? 'Tool'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canIssue)
            IconButton(
              tooltip: 'Edit tool',
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () async {
                final kept = await showFormSheet<bool>(
                  context,
                  ToolForm(tool: tool),
                );
                if (kept == false && context.mounted) context.pop();
              },
            ),
        ],
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
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(
                            tool: tool,
                            holder: tool.holderId == me
                                ? 'you'
                                : people[tool.holderId],
                          ).entrance(context),
                          if (canIssue) ...[
                            const SizedBox(height: Space.md),
                            if (tool.holderId == null)
                              FilledButton.icon(
                                onPressed:
                                    {'damaged', 'lost'}.contains(tool.condition)
                                    ? null
                                    : () => showFormSheet(
                                        context,
                                        _IssueSheet(tool: tool),
                                      ),
                                icon: const Icon(
                                  CupertinoIcons.arrow_right_circle_fill,
                                ),
                                label: const Text('Issue to someone'),
                              )
                            else
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: BrandColors.success,
                                ),
                                onPressed: () => showFormSheet(
                                  context,
                                  _ReturnSheet(tool: tool),
                                ),
                                icon: const Icon(
                                  CupertinoIcons.arrow_down_circle_fill,
                                ),
                                label: const Text('Take back'),
                              ),
                          ],
                          const SectionHeader('History'),
                          ref
                              .watch(toolHistoryProvider(id))
                              .when(
                                loading: () => const LinearProgressIndicator(),
                                error: (e, _) => Text(
                                  AppError.from(e).isRetryable
                                      ? 'History loads when you are online.'
                                      : AppError.from(e).message,
                                  style: theme.textTheme.bodySmall,
                                ),
                                data: (rows) => rows.isEmpty
                                    ? Text(
                                        'Never issued yet.',
                                        style: theme.textTheme.bodySmall,
                                      )
                                    : SurfaceCard(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Space.xs,
                                        ),
                                        child: Column(
                                          children: [
                                            for (final r in rows)
                                              ListTile(
                                                leading: AppAvatar(
                                                  name:
                                                      people[r.issuedTo] ?? '?',
                                                  size: 36,
                                                ),
                                                title: Text(
                                                  people[r.issuedTo] ??
                                                      'Someone',
                                                ),
                                                subtitle: Text(
                                                  [
                                                    'Out ${dates.formatShortMonthDay(r.issuedAt)}',
                                                    if (r.returnedAt != null)
                                                      'back ${dates.formatShortMonthDay(r.returnedAt!)} · ${ToolCondition.parse(r.returnCondition ?? 'good').label.toLowerCase()}'
                                                    else
                                                      'still out',
                                                    ?r.returnNote,
                                                  ].join(' · '),
                                                ),
                                                trailing:
                                                    r.signaturePath == null
                                                    ? null
                                                    : IconButton(
                                                        tooltip:
                                                            'See signature',
                                                        icon: const Icon(
                                                          CupertinoIcons
                                                              .signature,
                                                        ),
                                                        onPressed: () =>
                                                            _showSignature(
                                                              context,
                                                              r.signaturePath!,
                                                            ),
                                                      ),
                                              ),
                                          ],
                                        ),
                                      ),
                              ),
                          if (tool.notes != null) ...[
                            const SectionHeader('Notes'),
                            Text(
                              tool.notes!,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
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

class _Header extends StatelessWidget {
  const _Header({required this.tool, required this.holder});

  final LocalTool tool;
  final String? holder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final condition = ToolCondition.parse(tool.condition);
    final dates = MaterialLocalizations.of(context);
    final overdue = toolOverdue(tool);
    Widget fact(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color ?? scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              if (tool.code != null) RecordCode(tool.code!),
              Pill(label: condition.label, color: conditionColor(condition)),
              if (tool.kind != null) Pill(label: tool.kind!),
              if (tool.pending)
                const Pill(
                  label: 'Waiting to sync',
                  icon: CupertinoIcons.cloud_upload,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(tool.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          fact(
            tool.holderId == null
                ? CupertinoIcons.cube_box
                : CupertinoIcons.person_fill,
            tool.holderId == null
                ? 'In store'
                : 'With ${holder ?? 'someone'} since ${relativeTime(tool.issuedAt ?? DateTime.now())}',
          ),
          if (tool.dueBack != null)
            fact(
              CupertinoIcons.calendar,
              overdue
                  ? 'Overdue: was due back ${dates.formatMediumDate(tool.dueBack!)}'
                  : 'Due back ${dates.formatMediumDate(tool.dueBack!)}',
              color: overdue ? Colors.red : null,
            ),
          if (tool.calibrationDue != null)
            fact(
              CupertinoIcons.gauge,
              'Calibration due ${dates.formatMediumDate(tool.calibrationDue!)}',
              color: calibrationDue(tool) ? Colors.orange : null,
            ),
          if (tool.serialNo != null)
            fact(CupertinoIcons.number, 'Serial ${tool.serialNo}'),
          if (tool.lastCountedAt != null)
            fact(
              CupertinoIcons.checkmark_square,
              'Last counted ${dates.formatMediumDate(tool.lastCountedAt!)}',
            ),
        ],
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
