import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../jobs/job_editor.dart';
import '../jobs/jobs_repository.dart';
import '../jobs/media.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'tools_repository.dart';

enum _Filter { all, store, out, mine, due }

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.store: 'In store',
  _Filter.out: 'Out',
  _Filter.mine: 'Mine',
  _Filter.due: 'Attention',
};

Color conditionColor(ToolCondition c) => switch (c) {
  ToolCondition.good => BrandColors.success,
  ToolCondition.needsRepair => Colors.orange,
  ToolCondition.damaged || ToolCondition.lost => Colors.red,
};

/// Picks a tool's condition; chips wrap on narrow phones.
class ConditionPicker extends StatelessWidget {
  const ConditionPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ToolCondition value;
  final ValueChanged<ToolCondition> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final c in ToolCondition.values)
          ChoiceChip(
            label: Text(c.label),
            selected: value == c,
            selectedColor: conditionColor(c).withValues(alpha: 0.2),
            onSelected: (_) => onChanged(c),
          ),
      ],
    );
  }
}

/// The tools register at the current site.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key, this.mine = false});

  final bool mine;

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  late _Filter _filter = widget.mine ? _Filter.mine : _Filter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tools = ref.watch(siteToolsProvider).value ?? const [];
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canIssue =
        site != null && session.can('tools.issue', siteId: site.id);
    final q = _query.toLowerCase();
    final shown = [
      for (final t in tools)
        if (switch (_filter) {
              _Filter.all => true,
              _Filter.store => t.holderId == null,
              _Filter.out => t.holderId != null,
              _Filter.mine => t.holderId == me,
              _Filter.due =>
                toolOverdue(t) ||
                    calibrationDue(t) ||
                    t.condition != ToolCondition.good.value,
            } &&
            (q.isEmpty ||
                t.name.toLowerCase().contains(q) ||
                (t.code?.toLowerCase().contains(q) ?? false) ||
                (t.serialNo?.toLowerCase().contains(q) ?? false) ||
                (people[t.holderId]?.toLowerCase().contains(q) ?? false)))
          t,
    ];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Tools · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canIssue && tools.isNotEmpty)
            TextButton.icon(
              onPressed: () => context.push('/tools/count'),
              icon: const Icon(CupertinoIcons.checkmark_square),
              label: const Text('Count'),
            ),
        ],
      ),
      floatingActionButton: canIssue
          ? FloatingActionButton.extended(
              onPressed: () => showFormSheet(context, const ToolForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('Add tool'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: ref.read(toolsSyncProvider.notifier).refresh,
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
                      CupertinoSearchTextField(
                        placeholder: 'Search tools, codes or people',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: Space.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in _Filter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: Space.xs),
                                child: ChoiceChip(
                                  label: Text(_filterLabels[f]!),
                                  selected: _filter == f,
                                  onSelected: (_) =>
                                      setState(() => _filter = f),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xl),
                          child: Center(
                            child: EmptyState(
                              icon: CupertinoIcons.wrench,
                              title: tools.isEmpty
                                  ? 'No tools yet'
                                  : 'Nothing here',
                              message: tools.isEmpty
                                  ? (canIssue
                                        ? 'Add meggers, multimeters and other '
                                              'tools to know who holds what.'
                                        : 'The store adds tools here.')
                                  : 'No tools match this filter.',
                            ),
                          ),
                        ),
                      for (final (i, t) in shown.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: ToolTile(
                            tool: t,
                            holderName: people[t.holderId],
                            isMine: t.holderId == me,
                          ),
                        ).entrance(context, index: i.clamp(0, 8)),
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

class ToolTile extends StatelessWidget {
  const ToolTile({
    super.key,
    required this.tool,
    this.holderName,
    this.isMine = false,
  });

  final LocalTool tool;
  final String? holderName;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final condition = ToolCondition.parse(tool.condition);
    final overdue = toolOverdue(tool);
    final where = tool.holderId == null
        ? 'In store'
        : isMine
        ? 'With you'
        : 'With ${holderName ?? 'someone'}';
    return SurfaceCard(
      onTap: () => context.push('/tools/${tool.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(CupertinoIcons.wrench_fill, color: scheme.primary),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (tool.code != null)
                      RecordCode(tool.code!)
                    else
                      const Pill(label: 'New', dense: true),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        tool.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    where,
                    if (tool.dueBack != null)
                      overdue
                          ? 'overdue'
                          : 'back ${MaterialLocalizations.of(context).formatShortMonthDay(tool.dueBack!)}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overdue ? Colors.red : null,
                  ),
                ),
              ],
            ),
          ),
          if (condition != ToolCondition.good)
            Pill(
              label: condition.label,
              color: conditionColor(condition),
              dense: true,
            )
          else if (calibrationDue(tool))
            const Pill(
              label: 'Calibrate',
              color: Colors.orange,
              icon: CupertinoIcons.gauge,
              dense: true,
            ),
          if (tool.pending)
            Padding(
              padding: const EdgeInsets.only(left: Space.xs),
              child: Icon(
                CupertinoIcons.cloud_upload,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Add or edit a tool (store and supervisors).
class ToolForm extends ConsumerStatefulWidget {
  const ToolForm({super.key, this.tool});

  final LocalTool? tool;

  @override
  ConsumerState<ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends ConsumerState<ToolForm> {
  late final _name = TextEditingController(text: widget.tool?.name);
  late final _kind = TextEditingController(text: widget.tool?.kind);
  late final _serial = TextEditingController(text: widget.tool?.serialNo);
  late final _notes = TextEditingController(text: widget.tool?.notes);
  late DateTime? _calibration = widget.tool?.calibrationDue;
  late ToolCondition _condition = ToolCondition.parse(
    widget.tool?.condition ?? 'good',
  );
  List<Uint8List> _photos = [];
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _kind, _serial, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Name the tool');
      return;
    }
    if (archive && widget.tool?.holderId != null) {
      setState(() => _error = 'Take it back before removing it');
      return;
    }
    HapticFeedback.mediumImpact();
    await ref
        .read(toolActionsProvider)
        .save(
          tool: widget.tool,
          siteId: widget.tool?.siteId ?? site.id,
          name: _name.text,
          kind: _kind.text,
          serialNo: _serial.text,
          calibrationDue: _calibration,
          notes: _notes.text,
          condition: _condition,
          archived: archive,
          photo: _photos.firstOrNull,
        );
    if (mounted) Navigator.pop(context, !archive);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            widget.tool == null
                ? 'Add tool'
                : 'Edit ${widget.tool!.code ?? 'tool'}',
            style: theme.textTheme.headlineSmall,
          ),
          label('Name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Megger MIT420 insulation tester',
            ),
          ),
          label('Kind and serial (optional)'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kind,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Tester, drill…'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _serial,
                  decoration: const InputDecoration(hintText: 'Serial no.'),
                ),
              ),
            ],
          ),
          label('Calibration or test due'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.gauge),
                  label: Text(
                    _calibration == null
                        ? 'Not needed'
                        : MaterialLocalizations.of(context)
                              .formatMediumDate(_calibration!),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate:
                          _calibration ?? now.add(const Duration(days: 365)),
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now.add(const Duration(days: 365 * 5)),
                    );
                    if (d != null) setState(() => _calibration = d);
                  },
                ),
              ),
              if (_calibration != null)
                IconButton(
                  tooltip: 'Not needed',
                  icon: const Icon(CupertinoIcons.clear_circled),
                  onPressed: () => setState(() => _calibration = null),
                ),
            ],
          ),
          if (widget.tool != null && widget.tool!.holderId == null) ...[
            label('Condition'),
            ConditionPicker(
              value: _condition,
              onChanged: (c) => setState(() => _condition = c),
            ),
          ],
          label('Photo (optional)'),
          PhotoStrip(
            photos: _photos,
            onChanged: (p) => setState(() => _photos = p.take(1).toList()),
          ),
          label('Notes (optional)'),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
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
            onPressed: _save,
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Save'),
          ),
          if (widget.tool != null) ...[
            const SizedBox(height: Space.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Remove from register'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Monthly count: tick every tool seen on the shelf or with its holder.
class ToolCountScreen extends ConsumerStatefulWidget {
  const ToolCountScreen({super.key});

  @override
  ConsumerState<ToolCountScreen> createState() => _ToolCountScreenState();
}

class _ToolCountScreenState extends ConsumerState<ToolCountScreen> {
  final _seen = <String>{};

  @override
  Widget build(BuildContext context) {
    final tools = (ref.watch(siteToolsProvider).value ?? const [])
        .where((t) => t.condition != ToolCondition.lost.value)
        .toList();
    final people = ref.watch(peopleProvider).value ?? const {};
    final site = ref.watch(currentSiteProvider);
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Tool count'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _seen.isEmpty || site == null
            ? null
            : () async {
                HapticFeedback.mediumImpact();
                await ref
                    .read(toolActionsProvider)
                    .count(site.id, _seen.toList());
                if (!context.mounted) return;
                final missing = tools.length - _seen.length;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      missing == 0
                          ? 'All ${tools.length} tools counted'
                          : '${_seen.length} counted, $missing not seen',
                    ),
                  ),
                );
                context.pop();
              },
        icon: const Icon(CupertinoIcons.checkmark_seal),
        label: Text('Save count (${_seen.length}/${tools.length})'),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(Space.md, top + Space.md, Space.md, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    children: [
                      for (final t in tools)
                        CheckboxListTile.adaptive(
                          value: _seen.contains(t.id),
                          onChanged: (v) => setState(
                            () => v == true
                                ? _seen.add(t.id)
                                : _seen.remove(t.id),
                          ),
                          title: Text('${t.code ?? 'New'} · ${t.name}'),
                          subtitle: Text(
                            [
                              t.holderId == null
                                  ? 'In store'
                                  : 'With ${people[t.holderId] ?? 'someone'}',
                              if (t.lastCountedAt != null)
                                'last counted ${MaterialLocalizations.of(context).formatShortMonthDay(t.lastCountedAt!)}',
                            ].join(' · '),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
