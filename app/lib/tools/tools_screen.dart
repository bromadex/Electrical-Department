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
import 'issue_forms_repository.dart';
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
    // Tools out are grouped under the person who has them (one header
    // instead of "With …" on every card); the rest follow as "In store".
    final grouped = filter == ToolFilter.all || filter == ToolFilter.out;
    if (!grouped) {
      return CardColumns(
        children: [
          for (final (i, t) in shown.indexed)
            ToolTile(
              tool: t,
              holderName: toolHolder(t, people),
              isMine: t.holderId != null && t.holderId == me,
            ).entrance(context, index: i.clamp(0, 8)),
        ],
      );
    }
    final forms = {
      for (final f
          in ref.watch(issueFormsProvider).value ?? const <IssueForm>[])
        f.id: f,
    };
    final groups = <String, List<LocalTool>>{};
    final inStore = <LocalTool>[];
    for (final t in shown) {
      if (!toolOut(t)) {
        inStore.add(t);
        continue;
      }
      final key = t.holderId ?? 'name:${toolHolder(t, people) ?? ''}';
      groups.putIfAbsent(key, () => []).add(t);
    }
    final ordered = groups.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var i = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in ordered) ...[
          _HolderHeader(
            name: g.first.holderId != null && g.first.holderId == me
                ? 'You'
                : toolHolder(g.first, people) ?? 'Someone',
            tools: g,
            form: forms[g.first.formId],
          ).entrance(context, index: (i++).clamp(0, 8)),
          const SizedBox(height: Space.sm),
          CardColumns(
            children: [
              for (final t in g)
                ToolTile(
                  tool: t,
                  showHolder: false,
                ).entrance(context, index: (i++).clamp(0, 8)),
            ],
          ),
          const SizedBox(height: Space.lg),
        ],
        if (inStore.isNotEmpty) ...[
          if (ordered.isNotEmpty)
            _SectionLabel(
              icon: CupertinoIcons.cube_box_fill,
              color: BrandColors.success,
              text: 'In store · ${inStore.length}',
            ),
          CardColumns(
            children: [
              for (final t in inStore)
                ToolTile(tool: t).entrance(context, index: (i++).clamp(0, 8)),
            ],
          ),
        ],
      ],
    );
  }
}

