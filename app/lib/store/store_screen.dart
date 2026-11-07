import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'store_repository.dart';

/// The electrical store at the current site: stock on hand with search,
/// low-stock and category filters.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String _query = '';
  String? _category;
  bool _low = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = ref.watch(currentSiteProvider);
    final session = ref.watch(sessionProvider);
    final canAdd = session.can('store.adjust', siteId: site?.id);
    final items = ref.watch(storeItemsProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Store · ${site?.code ?? ''}'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (canAdd)
            IconButton(
              tooltip: 'Count stock',
              icon: const Icon(CupertinoIcons.number_square),
              onPressed: () => context.push('/store/count'),
            ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => showFormSheet<void>(context, const ItemForm()),
              icon: const Icon(CupertinoIcons.add),
              label: const Text('New item'),
            )
          : null,
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(storeItemsProvider),
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
                      CupertinoSearchTextField(
                        placeholder: 'Search items, I- codes or bins',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: Space.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            chip(
                              'All',
                              !_low && _category == null,
                              () => setState(() {
                                _low = false;
                                _category = null;
                              }),
                            ),
                            chip(
                              'Low stock',
                              _low,
                              () => setState(() => _low = !_low),
                            ),
                            for (final c in storeCategories.entries)
                              chip(
                                c.value,
                                _category == c.key,
                                () => setState(
                                  () => _category = _category == c.key
                                      ? null
                                      : c.key,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      ...items.when(
                        loading: () => [
                          const Center(child: CircularProgressIndicator()),
                        ],
                        error: (e, _) => [
                          EmptyState(
                            icon: CupertinoIcons.wifi_slash,
                            title: 'Could not load the store',
                            message: AppError.from(e).isRetryable
                                ? 'The store loads when you are connected.'
                                : AppError.from(e).message,
                          ),
                        ],
                        data: (stock) {
                          final list = stock.items;
                          final q = _query.trim().toLowerCase();
                          final low = list.where((i) => i.low).length;
                          final shown = [
                            for (final i in list)
                              if ((!_low || i.low || i.empty) &&
                                  (_category == null ||
                                      i.category == _category) &&
                                  (q.isEmpty ||
                                      i.name.toLowerCase().contains(q) ||
                                      i.code.toLowerCase().contains(q) ||
                                      (i.bin?.toLowerCase().contains(q) ??
                                          false)))
                                i,
                          ];
                          return [
                            if (stock.offline)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.wifi_slash,
                                      size: 16,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: Space.xs),
                                    Expanded(
                                      child: Text(
                                        'No signal: stock as saved '
                                        '${MaterialLocalizations.of(context).formatShortMonthDay(stock.savedAt!)} '
                                        '${TimeOfDay.fromDateTime(stock.savedAt!).format(context)}',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(color: Colors.orange),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (list.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                  left: Space.xs,
                                ),
                                child: Text(
                                  '${list.length} ${list.length == 1 ? 'item' : 'items'}'
                                  '${low > 0 ? ' · $low low' : ''}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (shown.isEmpty)
                              EmptyState(
                                icon: CupertinoIcons.cube_box,
                                title: list.isEmpty
                                    ? 'The store is empty'
                                    : 'Nothing here',
                                message: list.isEmpty
                                    ? 'The storekeeper adds items, then '
                                          'receives stock into them.'
                                    : 'No items match.',
                              ),
                            for (final (n, i) in shown.indexed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.sm,
                                ),
                                child: _ItemTile(item: i),
                              ).entrance(context, index: n.clamp(0, 8)),
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

Color _levelColor(StoreItem i) => i.empty
    ? Colors.red
    : i.low
    ? Colors.orange
    : BrandColors.success;

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final StoreItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      onTap: () => context.push('/store/${item.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RecordCode(item.code),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        item.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    storeCategories[item.category] ?? item.category,
                    if (item.bin != null) 'Bin ${item.bin}',
                    if (item.minLevel > 0)
                      'min ${qtyText(item.minLevel)} ${item.unit}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                qtyText(item.onHand),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: _levelColor(item),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(item.unit, style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// One item: stock on hand, receive and issue, and every move.
class StoreItemScreen extends ConsumerWidget {
  const StoreItemScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = ref.watch(storeItemProvider(id));
    final moves = ref.watch(stockMovesProvider(id));
    final people = ref.watch(peopleProvider).value ?? const {};
    final session = ref.watch(sessionProvider);
    final i = item.value;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/store'),
        title: Text(i?.code ?? 'Item'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          if (i != null && session.can('store.adjust', siteId: i.siteId))
            IconButton(
              tooltip: 'Edit item',
              icon: const Icon(CupertinoIcons.pencil),
              onPressed: () => showFormSheet<void>(context, ItemForm(item: i)),
            ),
        ],
      ),
      body: MeshBackground(
        child: i == null
            ? Center(
                child: item.isLoading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        icon: CupertinoIcons.cube_box,
                        title: 'Item not found',
                        message: 'It may have been archived.',
                      ),
              )
            : RefreshIndicator(
                edgeOffset: top,
                onRefresh: () async => ref.invalidate(storeItemProvider(id)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SurfaceCard(
                              padding: const EdgeInsets.all(Space.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i.name,
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Wrap(
                                    spacing: Space.xs,
                                    runSpacing: Space.xs,
                                    children: [
                                      RecordCode(i.code),
                                      Pill(
                                        label:
                                            storeCategories[i.category] ??
                                            i.category,
                                      ),
                                      if (i.bin != null)
                                        Pill(label: 'Bin ${i.bin}'),
                                    ],
                                  ),
                                  const SizedBox(height: Space.md),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        qtyText(i.onHand),
                                        style: theme.textTheme.displaySmall
                                            ?.copyWith(
                                              color: _levelColor(i),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(width: Space.xs),
                                      Text(
                                        '${i.unit} in stock',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                  if (i.minLevel > 0)
                                    Text(
                                      i.low
                                          ? 'Below the minimum of '
                                                '${qtyText(i.minLevel)} ${i.unit}'
                                          : 'Minimum ${qtyText(i.minLevel)} ${i.unit}',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: i.low ? Colors.orange : null,
                                          ),
                                    ),
                                  const SizedBox(height: Space.md),
                                  Wrap(
                                    spacing: Space.sm,
                                    runSpacing: Space.sm,
                                    children: [
                                      if (session.can(
                                        'store.issue',
                                        siteId: i.siteId,
                                      ))
                                        FilledButton.icon(
                                          onPressed: i.empty
                                              ? null
                                              : () => showFormSheet<void>(
                                                  context,
                                                  StockSheet(item: i),
                                                ),
                                          icon: const Icon(
                                            CupertinoIcons.arrow_up_right,
                                          ),
                                          label: const Text('Issue'),
                                        ),
                                      if (session.can(
                                        'store.receive',
                                        siteId: i.siteId,
                                      ))
                                        OutlinedButton.icon(
                                          onPressed: () => showFormSheet<void>(
                                            context,
                                            StockSheet(
                                              item: i,
                                              action: StockAction.receive,
                                            ),
                                          ),
                                          icon: const Icon(
                                            CupertinoIcons.arrow_down_left,
                                          ),
                                          label: const Text('Receive'),
                                        ),
                                      if (session.can(
                                        'store.receive',
                                        siteId: i.siteId,
                                      ))
                                        OutlinedButton.icon(
                                          onPressed: () => showFormSheet<void>(
                                            context,
                                            StockSheet(
                                              item: i,
                                              action: StockAction.giveBack,
                                            ),
                                          ),
                                          icon: const Icon(
                                            CupertinoIcons.arrow_uturn_left,
                                          ),
                                          label: const Text('Take back'),
                                        ),
                                      if (session.can(
                                        'store.adjust',
                                        siteId: i.siteId,
                                      ))
                                        OutlinedButton.icon(
                                          onPressed: () => showFormSheet<void>(
                                            context,
                                            StockSheet(
                                              item: i,
                                              action: StockAction.adjust,
                                            ),
                                          ),
                                          icon: const Icon(
                                            CupertinoIcons.slider_horizontal_3,
                                          ),
                                          label: const Text('Adjust'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Space.md),
                            Panel(
                              icon: CupertinoIcons.clock,
                              title: 'Movements',
                              child: moves.when(
                                loading: () => const LinearProgressIndicator(),
                                error: (e, _) => Text(AppError.from(e).message),
                                data: (list) => list.isEmpty
                                    ? Text(
                                        'No stock has moved yet.',
                                        style: theme.textTheme.labelMedium,
                                      )
                                    : Column(
                                        children: [
                                          for (final m in list)
                                            ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              dense: true,
                                              onTap: m.jobCardNumber == null
                                                  ? null
                                                  : () => context.push(
                                                      '/jobs/${m.jobCardNumber}',
                                                    ),
                                              leading: Icon(
                                                switch (m.kind) {
                                                  'receive' =>
                                                    CupertinoIcons
                                                        .arrow_down_left,
                                                  'issue' =>
                                                    CupertinoIcons
                                                        .arrow_up_right,
                                                  'return' =>
                                                    CupertinoIcons
                                                        .arrow_uturn_left,
                                                  'count' =>
                                                    CupertinoIcons
                                                        .number_square,
                                                  _ =>
                                                    CupertinoIcons
                                                        .slider_horizontal_3,
                                                },
                                                color: m.qty > 0
                                                    ? BrandColors.success
                                                    : theme.colorScheme.primary,
                                              ),
                                              title: Text(
                                                moveTitle(
                                                  m,
                                                  i.unit,
                                                  m.jobCardNumber ??
                                                      people[m.toUser] ??
                                                      m.toName,
                                                ),
                                              ),
                                              subtitle: Text(
                                                [
                                                  '${dates.formatShortMonthDay(m.createdAt)} '
                                                      '${TimeOfDay.fromDateTime(m.createdAt).format(context)}',
                                                  if (people[m.createdBy]
                                                      case final String by)
                                                    'by $by',
                                                  ?m.note,
                                                ].join(' · '),
                                              ),
                                              trailing: Text(
                                                qtyText(m.balanceAfter),
                                                style:
                                                    theme.textTheme.labelMedium,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
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

enum StockAction { issue, receive, giveBack, adjust }

/// Receive stock, issue it to a job card or a person, take unused stock
/// back, or correct it with a reason.
class StockSheet extends ConsumerStatefulWidget {
  const StockSheet({
    super.key,
    required this.item,
    this.action = StockAction.issue,
  });

  final StoreItem item;
  final StockAction action;

  @override
  ConsumerState<StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<StockSheet> {
  final _qty = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();
  String? _jobCard;
  String? _person;
  bool _toJob = true;
  bool _add = false;
  String? _error;
  bool _busy = false;

  StockAction get _action => widget.action;

  /// Issue and give-back name a job card or a person.
  bool get _withWho =>
      _action == StockAction.issue || _action == StockAction.giveBack;

  @override
  void dispose() {
    _qty.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final i = widget.item;
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter how much');
      return;
    }
    final takesOff =
        _action == StockAction.issue ||
        (_action == StockAction.adjust && !_add);
    if (takesOff && qty > i.onHand) {
      setState(() => _error = 'Only ${qtyText(i.onHand)} ${i.unit} in stock');
      return;
    }
    if (_withWho &&
        (_toJob ? _jobCard == null : _person == null && _name.text.isEmpty)) {
      setState(
        () => _error = _toJob
            ? 'Pick the job card'
            : 'Pick the person or type a name',
      );
      return;
    }
    if (_action == StockAction.adjust && _note.text.trim().length < 3) {
      setState(() => _error = 'Say why stock changes');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final actions = ref.read(storeActionsProvider);
      final job = _toJob ? _jobCard : null;
      final user = _toJob ? null : _person;
      final name = _toJob || _person != null ? null : _name.text;
      switch (_action) {
        case StockAction.receive:
          await actions.receive(i, qty, note: _note.text);
        case StockAction.issue:
          await actions.issue(
            i,
            qty,
            jobCardId: job,
            toUser: user,
            toName: name,
            note: _note.text,
          );
        case StockAction.giveBack:
          await actions.giveBack(
            i,
            qty,
            jobCardId: job,
            fromUser: user,
            fromName: name,
            note: _note.text,
          );
        case StockAction.adjust:
          await actions.adjust(i, _add ? qty : -qty, _note.text);
      }
      if (mounted) Navigator.pop(context);
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
    final i = widget.item;
    final jobs = _withWho
        ? ref.watch(openJobCardsProvider).value ?? const []
        : const <({String id, String number, String title})>[];
    final people = ref.watch(peopleProvider).value ?? const {};
    final names = people.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final back = _action == StockAction.giveBack;
    final (title, button) = switch (_action) {
      StockAction.receive => ('Receive stock', 'Receive'),
      StockAction.issue => ('Issue stock', 'Issue'),
      StockAction.giveBack => ('Take stock back', 'Take back'),
      StockAction.adjust => ('Adjust stock', 'Adjust'),
    };
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
          Text(title, style: theme.textTheme.headlineSmall),
          Text(
            '${i.code} ${i.name} · ${qtyText(i.onHand)} ${i.unit} in stock',
            style: theme.textTheme.bodySmall,
          ),
          if (_action == StockAction.adjust) ...[
            const SizedBox(height: Space.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Take off')),
                ButtonSegment(value: true, label: Text('Add')),
              ],
              selected: {_add},
              onSelectionChanged: (s) => setState(() => _add = s.first),
            ),
          ],
          const SizedBox(height: Space.md),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'How much',
              suffixText: i.unit,
            ),
          ),
          if (_withWho) ...[
            const SizedBox(height: Space.md),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(back ? 'From a job card' : 'To a job card'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(back ? 'From a person' : 'To a person'),
                ),
              ],
              selected: {_toJob},
              onSelectionChanged: (s) => setState(() => _toJob = s.first),
            ),
            const SizedBox(height: Space.sm),
            if (_toJob)
              DropdownButtonFormField<String>(
                initialValue: _jobCard,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Job card'),
                items: [
                  for (final j in jobs)
                    DropdownMenuItem(
                      value: j.id,
                      child: Text(
                        '${j.number} · ${j.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _jobCard = v),
              )
            else ...[
              DropdownButtonFormField<String?>(
                initialValue: _person,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Person'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Someone else (type the name)'),
                  ),
                  for (final p in names)
                    if (p.value.isNotEmpty)
                      DropdownMenuItem(value: p.key, child: Text(p.value)),
                ],
                onChanged: (v) => setState(() => _person = v),
              ),
              if (_person == null) ...[
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name and company',
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: Space.sm),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: switch (_action) {
                StockAction.receive => 'Supplier or delivery note (optional)',
                StockAction.adjust => 'Why (damaged, found, written off…)',
                _ => 'Note (optional)',
              },
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
          FilledButton(onPressed: _busy ? null : _save, child: Text(button)),
        ],
      ),
    );
  }
}

/// Adds or edits a store item.
class ItemForm extends ConsumerStatefulWidget {
  const ItemForm({super.key, this.item});

  final StoreItem? item;

  @override
  ConsumerState<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<ItemForm> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _bin = TextEditingController(text: widget.item?.bin);
  late final _min = TextEditingController(
    text: widget.item == null || widget.item!.minLevel == 0
        ? ''
        : qtyText(widget.item!.minLevel),
  );
  late String _unit = widget.item?.unit ?? 'pcs';
  late String _category = widget.item?.category ?? 'cable';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _bin.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Name the item');
      return;
    }
    final min = _min.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_min.text.trim().replaceAll(',', '.'));
    if (min == null || min < 0) {
      setState(() => _error = 'The minimum is a number');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(storeActionsProvider)
          .saveItem(
            item: widget.item,
            siteId: widget.item?.siteId ?? site.id,
            name: _name.text,
            unit: _unit,
            category: _category,
            bin: _bin.text,
            minLevel: min,
            archived: archive,
          );
      if (!mounted) return;
      Navigator.pop(context);
      if (archive) context.go('/store');
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
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
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
          Text(
            widget.item == null ? 'New item' : 'Edit ${widget.item!.code}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. 16mm² 4-core armoured cable',
            ),
          ),
          label('Unit'),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final u in storeUnits)
                ChoiceChip(
                  label: Text(u),
                  selected: _unit == u,
                  onSelected: (_) => setState(() => _unit = u),
                ),
            ],
          ),
          label('Category'),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final c in storeCategories.entries)
                ChoiceChip(
                  label: Text(c.value),
                  selected: _category == c.key,
                  onSelected: (_) => setState(() => _category = c.key),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bin,
                  decoration: const InputDecoration(labelText: 'Bin or shelf'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Alert below',
                    suffixText: _unit,
                  ),
                ),
              ),
            ],
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
            child: Text(widget.item == null ? 'Add item' : 'Save'),
          ),
          if (widget.item != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : () => _save(archive: true),
              icon: const Icon(CupertinoIcons.archivebox),
              label: const Text('Archive item'),
            ),
        ],
      ),
    );
  }
}
