import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/local_db.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/form_sheet.dart';
import '../ui/signature_pad.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'issue_forms_repository.dart';
import 'tools_repository.dart';
import 'tools_screen.dart';

/// A new tool issue form, like the paper one: who is receiving (someone in
/// the app or outside it), the team lead and place, the return date, the
/// tools with quantity and condition, then three signatures.
class IssueFormScreen extends ConsumerStatefulWidget {
  const IssueFormScreen({super.key, this.toolIds = const [], this.jobCardId});

  /// Tools picked before opening (e.g. from a job card).
  final List<String> toolIds;

  /// Issue for this job card; its tools are linked to it.
  final String? jobCardId;

  @override
  ConsumerState<IssueFormScreen> createState() => _IssueFormScreenState();
}

enum _Who { outside, app }

class _Line {
  _Line(this.tool);

  final LocalTool tool;
  int qty = 1;
  ToolCondition condition = ToolCondition.good;
}

class _IssueFormScreenState extends ConsumerState<IssueFormScreen> {
  _Who _who = _Who.outside;
  String? _userId;
  final _name = TextEditingController();
  final _role = TextEditingController(text: 'Electrician');
  final _company = TextEditingController();
  final _lead = TextEditingController();
  final _location = TextEditingController();
  final _remarks = TextEditingController();
  DateTime? _dueBack;
  final _lines = <_Line>[];
  final _issuer = SignatureController();
  final _recipient = SignatureController();
  final _leadSig = SignatureController();
  String? _error;
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in [_name, _role, _company, _lead, _location, _remarks]) {
      c.dispose();
    }
    _issuer.dispose();
    _recipient.dispose();
    _leadSig.dispose();
    super.dispose();
  }

  void _seed(List<LocalTool> tools) {
    if (_seeded || tools.isEmpty) return;
    _seeded = true;
    for (final id in widget.toolIds) {
      final t = tools.where((t) => t.id == id).firstOrNull;
      if (t != null && issuable(t) == null) _lines.add(_Line(t));
    }
  }

  Future<void> _pickTools(List<LocalTool> tools) async {
    final picked = await showFormSheet<List<LocalTool>>(
      context,
      ToolPickerSheet(
        tools: tools,
        already: {for (final l in _lines) l.tool.id},
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      for (final t in picked) {
        _lines.add(_Line(t));
      }
      _error = null;
    });
  }

  Future<void> _newTool() async {
    final id = await showFormSheet<String>(context, const _QuickToolSheet());
    if (id == null || !mounted) return;
    final db = ref.read(localDbProvider);
    final t = await (db.select(
      db.localTools,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (t != null && mounted) setState(() => _lines.add(_Line(t)));
  }

  Future<void> _submit() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    String? fail;
    if (_who == _Who.app && _userId == null) {
      fail = 'Pick who is receiving the tools';
    } else if (_who == _Who.outside && _name.text.trim().length < 2) {
      fail = 'Write the name of the person receiving the tools';
    } else if (_lines.isEmpty) {
      fail = 'Add the tools going out';
    } else if (_issuer.isEmpty) {
      fail = 'Sign as the person issuing';
    } else if (_recipient.isEmpty) {
      fail = 'Ask the person receiving to sign';
    }
    if (fail != null) {
      setState(() => _error = fail);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    final people = ref.read(toolPeopleProvider(site.id)).value ?? const [];
    final name = _who == _Who.app
        ? people.where((p) => p.id == _userId).firstOrNull?.name ?? ''
        : _name.text;
    final id = await ref
        .read(issueFormActionsProvider)
        .issue(
          siteId: site.id,
          lines: [
            for (final l in _lines)
              (tool: l.tool, qty: l.qty, condition: l.condition),
          ],
          userId: _who == _Who.app ? _userId : null,
          name: name,
          role: _who == _Who.outside ? _role.text : null,
          company: _who == _Who.outside ? _company.text : null,
          teamLead: _lead.text,
          location: _location.text,
          jobCardId: widget.jobCardId,
          dueBack: _dueBack,
          remarks: _remarks.text,
          signatures: (
            issuer: await _issuer.toPng(),
            recipient: await _recipient.toPng(),
            lead: _leadSig.isEmpty ? null : await _leadSig.toPng(),
          ),
        );
    if (!mounted) return;
    context.pushReplacement('/tools/forms/$id');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final tools = ref.watch(siteToolsProvider).value ?? const <LocalTool>[];
    _seed(tools);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    final canIssue =
        site != null && session.can('tools.issue', siteId: site.id);

    Widget field(
      TextEditingController c,
      String label, {
      String? hint,
      TextCapitalization caps = TextCapitalization.words,
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: TextField(
        controller: c,
        textCapitalization: caps,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 4,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: (_) => setState(() => _error = null),
      ),
    );

    Widget sign(String title, String? who, SignatureController c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
          child: Text(
            who == null || who.trim().isEmpty
                ? title
                : '$title · ${who.trim()}',
            style: theme.textTheme.labelLarge,
          ),
        ),
        SignaturePad(controller: c, height: 140),
      ],
    );

    final people = site == null ? null : ref.watch(toolPeopleProvider(site.id));
    final receiver = _who == _Who.app
        ? people?.value?.where((p) => p.id == _userId).firstOrNull?.name
        : _name.text;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/tools/forms'),
        title: const Text('Tool issue form'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: !canIssue
            ? const Center(
                child: EmptyState(
                  icon: CupertinoIcons.lock,
                  title: 'Store only',
                  message: 'The store or a supervisor issues tools.',
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
                          Text(
                            '${site.name} · ${dates.formatMediumDate(DateTime.now())}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SectionHeader('Issued to'),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GlassSegmented<_Who>(
                                  value: _who,
                                  segments: const {
                                    _Who.outside: 'Someone else',
                                    _Who.app: 'Uses the app',
                                  },
                                  onChanged: (w) => setState(() {
                                    _who = w;
                                    _error = null;
                                  }),
                                ),
                                const SizedBox(height: Space.md),
                                if (_who == _Who.app)
                                  people!.when(
                                    loading: () =>
                                        const LinearProgressIndicator(),
                                    error: (_, _) => const Text(
                                      'Connect to pick someone, or use '
                                      '"Someone else".',
                                    ),
                                    data: (list) =>
                                        DropdownButtonFormField<String>(
                                          initialValue: _userId,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Person',
                                          ),
                                          items: [
                                            for (final p in list)
                                              DropdownMenuItem(
                                                value: p.id,
                                                child: Text(
                                                  p.name.isEmpty
                                                      ? 'Unnamed'
                                                      : p.name,
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) => setState(() {
                                            _userId = v;
                                            _error = null;
                                          }),
                                        ),
                                  )
                                else ...[
                                  field(_name, 'Name'),
                                  field(
                                    _role,
                                    'Trade',
                                    hint: 'Electrician, fitter…',
                                  ),
                                  field(
                                    _company,
                                    'Company',
                                    hint: 'e.g. Manhattan',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SectionHeader('Job'),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                field(_lead, 'Project team lead'),
                                field(_location, 'Site or location'),
                                OutlinedButton.icon(
                                  icon: const Icon(CupertinoIcons.calendar),
                                  label: Text(
                                    _dueBack == null
                                        ? 'Expected return date (optional)'
                                        : 'Back by ${dates.formatMediumDate(_dueBack!)}',
                                  ),
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _dueBack ??
                                          now.add(const Duration(days: 7)),
                                      firstDate: now,
                                      lastDate: now.add(
                                        const Duration(days: 366),
                                      ),
                                    );
                                    if (d != null) {
                                      setState(() => _dueBack = d);
                                    }
                                  },
                                ),
                                if (widget.jobCardId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: Space.sm,
                                    ),
                                    child: Text(
                                      'For a job card: the tools are added '
                                      'to it.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SectionHeader(
                            'Tools · ${_lines.length}',
                            trailing: TextButton.icon(
                              onPressed: _newTool,
                              icon: const Icon(CupertinoIcons.add, size: 18),
                              label: const Text('New tool'),
                            ),
                          ),
                          SurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, l) in _lines.indexed)
                                  _LineTile(
                                    no: i + 1,
                                    line: l,
                                    onChanged: () => setState(() {}),
                                    onRemove: () =>
                                        setState(() => _lines.removeAt(i)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(Space.sm),
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => _pickTools(tools),
                                    icon: const Icon(CupertinoIcons.wrench),
                                    label: Text(
                                      _lines.isEmpty
                                          ? 'Pick tools from the register'
                                          : 'Add more tools',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SectionHeader('Remarks'),
                          field(
                            _remarks,
                            'Remarks (optional)',
                            caps: TextCapitalization.sentences,
                            lines: 2,
                          ),
                          const SectionHeader('Signatures'),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'The person receiving accepts '
                                  'responsibility for the tools and will '
                                  'return them in the same condition, fair '
                                  'wear and tear excepted. Loss or damage '
                                  'through negligence may be charged to '
                                  'their company.',
                                  style: theme.textTheme.bodySmall,
                                ),
                                sign(
                                  'Issued by',
                                  session.profile?.fullName,
                                  _issuer,
                                ),
                                sign('Received by', receiver, _recipient),
                                sign(
                                  'Project team lead (optional)',
                                  _lead.text,
                                  _leadSig,
                                ),
                              ],
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.md),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: Space.lg),
                          FilledButton.icon(
                            onPressed: _busy ? null : _submit,
                            icon: const Icon(
                              CupertinoIcons.arrow_right_circle_fill,
                            ),
                            label: Text(
                              _lines.isEmpty
                                  ? 'Issue tools'
                                  : 'Issue ${_lines.length} '
                                        '${_lines.length == 1 ? 'tool' : 'tools'}',
                            ),
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
}

/// Why a tool cannot go out, or null when it can.
String? issuable(LocalTool t) {
  if (toolOut(t)) return 'Out';
  if (t.condition == 'damaged' || t.condition == 'lost') {
    return ToolCondition.parse(t.condition).label;
  }
  if (calibrationExpired(t)) return 'Calibration expired';
  return null;
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.no,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final int no;
  final _Line line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = line.tool;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('$no', style: theme.textTheme.labelLarge),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: theme.textTheme.titleSmall),
                    Text(
                      [
                        t.code ?? 'New',
                        if (t.serialNo != null) 'S/N ${t.serialNo}',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fewer',
                visualDensity: VisualDensity.compact,
                onPressed: line.qty > 1
                    ? () {
                        line.qty--;
                        onChanged();
                      }
                    : null,
                icon: const Icon(CupertinoIcons.minus_circle),
              ),
              Text('${line.qty}', style: theme.textTheme.titleSmall),
              IconButton(
                tooltip: 'More',
                visualDensity: VisualDensity.compact,
                onPressed: line.qty < 999
                    ? () {
                        line.qty++;
                        onChanged();
                      }
                    : null,
                icon: const Icon(CupertinoIcons.plus_circle),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(CupertinoIcons.xmark),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: Space.sm),
            child: Wrap(
              spacing: Space.xs,
              children: [
                for (final c in [ToolCondition.good, ToolCondition.needsRepair])
                  ChoiceChip(
                    label: Text(c.label),
                    selected: line.condition == c,
                    selectedColor: conditionColor(c).withValues(alpha: 0.2),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      line.condition = c;
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Picks several tools from the register; tools that cannot go out show
/// why.
class ToolPickerSheet extends StatefulWidget {
  const ToolPickerSheet({
    super.key,
    required this.tools,
    this.already = const {},
    this.title = 'Pick tools',
    this.onlyIssuable = true,
  });

  final List<LocalTool> tools;
  final Set<String> already;
  final String title;

  /// Only tools that can go out now are selectable.
  final bool onlyIssuable;

  @override
  State<ToolPickerSheet> createState() => _ToolPickerSheetState();
}

class _ToolPickerSheetState extends State<ToolPickerSheet> {
  final _search = TextEditingController();
  final _picked = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final t in widget.tools)
        if (!widget.already.contains(t.id) && toolMatches(t, q, const {})) t,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Space.sm),
            CupertinoSearchTextField(
              controller: _search,
              placeholder: 'Search name, code or serial',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: CupertinoIcons.wrench,
                        title: 'No tools',
                        message:
                            'Add it with "New tool" if it is not in the '
                            'register yet.',
                      ),
                    )
                  : ListView(
                      children: [
                        for (final t in shown)
                          Builder(
                            builder: (context) {
                              final why = widget.onlyIssuable
                                  ? issuable(t)
                                  : null;
                              return CheckboxListTile.adaptive(
                                value: _picked.contains(t.id),
                                onChanged: why != null
                                    ? null
                                    : (v) => setState(
                                        () => v == true
                                            ? _picked.add(t.id)
                                            : _picked.remove(t.id),
                                      ),
                                title: Text('${t.code ?? 'New'} · ${t.name}'),
                                subtitle: Text(
                                  [
                                    ?why,
                                    if (t.serialNo != null) 'S/N ${t.serialNo}',
                                  ].join(' · '),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: why != null
                                        ? theme.colorScheme.error
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Space.sm),
            FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.pop(context, [
                      for (final t in widget.tools)
                        if (_picked.contains(t.id)) t,
                    ]),
              child: Text(
                _picked.isEmpty ? 'Pick tools' : 'Add ${_picked.length}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a tool to the register from the form: name and serial number.
class _QuickToolSheet extends ConsumerStatefulWidget {
  const _QuickToolSheet();

  @override
  ConsumerState<_QuickToolSheet> createState() => _QuickToolSheetState();
}

class _QuickToolSheetState extends ConsumerState<_QuickToolSheet> {
  final _name = TextEditingController();
  final _serial = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _serial.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Name the tool');
      return;
    }
    final id = await ref
        .read(toolActionsProvider)
        .save(siteId: site.id, name: _name.text, serialNo: _serial.text);
    if (mounted) Navigator.pop(context, id);
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
          Text('New tool', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            'It joins the register with a T- code.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'e.g. Fluke True-RMS Clamp Meter',
            ),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _serial,
            decoration: const InputDecoration(
              labelText: 'Serial number (optional)',
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
          FilledButton(onPressed: _add, child: const Text('Add to the form')),
        ],
      ),
    );
  }
}