/// What a tool looks like in lists: an icon and colour by what it is.
({IconData icon, Color color}) toolLook(LocalTool t) {
  final k = '${t.name} ${t.kind ?? ''}'.toLowerCase();
  bool has(List<String> words) => words.any(k.contains);
  if (has(['meter', 'megger', 'tester', 'clamp', 'detector', 'gauge'])) {
    return (icon: Icons.speed_rounded, color: BrandColors.info);
  }
  if (has(['toolbox', 'tool box', 'bag', 'case'])) {
    return (icon: Icons.home_repair_service_rounded, color: BrandColors.maroon);
  }
  if (has(['padlock', 'lock', 'loto', 'hasp'])) {
    return (icon: Icons.lock_rounded, color: const Color(0xFFC0392B));
  }
  if (has(['hammer', 'mallet'])) {
    return (icon: Icons.hardware_rounded, color: const Color(0xFF8D5A3B));
  }
  if (has(['saw', 'blade'])) {
    return (icon: Icons.carpenter_rounded, color: const Color(0xFFD9572B));
  }
  if (has(['tape', 'measure', 'ruler', 'level'])) {
    return (icon: Icons.straighten_rounded, color: const Color(0xFF0F9D9A));
  }
  if (has(['crimp', 'stripper', 'cutter', 'plier', 'snip'])) {
    return (icon: Icons.content_cut_rounded, color: BrandColors.warning);
  }
  if (has(['screwdriver', 'bits', 'hex', 'allen', 'spanner', 'wrench'])) {
    return (icon: Icons.handyman_rounded, color: const Color(0xFF7B4FD6));
  }
  if (has(['drill', 'grinder', 'driver'])) {
    return (icon: Icons.construction_rounded, color: BrandColors.coral);
  }
  if (has(['ladder'])) {
    return (icon: Icons.stairs_rounded, color: const Color(0xFF5B6B7F));
  }
  return (icon: CupertinoIcons.wrench_fill, color: BrandColors.maroon);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, Space.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.xs),
          Text(
            text,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The person holding a group of tools: avatar, company, form, how many
/// and since when, with a bar showing how many are overdue.
class _HolderHeader extends StatelessWidget {
  const _HolderHeader({
    required this.name,
    required this.tools,
    required this.form,
  });

  final String name;
  final List<LocalTool> tools;
  final IssueForm? form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = tools.where(toolOverdue).length;
    final since = tools
        .map((t) => t.issuedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final dates = MaterialLocalizations.of(context);
    final f = form;
    return SurfaceCard(
      onTap: f == null ? null : () => context.push('/tools/forms/${f.id}'),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          (overdue > 0 ? Colors.red : BrandColors.info).withValues(alpha: 0.16),
          BrandColors.blush.withValues(alpha: 0.10),
        ],
      ),
      child: Row(
        children: [
          AppAvatar(name: name, size: 52),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    ?f?.recipientRole,
                    ?f?.company,
                    if (since != null) 'since ${dates.formatMediumDate(since)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (f != null) ...[
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.xs,
                    children: [
                      Pill(
                        label: f.code,
                        icon: CupertinoIcons.doc_text,
                        dense: true,
                      ),
                      if (f.teamLead != null)
                        Pill(
                          label: 'Lead: ${f.teamLead}',
                          icon: CupertinoIcons.person_2,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${tools.length}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: overdue > 0 ? Colors.red : BrandColors.info,
                ),
              ),
              Text(
                overdue > 0
                    ? '$overdue overdue'
                    : tools.length == 1
                    ? 'tool'
                    : 'tools',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overdue > 0 ? Colors.red : null,
                ),
              ),
            ],
          ),
          if (f != null) ...[
            const SizedBox(width: Space.xs),
            const Icon(CupertinoIcons.chevron_right, size: 18),
          ],
        ],
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
    this.showHolder = true,
  });

  final LocalTool tool;
  final String? holderName;
  final bool isMine;

  /// False under a holder's group header, which already says who.
  final bool showHolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final condition = ToolCondition.parse(tool.condition);
    final overdue = toolOverdue(tool);
    final out = toolOut(tool);
    final look = toolLook(tool);
    final dates = MaterialLocalizations.of(context);
    final status =
        returnStatus(tool) ??
        (calibrationExpired(tool)
            ? (label: 'Calibration hold', color: Colors.blueGrey)
            : (label: 'In store', color: BrandColors.success));
    final detail = [
      if (out && showHolder) isMine ? 'With you' : holderName ?? 'Out',
      if (out && tool.dueBack != null)
        'due ${dates.formatShortMonthDay(tool.dueBack!)}'
      else if (out && !showHolder && tool.issuedAt != null)
        'since ${dates.formatShortMonthDay(tool.issuedAt!)}',
      if (tool.serialNo != null) 'S/N ${tool.serialNo}',
    ].join(' · ');
    return SurfaceCard(
      onTap: () => context.push('/tools/${tool.id}'),
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  look.color.withValues(alpha: 0.24),
                  look.color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: look.color.withValues(alpha: 0.25)),
            ),
            child: Icon(look.icon, color: look.color, size: 28),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (tool.code != null)
                      RecordCode(tool.code!)
                    else
                      const Pill(label: 'New', dense: true),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: overdue
                                ? Colors.red
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Pill(label: status.label, color: status.color, dense: true),
              if (condition != ToolCondition.good) ...[
                const SizedBox(height: 4),
                Pill(
                  label: condition.label,
                  color: conditionColor(condition),
                  dense: true,
                ),
              ] else if (calibrationDue(tool)) ...[
                const SizedBox(height: 4),
                const Pill(
                  label: 'Calibrate',
                  color: Colors.orange,
                  icon: CupertinoIcons.gauge,
                  dense: true,
                ),
              ],
            ],
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

int _daysFrom(DateTime d) {
  final n = DateTime.now();
  return DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
}

/// "Due today", "3 days late" or "On time" for a tool that is out.
({String label, Color color})? returnStatus(LocalTool t) {
  if (!toolOut(t)) return null;
  final due = t.dueBack;
  if (due == null) return (label: 'Out', color: BrandColors.info);
  final late = _daysFrom(due);
  if (late > 0) {
    return (
      label: '$late ${late == 1 ? 'day' : 'days'} late',
      color: Colors.red,
    );
  }
  if (late == 0) return (label: 'Due today', color: BrandColors.warning);
  return (label: 'On time', color: BrandColors.success);
}

bool _underRepair(LocalTool t) =>
    !toolOut(t) && (t.condition == 'damaged' || t.condition == 'needs_repair');

bool _calibrationHold(LocalTool t) =>
    !toolOut(t) && !_underRepair(t) && calibrationExpired(t);

/// Tool availability at a glance: how many are in the store and ready, a
/// bar of in store · out · under repair · calibration hold, and the numbers
/// that need action. Tapping a part filters the list.
class ToolOverview extends StatelessWidget {
  const ToolOverview({
    super.key,
    required this.tools,
    required this.current,
    required this.onFilter,
  });

  final List<LocalTool> tools;
  final ToolFilter current;
  final ValueChanged<ToolFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = tools.where((t) => t.condition != 'lost').length;
    final out = tools.where(toolOut).length;
    final repair = tools.where(_underRepair).length;
    final hold = tools.where(_calibrationHold).length;
    final ready = tools
        .where(
          (t) =>
              !toolOut(t) &&
              !_underRepair(t) &&
              !_calibrationHold(t) &&
              t.condition != 'lost',
        )
        .length;
    final overdue = tools.where(toolOverdue).length;
    final calibration = tools.where(calibrationDue).length;
    final lost = tools.where((t) => t.condition == 'lost').length;
    final parts = [
      (
        label: 'In store',
        n: ready,
        color: BrandColors.success,
        filter: ToolFilter.store,
      ),
      (label: 'Out', n: out, color: BrandColors.info, filter: ToolFilter.out),
      (
        label: 'Under repair',
        n: repair,
        color: BrandColors.warning,
        filter: ToolFilter.attention,
      ),
      (
        label: 'Calibration hold',
        n: hold,
        color: Colors.blueGrey,
        filter: ToolFilter.calibration,
      ),
    ];

