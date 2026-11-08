import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../projects/projects_repository.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../store/store_repository.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'procurement_repository.dart';

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _err(Object e) => AppError.from(e).isRetryable
    ? 'Connect to the internet for that.'
    : AppError.from(e).message;

Color mrColor(String s) => switch (s) {
  'pending' => Colors.orange,
  'approved' || 'part_issued' => BrandColors.info,
  'issued' => BrandColors.success,
  _ => Colors.grey,
};

Color poColor(String s) => switch (s) {
  'requested' => Colors.orange,
  'ordered' => BrandColors.info,
  'delivered' => BrandColors.success,
  _ => Colors.grey,
};

bool canSeePurchases(SessionState s, String? site) =>
    s.can('po.manage', siteId: site) ||
    s.can('mr.approve', siteId: site) ||
    s.can('store.receive', siteId: site);

/// Material requests and purchases at the current site.
class MaterialsScreen extends ConsumerStatefulWidget {
  const MaterialsScreen({super.key, this.purchases = false});

  final bool purchases;

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  late bool _purchases = widget.purchases;
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final seePo = canSeePurchases(session, site?.id);
    final showPo = _purchases && seePo;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    final people = ref.watch(peopleProvider).value ?? const {};

    final List<Widget> rows;
    if (showPo) {
      final pos = ref.watch(purchasesProvider);
      rows = pos.when(
        loading: () => [const Center(child: CircularProgressIndicator())],
        error: (e, _) => [Text(_err(e))],
        data: (list) {
          final shown = [
            for (final o in list)
              if (!_open || o.open) o,
          ];
          return [
            if (shown.isEmpty)
              EmptyState(
                icon: CupertinoIcons.cart,
                title: _open ? 'Nothing on order' : 'No purchases yet',
                message: 'The store raises purchases from approved requests.',
              ),
            for (final (i, o) in shown.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: SurfaceCard(
                  onTap: () => context.push('/purchases/${o.id}'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                RecordCode(o.code),
                                const SizedBox(width: Space.xs),
                                Expanded(
                                  child: Text(
                                    o.supplierName ?? 'No supplier yet',
                                    style: theme.textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              [
                                '${o.lines.length} ${o.lines.length == 1 ? 'line' : 'lines'}',
                                ?o.poNumber,
                                if (o.expectedDate != null && o.open)
                                  'expected ${dates.formatShortMonthDay(o.expectedDate!)}',
                              ].join(' · '),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        label: poStatuses[o.status]!,
                        color: poColor(o.status),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ).entrance(context, index: i.clamp(0, 8)),
          ];
        },
      );
    } else {
      final mrs = ref.watch(materialRequestsProvider(null));
      rows = mrs.when(
        loading: () => [const Center(child: CircularProgressIndicator())],
        error: (e, _) => [Text(_err(e))],
        data: (list) {
          final shown = [
            for (final r in list)
              if (!_open || r.status == 'pending' || r.canIssue) r,
          ];
          return [
            if (shown.isEmpty)
              EmptyState(
                icon: CupertinoIcons.cube_box,
                title: _open ? 'No open requests' : 'No requests yet',
                message:
                    'Ask for cable, breakers and anything else a job needs; '
                    'a supervisor approves and the store issues or orders it.',
              ),
            for (final (i, r) in shown.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: SurfaceCard(
                  onTap: () => context.push('/materials/${r.id}'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                RecordCode(r.code),
                                const SizedBox(width: Space.xs),
                                Expanded(
                                  child: Text(
                                    r.lines
                                        .map((l) => l.description)
                                        .take(3)
                                        .join(', '),
                                    style: theme.textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              [
                                r.forWhat,
                                people[r.requestedBy] ?? 'Someone',
                                dates.formatShortMonthDay(r.createdAt),
                                if (r.neededBy != null)
                                  'needed ${dates.formatShortMonthDay(r.neededBy!)}',
                              ].join(' · '),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        label: mrStatuses[r.status]!,
                        color: mrColor(r.status),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ).entrance(context, index: i.clamp(0, 8)),
          ];
        },
      );
    }

    final fab = showPo
        ? (session.can('po.manage', siteId: site?.id)
              ? FloatingActionButton.extended(
                  onPressed: () => context.push('/purchases/new'),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('New purchase'),
                )
              : null)
        : (session.can('mr.create', siteId: site?.id)
              ? FloatingActionButton.extended(
                  onPressed: () => context.push('/materials/new'),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Request materials'),
                )
              : null);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Materials · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: fab,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async {
            ref.invalidate(materialRequestsProvider);
            ref.invalidate(purchasesProvider);
          },
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
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (seePo)
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Requests'),
                              icon: Icon(CupertinoIcons.doc_plaintext),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Purchases'),
                              icon: Icon(CupertinoIcons.cart),
                            ),
                          ],
                          selected: {_purchases},
                          onSelectionChanged: (s) =>
                              setState(() => _purchases = s.first),
                        ),
                      const SizedBox(height: Space.sm),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Open'),
                            selected: _open,
                            onSelected: (_) => setState(() => _open = true),
                          ),
                          const SizedBox(width: Space.xs),
                          ChoiceChip(
                            label: const Text('All'),
                            selected: !_open,
                            onSelected: (_) => setState(() => _open = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      ...rows,
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

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.doneWord, this.price});

  final OrderLine line;
  final String doneWord;
  final bool? price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = line;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Icon(
            l.done >= l.qty
                ? CupertinoIcons.checkmark_circle_fill
                : l.stocked
                ? CupertinoIcons.cube_box
                : CupertinoIcons.cart,
            color: l.done >= l.qty ? BrandColors.success : null,
            size: 20,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [?l.itemCode, l.description].join(' '),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  [
                    '${qtyText(l.done)} of ${qtyText(l.qty)} ${l.unit} $doneWord',
                    if (!l.stocked) 'not in inventory',
                    if (price == true && l.unitPrice != null)
                      '@ ${l.unitPrice!.toStringAsFixed(2)}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One material request: its lines, and approve, issue, order or cancel.
class MaterialRequestScreen extends ConsumerWidget {
  const MaterialRequestScreen({super.key, required this.id});

  final String id;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    MaterialRequest r,
    bool approve,
  ) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Reject ${r.code}?'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Why'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (note == null) return;
    }
    try {
      await ref.read(procurementActionsProvider).decide(r, approve, note);
      if (context.mounted) _say(context, approve ? 'Approved' : 'Rejected');
    } catch (e) {
      if (context.mounted) _say(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final req = ref.watch(materialRequestProvider(id));
    final r = req.value;
    final session = ref.watch(sessionProvider);
    final me = ref.watch(authUserIdProvider);
    final people = ref.watch(peopleProvider).value ?? const {};
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/materials'),
        title: Text(r?.code ?? 'Material request'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: r == null
            ? Center(
                child: req.isLoading
                    ? const CircularProgressIndicator()
                    : EmptyState(
                        icon: CupertinoIcons.doc_plaintext,
                        title: 'Request not found',
                        message: req.hasError
                            ? _err(req.error!)
                            : 'It may not have reached the server yet.',
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
                          SurfaceCard(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: Space.xs,
                                  runSpacing: Space.xs,
                                  children: [
                                    RecordCode(r.code),
                                    Pill(
                                      label: mrStatuses[r.status]!,
                                      color: mrColor(r.status),
                                    ),
                                    if (r.jobCardNumber != null)
                                      ActionChip(
                                        label: Text(r.jobCardNumber!),
                                        onPressed: () => context.push(
                                          '/jobs/${r.jobCardNumber}',
                                        ),
                                      ),
                                    if (r.projectCode != null)
                                      ActionChip(
                                        label: Text(r.projectCode!),
                                        onPressed: () => context.push(
                                          '/projects/${r.projectId}',
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: Space.sm),
                                Text(
                                  [
                                    'By ${people[r.requestedBy] ?? 'someone'}',
                                    dates.formatShortMonthDay(r.createdAt),
                                    if (r.neededBy != null)
                                      'needed by ${dates.formatShortMonthDay(r.neededBy!)}',
                                  ].join(' · '),
                                  style: theme.textTheme.labelMedium,
                                ),
                                if (r.note != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: Space.xs,
                                    ),
                                    child: Text(r.note!),
                                  ),
                                if (r.decisionNote != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: Space.xs,
                                    ),
                                    child: Text(
                                      '${people[r.decidedBy] ?? 'Supervisor'}: ${r.decisionNote}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.md),
                          Panel(
                            icon: CupertinoIcons.list_bullet,
                            title: 'Lines',
                            child: Column(
                              children: [
                                for (final l in r.lines)
                                  _LineRow(line: l, doneWord: 'issued'),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.md),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              if (r.status == 'pending' &&
                                  session.can(
                                    'mr.approve',
                                    siteId: r.siteId,
                                  )) ...[
                                FilledButton.icon(
                                  onPressed: () =>
                                      _decide(context, ref, r, true),
                                  icon: const Icon(CupertinoIcons.checkmark),
                                  label: const Text('Approve'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _decide(context, ref, r, false),
                                  icon: const Icon(CupertinoIcons.xmark),
                                  label: const Text('Reject'),
                                ),
                              ],
                              if (r.canIssue &&
                                  session.can(
                                    'store.issue',
                                    siteId: r.siteId,
                                  ) &&
                                  r.lines.any((l) => l.stocked && l.left > 0))
                                FilledButton.icon(
                                  onPressed: () => showFormSheet<void>(
                                    context,
                                    _IssueSheet(request: r),
                                  ),
                                  icon: const Icon(
                                    CupertinoIcons.arrow_up_right,
                                  ),
                                  label: const Text('Issue from inventory'),
                                ),
                              if (r.canIssue &&
                                  session.can('po.manage', siteId: r.siteId) &&
                                  r.lines.any((l) => l.left > 0))
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push('/purchases/new?mr=${r.id}'),
                                  icon: const Icon(CupertinoIcons.cart),
                                  label: const Text('Order'),
                                ),
                              if ((r.status == 'pending' ||
                                      r.status == 'approved') &&
                                  (r.requestedBy == me ||
                                      session.can(
                                        'mr.approve',
                                        siteId: r.siteId,
                                      )))
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(procurementActionsProvider)
                                          .cancel(r);
                                    } catch (e) {
                                      if (context.mounted) {
                                        _say(context, _err(e));
                                      }
                                    }
                                  },
                                  child: const Text('Cancel request'),
                                ),
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
}

/// Quantities per line, prefilled with what is left; for issuing a
/// request or receiving a purchase.
class _QtySheet extends StatefulWidget {
  const _QtySheet({
    required this.title,
    required this.lines,
    required this.button,
    required this.onSave,
    this.withNote = false,
  });

  final String title;
  final List<OrderLine> lines;
  final String button;
  final bool withNote;
  final Future<void> Function(Map<String, double> qty, String note) onSave;

  @override
  State<_QtySheet> createState() => _QtySheetState();
}

class _QtySheetState extends State<_QtySheet> {
  late final _qty = {
    for (final l in widget.lines)
      l.id: TextEditingController(text: qtyText(l.left)),
  };
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = <String, double>{};
    for (final l in widget.lines) {
      final v = double.tryParse(_qty[l.id]!.text.trim().replaceAll(',', '.'));
      if (v == null || v <= 0) continue;
      if (v > l.left) {
        setState(
          () => _error =
              'Only ${qtyText(l.left)} ${l.unit} of ${l.description} left',
        );
        return;
      }
      q[l.id] = v;
    }
    if (q.isEmpty) {
      setState(() => _error = 'Enter at least one quantity');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.onSave(q, _note.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          for (final l in widget.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l.description}\n${qtyText(l.left)} ${l.unit} left',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _qty[l.id],
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: l.unit,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.withNote)
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Delivery note (optional)',
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
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.button),
          ),
        ],
      ),
    );
  }
}

class _IssueSheet extends ConsumerWidget {
  const _IssueSheet({required this.request});

  final MaterialRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _QtySheet(
    title: 'Issue ${request.code}',
    button: 'Issue',
    lines: [
      for (final l in request.lines)
        if (l.stocked && l.left > 0) l,
    ],
    onSave: (q, _) => ref.read(procurementActionsProvider).issue(request, q),
  );
}

/// A line being written, before it is sent.
class _Draft {
  _Draft({
    this.itemId,
    this.itemCode,
    required this.description,
    required this.unit,
    required double qty,
    this.mrLineId,
    double? price,
  }) : qty = TextEditingController(text: qty == 0 ? '' : qtyText(qty)),
       price = TextEditingController(
         text: price == null ? '' : price.toStringAsFixed(2),
       );

  final String? itemId;
  final String? itemCode;
  final String description;
  final String unit;
  final String? mrLineId;
  final TextEditingController qty;
  final TextEditingController price;

  double? get qtyValue => double.tryParse(qty.text.trim().replaceAll(',', '.'));
  double? get priceValue =>
      double.tryParse(price.text.trim().replaceAll(',', '.'));

  DraftLine get line => (
    itemId: itemId,
    description: description,
    unit: unit,
    qty: qtyValue ?? 0,
    unitPrice: priceValue,
    mrLineId: mrLineId,
  );

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Lines with quantities (and prices on purchases), added from inventory
/// or typed for things not stocked.
class _LinesEditor extends ConsumerStatefulWidget {
  const _LinesEditor({required this.lines, this.prices = false});

  final List<_Draft> lines;
  final bool prices;

  @override
  ConsumerState<_LinesEditor> createState() => _LinesEditorState();
}

class _LinesEditorState extends ConsumerState<_LinesEditor> {
  Future<void> _addFromInventory() async {
    final stock = await ref.read(storeItemsProvider.future);
    if (!mounted) return;
    final item = await showFormSheet<StoreItem>(
      context,
      _ItemPicker(items: stock.items),
    );
    if (item == null) return;
    setState(
      () => widget.lines.add(
        _Draft(
          itemId: item.id,
          itemCode: item.code,
          description: item.name,
          unit: item.unit,
          qty: 0,
        ),
      ),
    );
  }

  Future<void> _addOther() async {
    final name = TextEditingController();
    final unit = TextEditingController(text: 'pcs');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Something not in inventory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What'),
            ),
            TextField(
              controller: unit,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().length >= 2) {
      setState(
        () => widget.lines.add(
          _Draft(
            description: name.text.trim(),
            unit: unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
            qty: 0,
          ),
        ),
      );
    }
    name.dispose();
    unit.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, d) in widget.lines.indexed)
          Padding(
            key: ObjectKey(d),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [?d.itemCode, d.description].join(' '),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: d.qty,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'qty',
                      suffixText: d.unit,
                    ),
                  ),
                ),
                if (widget.prices) ...[
                  const SizedBox(width: Space.xs),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: d.price,
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'price',
                      ),
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                  onPressed: () => setState(() {
                    widget.lines.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: Space.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _addFromInventory,
              icon: const Icon(CupertinoIcons.cube_box, size: 18),
              label: const Text('From inventory'),
            ),
            TextButton.icon(
              onPressed: _addOther,
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: const Text('Something else'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.items});

  final List<StoreItem> items;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final shown = [
      for (final i in widget.items)
        if (q.isEmpty ||
            i.name.toLowerCase().contains(q) ||
            i.code.toLowerCase().contains(q))
          i,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'From inventory',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.sm),
          CupertinoSearchTextField(onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: Space.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final i in shown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${i.code} ${i.name}'),
                    trailing: Text('${qtyText(i.onHand)} ${i.unit}'),
                    onTap: () => Navigator.pop(context, i),
                  ),
                if (shown.isEmpty) const Text('No items match.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A new material request, from a job card, a project or for the site.
class MaterialRequestForm extends ConsumerStatefulWidget {
  const MaterialRequestForm({super.key, this.jobCardId, this.projectId});

  final String? jobCardId;
  final String? projectId;

  @override
  ConsumerState<MaterialRequestForm> createState() =>
      _MaterialRequestFormState();
}

class _MaterialRequestFormState extends ConsumerState<MaterialRequestForm> {
  final _lines = <_Draft>[];
  final _note = TextEditingController();
  late String? _job = widget.jobCardId;
  late String? _project = widget.projectId;
  DateTime? _needed;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final d in _lines) {
      d.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_lines.isEmpty) {
      setState(() => _error = 'Add what you need');
      return;
    }
    if (_lines.any((d) => (d.qtyValue ?? 0) <= 0)) {
      setState(() => _error = 'Every line needs a quantity');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final id = await ref
          .read(procurementActionsProvider)
          .createRequest(
            siteId: site.id,
            jobCardId: _job,
            projectId: _project,
            neededBy: _needed,
            note: _note.text,
            lines: [for (final d in _lines) d.line],
          );
      if (mounted) context.pushReplacement('/materials/$id');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jobs = ref.watch(openJobCardsProvider).value ?? const [];
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/materials'),
        title: const Text('Request materials'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
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
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String?>(
                        initialValue: _job,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'For a job card (optional)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final j in jobs)
                            DropdownMenuItem(
                              value: j.id,
                              child: Text(
                                '${j.number} · ${j.title}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _job = v),
                      ),
                      const SizedBox(height: Space.sm),
                      DropdownButtonFormField<String?>(
                        initialValue: _project,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'For a project (optional)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final p in projects)
                            if (p.open)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.code} · ${p.name}'),
                              ),
                        ],
                        onChanged: (v) => setState(() => _project = v),
                      ),
                      const SizedBox(height: Space.sm),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate:
                                _needed ?? now.add(const Duration(days: 2)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => _needed = d);
                        },
                        icon: const Icon(CupertinoIcons.calendar),
                        label: Text(
                          _needed == null
                              ? 'Needed by (optional)'
                              : 'Needed by ${dates.formatMediumDate(_needed!)}',
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      Text('What you need', style: theme.textTheme.labelLarge),
                      const SizedBox(height: Space.xs),
                      _LinesEditor(lines: _lines),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
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
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Send for approval'),
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

/// One purchase: lines, mark ordered, receive deliveries, cancel.
class PurchaseScreen extends ConsumerWidget {
  const PurchaseScreen({super.key, required this.id});

  final String id;

  Future<void> _ordered(
    BuildContext context,
    WidgetRef ref,
    PurchaseOrder o,
  ) async {
    final number = TextEditingController(text: o.poNumber);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark ${o.code} ordered'),
        content: TextField(
          controller: number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'PO number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ordered'),
          ),
        ],
      ),
    );
    final text = number.text;
    number.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(procurementActionsProvider)
          .setPurchaseStatus(o, 'ordered', poNumber: text);
    } catch (e) {
      if (context.mounted) _say(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final po = ref.watch(purchaseProvider(id));
    final o = po.value;
    final session = ref.watch(sessionProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/purchases'),
        title: Text(o?.code ?? 'Purchase'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: o == null
            ? Center(
                child: po.isLoading
                    ? const CircularProgressIndicator()
                    : EmptyState(
                        icon: CupertinoIcons.cart,
                        title: 'Purchase not found',
                        message: po.hasError ? _err(po.error!) : '',
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
                          SurfaceCard(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.supplierName ?? 'No supplier yet',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: Space.xs),
                                Wrap(
                                  spacing: Space.xs,
                                  runSpacing: Space.xs,
                                  children: [
                                    RecordCode(o.code),
                                    Pill(
                                      label: poStatuses[o.status]!,
                                      color: poColor(o.status),
                                    ),
                                    if (o.poNumber != null)
                                      Pill(label: 'PO ${o.poNumber}'),
                                    if (o.expectedDate != null)
                                      Pill(
                                        label:
                                            'Expected ${dates.formatShortMonthDay(o.expectedDate!)}',
                                      ),
                                    if (o.total > 0)
                                      Pill(
                                        label:
                                            'Total ${o.total.toStringAsFixed(2)}',
                                      ),
                                  ],
                                ),
                                if (o.note != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: Space.xs,
                                    ),
                                    child: Text(o.note!),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.md),
                          Panel(
                            icon: CupertinoIcons.list_bullet,
                            title: 'Lines',
                            child: Column(
                              children: [
                                for (final l in o.lines)
                                  _LineRow(
                                    line: l,
                                    doneWord: 'received',
                                    price: true,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.md),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              if (o.status == 'requested' &&
                                  session.can('po.manage', siteId: o.siteId))
                                FilledButton.icon(
                                  onPressed: () => _ordered(context, ref, o),
                                  icon: const Icon(CupertinoIcons.paperplane),
                                  label: const Text('Mark ordered'),
                                ),
                              if (o.open &&
                                  session.can(
                                    'store.receive',
                                    siteId: o.siteId,
                                  ))
                                FilledButton.icon(
                                  onPressed: () => showFormSheet<void>(
                                    context,
                                    _QtySheet(
                                      title: 'Receive ${o.code}',
                                      button: 'Receive',
                                      withNote: true,
                                      lines: [
                                        for (final l in o.lines)
                                          if (l.left > 0) l,
                                      ],
                                      onSave: (q, note) => ref
                                          .read(procurementActionsProvider)
                                          .receive(o, q, note: note),
                                    ),
                                  ),
                                  icon: const Icon(
                                    CupertinoIcons.arrow_down_left,
                                  ),
                                  label: const Text('Receive delivery'),
                                ),
                              if (o.open &&
                                  session.can('po.manage', siteId: o.siteId))
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(procurementActionsProvider)
                                          .setPurchaseStatus(o, 'cancelled');
                                    } catch (e) {
                                      if (context.mounted) {
                                        _say(context, _err(e));
                                      }
                                    }
                                  },
                                  child: const Text('Cancel purchase'),
                                ),
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
}

/// A new purchase; from a request ([mrId]) its lines still to supply are
/// filled in.
class PurchaseForm extends ConsumerStatefulWidget {
  const PurchaseForm({super.key, this.mrId});

  final String? mrId;

  @override
  ConsumerState<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends ConsumerState<PurchaseForm> {
  final _lines = <_Draft>[];
  final _number = TextEditingController();
  final _note = TextEditingController();
  String? _supplier;
  DateTime? _expected;
  bool _busy = false;
  bool _filled = false;
  String? _error;

  @override
  void dispose() {
    for (final d in _lines) {
      d.dispose();
    }
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  void _fillFrom(MaterialRequest r) {
    if (_filled) return;
    _filled = true;
    for (final l in r.lines) {
      if (l.left <= 0) continue;
      _lines.add(
        _Draft(
          itemId: l.itemId,
          itemCode: l.itemCode,
          description: l.description,
          unit: l.unit,
          qty: l.left,
          mrLineId: l.id,
        ),
      );
    }
    _note.text = 'For ${r.code}';
  }

  Future<void> _newSupplier() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final n = name.text;
    final ph = phone.text;
    name.dispose();
    phone.dispose();
    if (ok != true) return;
    try {
      final id = await ref
          .read(procurementActionsProvider)
          .saveSupplier(site.id, n, phone: ph);
      setState(() => _supplier = id);
    } catch (e) {
      if (mounted) _say(context, _err(e));
    }
  }

  Future<void> _save() async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_lines.isEmpty) {
      setState(() => _error = 'Add what you are buying');
      return;
    }
    if (_lines.any((d) => (d.qtyValue ?? 0) <= 0)) {
      setState(() => _error = 'Every line needs a quantity');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(procurementActionsProvider)
          .createPurchase(
            siteId: site.id,
            supplierId: _supplier,
            poNumber: _number.text,
            expected: _expected,
            note: _note.text,
            lines: [for (final d in _lines) d.line],
          );
      if (mounted) context.pushReplacement('/purchases/$id');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.mrId != null) {
      final r = ref.watch(materialRequestProvider(widget.mrId!)).value;
      if (r != null) _fillFrom(r);
    }
    final suppliers = ref.watch(suppliersProvider).value ?? const [];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/purchases'),
        title: const Text('New purchase'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
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
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey(_supplier),
                              initialValue: _supplier,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Supplier',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Not chosen yet'),
                                ),
                                for (final s in suppliers)
                                  DropdownMenuItem(
                                    value: s.id,
                                    child: Text(s.name),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _supplier = v),
                            ),
                          ),
                          IconButton(
                            tooltip: 'New supplier',
                            icon: const Icon(CupertinoIcons.person_add),
                            onPressed: _newSupplier,
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _number,
                        decoration: const InputDecoration(
                          labelText: 'PO number (optional)',
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate:
                                _expected ?? now.add(const Duration(days: 7)),
                            firstDate: now.subtract(const Duration(days: 30)),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => _expected = d);
                        },
                        icon: const Icon(CupertinoIcons.calendar),
                        label: Text(
                          _expected == null
                              ? 'Expected (optional)'
                              : 'Expected ${dates.formatMediumDate(_expected!)}',
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      Text(
                        'Lines (quantity, unit price)',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: Space.xs),
                      _LinesEditor(lines: _lines, prices: true),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
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
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Create purchase'),
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
