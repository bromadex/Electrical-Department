import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../theme/theme_mode.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';
import 'store_repository.dart';

/// Stock count: walk the shelves and type what is there. Only the items
/// counted are sent; those that differ from stock on hand are corrected.
/// What is typed is kept on the device until the count is saved, so leaving
/// the screen does not lose it.
class StoreCountScreen extends ConsumerStatefulWidget {
  const StoreCountScreen({super.key});

  @override
  ConsumerState<StoreCountScreen> createState() => _StoreCountScreenState();
}

class _StoreCountScreenState extends ConsumerState<StoreCountScreen> {
  final _counted = <String, double>{};
  final _countedAt = <String, DateTime>{};
  final _note = TextEditingController();
  String _query = '';
  bool _busy = false;
  bool _restored = false;
  String? _draftKey;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authUserIdProvider);
    final site = ref.read(currentSiteProvider);
    if (user != null && site != null) {
      _draftKey = countDraftKey(user, site.id);
      final draft = CountDraft.decode(
        ref.read(sharedPrefsProvider).getString(_draftKey!),
      );
      if (!draft.isEmpty) {
        _counted.addAll(draft.counted);
        _countedAt.addAll(draft.countedAt);
        _note.text = draft.note;
        _restored = true;
      }
    }
    _note.addListener(_saveDraft);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _saveDraft() {
    final key = _draftKey;
    if (key == null) return;
    final draft = CountDraft(
      counted: _counted,
      countedAt: _countedAt,
      note: _note.text,
    );
    final prefs = ref.read(sharedPrefsProvider);
    unawaited(
      draft.isEmpty ? prefs.remove(key) : prefs.setString(key, draft.encode()),
    );
  }

  void _set(String id, double? v) {
    setState(() {
      if (v == null) {
        _counted.remove(id);
        _countedAt.remove(id);
      } else {
        _counted[id] = v;
        _countedAt[id] = DateTime.now();
      }
    });
    _saveDraft();
  }

  Future<void> _startAgain() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start the count again?'),
        content: Text(
          'The ${_counted.length} items counted so far are cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start again'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _counted.clear();
      _countedAt.clear();
      _restored = false;
      // Fresh boxes: the lines are keyed by this generation.
      _generation++;
    });
    _note.clear();
    _saveDraft();
  }

  int _generation = 0;

  Future<void> _submit(List<StoreItem> items) async {
    final site = ref.read(currentSiteProvider);
    if (site == null || _counted.isEmpty) return;
    final diff = countDifferences(items, _counted);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save the count of ${_counted.length} items?'),
        content: Text(
          diff.isEmpty
              ? 'Everything counted matches stock on hand.'
              : '${diff.length} ${diff.length == 1 ? 'item differs' : 'items differ'} '
                    'and will be corrected to what you counted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep counting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save count'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(storeActionsProvider)
          .submitCount(
            site.id,
            Map.of(_counted),
            countedAt: Map.of(_countedAt),
            note: _note.text,
          );
      final key = _draftKey;
      if (key != null) {
        await ref.read(sharedPrefsProvider).remove(key);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Count saved: ${_counted.length} counted, '
            '${diff.length} corrected',
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stock = ref.watch(storeItemsProvider);
    // A count is of one site's shelves, whatever the list shows.
    final here = ref.watch(currentSiteProvider)?.id;
    final items = [
      for (final i in stock.value?.items ?? const <StoreItem>[])
        if (i.siteId == here) i,
    ];
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final i in items)
        if (q.isEmpty ||
            i.name.toLowerCase().contains(q) ||
            i.code.toLowerCase().contains(q) ||
            (i.bin?.toLowerCase().contains(q) ?? false))
          i,
    ]..sort((a, b) => (a.bin ?? '~').compareTo(b.bin ?? '~'));
    final diff = countDifferences(items, _counted);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/inventory'),
        title: const Text('Count stock'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
        actions: [
          IconButton(
            tooltip: 'Past counts',
            icon: const Icon(CupertinoIcons.clock),
            onPressed: () => context.push('/inventory/counts'),
          ),
          if (_counted.isNotEmpty)
            IconButton(
              tooltip: 'Start again',
              icon: const Icon(CupertinoIcons.arrow_counterclockwise),
              onPressed: _busy ? null : _startAgain,
            ),
        ],
      ),
      floatingActionButton: _counted.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _submit(items),
              icon: const Icon(CupertinoIcons.checkmark_alt),
              label: Text('Save count (${_counted.length})'),
            ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(Space.md, top + Space.md, Space.md, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Type what is on the shelf. Items you leave empty are '
                      'not counted. Sorted by bin.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_restored) ...[
                      const SizedBox(height: Space.sm),
                      Text(
                        'Carrying on with the count you started: '
                        '${_counted.length} items already counted.',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.sm),
                    CupertinoSearchTextField(
                      placeholder: 'Find an item or bin',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: Space.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Text(
                        _counted.isEmpty
                            ? '${items.length} items to count'
                            : '${_counted.length} counted · '
                                  '${diff.length} ${diff.length == 1 ? 'differs' : 'differ'}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    if (stock.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (items.isEmpty)
                      const EmptyState(
                        icon: CupertinoIcons.cube_box,
                        title: 'Nothing to count',
                        message: 'Add items to the inventory first.',
                      ),
                    for (final i in shown)
                      // Keyed so a line keeps what was typed when the list
                      // above it changes.
                      Padding(
                        key: ValueKey('${i.id}#$_generation'),
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: CountLine(
                          item: i,
                          counted: _counted[i.id],
                          onChanged: (v) => _set(i.id, v),
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    TextField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: 'Note on this count (optional)',
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

/// One item on the count: its bin and stock on hand, a box for what is on
/// the shelf, and the difference once typed.
class CountLine extends StatelessWidget {
  const CountLine({
    super.key,
    required this.item,
    required this.counted,
    required this.onChanged,
  });

  final StoreItem item;
  final double? counted;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = counted;
    final diff = c == null ? 0.0 : c - item.onHand;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    item.code,
                    if (item.bin != null) 'Bin ${item.bin}',
                    'system ${qtyText(item.onHand)} ${item.unit}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (c != null && diff != 0)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Text(
                '${diff > 0 ? '+' : '−'}${qtyText(diff.abs())}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.orange,
                ),
              ),
            )
          else if (c != null)
            const Padding(
              padding: EdgeInsets.only(right: Space.sm),
              child: Icon(
                CupertinoIcons.checkmark_alt,
                color: BrandColors.success,
                size: 18,
              ),
            ),
          SizedBox(
            width: 112,
            child: TextFormField(
              initialValue: c == null ? null : qtyText(c),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                hintText: '—',
                suffixText: item.unit,
              ),
              onChanged: (v) {
                final t = v.trim().replaceAll(',', '.');
                final n = double.tryParse(t);
                onChanged(t.isEmpty || n == null || n < 0 ? null : n);
              },
            ),
          ),
        ],
      ),
    );
  }
}