    Widget number(
      String label,
      int n,
      Color color,
      ToolFilter f, {
      bool compact = false,
    }) => Pressable(
      onTap: () => onFilter(f),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          color: current == f ? color.withValues(alpha: 0.12) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? theme.textTheme.labelSmall
                  : theme.textTheme.labelMedium,
            ),
            Text(
              '$n',
              style:
                  (compact
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.headlineMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: n > 0
                            ? color
                            : theme.colorScheme.onSurfaceVariant,
                      ),
            ),
          ],
        ),
      ),
    );

    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tool availability', style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: Space.sm,
          children: [
            Text(
              '$ready',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'of $total ${total == 1 ? 'tool is' : 'tools are'} in the '
                'store, ready to go out',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final damaged = tools.where((t) => t.condition == 'damaged').length + lost;
    Widget numbers({bool compact = false}) {
      final items = [
        number(
          compact ? 'Overdue' : 'Overdue returns',
          overdue,
          Colors.red,
          ToolFilter.overdue,
          compact: compact,
        ),
        number(
          compact ? 'Calibration' : 'Calibration due',
          calibration,
          BrandColors.warning,
          ToolFilter.calibration,
          compact: compact,
        ),
        number(
          compact ? 'Damaged/lost' : 'Damaged or lost',
          damaged,
          Colors.blueGrey,
          ToolFilter.attention,
          compact: compact,
        ),
      ];
      return compact
          ? Row(children: [for (final i in items) Expanded(child: i)])
          : Row(mainAxisSize: MainAxisSize.min, children: items);
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 720
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: headline),
                      numbers(),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      headline,
                      const SizedBox(height: Space.sm),
                      numbers(compact: true),
                    ],
                  ),
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: SizedBox(
              height: 14,
              child: total == 0
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : Row(
                      children: [
                        for (final p in parts)
                          if (p.n > 0)
                            Expanded(
                              flex: p.n,
                              child: Container(
                                margin: const EdgeInsets.only(right: 2),
                                color: p.color,
                              ),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              for (final p in parts)
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  onTap: () => onFilter(p.filter),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${p.label} ${p.n}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: current == p.filter
                                ? FontWeight.w800
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What needs chasing: overdue returns (who, what, how late) and
/// calibration (expired tools are blocked; due within 30 days).
class ToolAlerts extends StatelessWidget {
  const ToolAlerts({super.key, required this.tools, required this.people});

  final List<LocalTool> tools;
  final Map<String, String> people;

  static bool hasAny(List<LocalTool> tools) => tools.any(
    (t) =>
        toolOverdue(t) ||
        (t.calibrationDue != null && _daysFrom(t.calibrationDue!) >= -30),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = tools.where(toolOverdue).toList()
      ..sort((a, b) => a.dueBack!.compareTo(b.dueBack!));
    final calibration =
        tools
            .where(
              (t) =>
                  t.calibrationDue != null &&
                  t.condition != 'lost' &&
                  _daysFrom(t.calibrationDue!) >= -30,
            )
            .toList()
          ..sort((a, b) => a.calibrationDue!.compareTo(b.calibrationDue!));

    Widget panel(String title, IconData icon, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Panel(
        title: title,
        icon: icon,
        child: Column(children: rows),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overdue.isNotEmpty)
          panel('Overdue returns', CupertinoIcons.clock, [
            for (final t in overdue.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () => context.push('/tools/${t.id}'),
                leading: AppAvatar(
                  name: toolHolder(t, people) ?? '?',
                  size: 34,
                ),
                title: Text(
                  toolHolder(t, people) ?? 'Someone',
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  '${t.code ?? ''} ${t.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  returnStatus(t)!.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (overdue.length > 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push('/tools/holders'),
                  child: Text('All ${overdue.length} in Who has what'),
                ),
              ),
          ]),
        if (calibration.isNotEmpty)
          panel('Calibration', CupertinoIcons.gauge, [
            for (final t in calibration.take(6))
              Builder(
                builder: (context) {
                  final left = -_daysFrom(t.calibrationDue!);
                  final blocked = left < 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => context.push('/tools/${t.id}'),
                    title: Text(
                      '${t.code ?? ''} ${t.name}',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${blocked ? 'Expired' : 'Due'} '
                      '${dayWithYear(t.calibrationDue!)}',
                    ),
                    trailing: Pill(
                      label: blocked
                          ? 'Blocked'
                          : left == 0
                          ? 'Today'
                          : '$left ${left == 1 ? 'day' : 'days'}',
                      color: blocked
                          ? Colors.red
                          : left <= 7
                          ? BrandColors.warning
                          : Colors.blueGrey,
                      dense: true,
                    ),
                  );
                },
              ),
          ]),
      ],
    );
  }
}
