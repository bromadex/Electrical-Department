import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../data/site_data.dart';
import '../ui/media.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../assets/assets_screen.dart' show CardColumns;
import 'tools_repository.dart';
import '../widgets/app_back_button.dart';

/// Narrows the tools side of the Equipment & tools page.
enum ToolFilter { all, store, out, mine, overdue, calibration, attention }

const toolFilterLabels = {
  ToolFilter.all: 'All',
  ToolFilter.store: 'In store',
  ToolFilter.out: 'Out',
  ToolFilter.mine: 'With me',
  ToolFilter.overdue: 'Overdue back',
  ToolFilter.calibration: 'Calibration due',
  ToolFilter.attention: 'Needs attention',
};

bool toolMatches(LocalTool t, String q, Map<String, String> people) =>
    q.isEmpty ||
    t.name.toLowerCase().contains(q) ||
    (t.code?.toLowerCase().contains(q) ?? false) ||
    (t.kind?.toLowerCase().contains(q) ?? false) ||
    (t.serialNo?.toLowerCase().contains(q) ?? false) ||
    (toolHolder(t, people)?.toLowerCase().contains(q) ?? false);

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

/// The tools register at the current site, as cards. The Equipment &
/// tools page supplies search and filter.
class ToolList extends ConsumerWidget {
  const ToolList({super.key, this.query = '', this.filter = ToolFilter.all});

  final String query;
  final ToolFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(siteToolsProvider).value ?? const [];
    final people = ref.watch(peopleProvider).value ?? const {};
    final me = ref.watch(authUserIdProvider);
    final session = ref.watch(sessionProvider);
    final site = ref.watch(currentSiteProvider);
    final canIssue =
        site != null && session.can('tools.issue', siteId: site.id);
    final q = query.trim().toLowerCase();
    final shown = [
      for (final t in tools)
        if (switch (filter) {
              ToolFilter.all => true,
              ToolFilter.store => !toolOut(t),
              ToolFilter.out => toolOut(t),
              ToolFilter.mine => t.holderId == me,
              ToolFilter.overdue => toolOverdue(t),
              ToolFilter.calibration => calibrationDue(t),
              ToolFilter.attention =>
                toolOverdue(t) ||
                    calibrationDue(t) ||
                    t.condition != ToolCondition.good.value,
            } &&
            toolMatches(t, q, people))
          t,
    ];
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: Center(
          child: EmptyState(
            icon: CupertinoIcons.wrench,
            title: tools.isEmpty ? 'No tools yet' : 'Nothing here',
            message: tools.isEmpty
                ? (canIssue
                      ? 'Add meggers, multimeters and other tools to know '
                            'who holds what.'
                      : 'The store adds tools here.')
                : 'No tools match.',
          ),
        ),
      );
    }
    return CardColumns(
      children: [
        for (final (i, t) in shown.indexed)
          ToolTile(
            tool: t,
            holderName: toolHolder(t, people),
            isMine: t.holderId == me,
          ).entrance(context, index: i.clamp(0, 8)),
      ],
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
    final where = !toolOut(tool)
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
    if (archive && widget.tool != null && toolOut(widget.tool!)) {
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
          if (widget.tool != null && !toolOut(widget.tool!)) ...[
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
        leading: const AppBackButton(),
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
                              !toolOut(t)
                                  ? 'In store'
                                  : 'With ${toolHolder(t, people) ?? 'someone'}',
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
