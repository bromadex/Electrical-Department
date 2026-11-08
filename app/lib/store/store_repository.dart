import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../v2/site_filter.dart';

/// The electrical store, stock basics (API.md section 13b): items with I-
/// codes and stock on hand, moved only by receiving and issuing.
const storeCategories = {
  'cable': 'Cable',
  'breakers': 'Breakers',
  'lugs': 'Lugs',
  'glands': 'Glands',
  'lamps': 'Lamps',
  'fittings': 'Fittings',
  'consumables': 'Consumables',
  'other': 'Other',
};

const storeUnits = [
  'pcs',
  'm',
  'roll',
  'box',
  'pack',
  'pair',
  'set',
  'kg',
  'l',
];

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// 12.5 → "12.5", 12.0 → "12", 0.25 → "0.25".
String qtyText(double q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

class StoreItem {
  StoreItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      name = j['name'] as String,
      unit = j['unit'] as String,
      category = j['category'] as String,
      bin = j['bin'] as String?,
      minLevel = _num(j['min_level']),
      onHand = _num(j['on_hand']);

  final String id;
  final String siteId;
  final String code;
  final String name;
  final String unit;
  final String category;
  final String? bin;
  final double minLevel;
  final double onHand;

  bool get low => minLevel > 0 && onHand < minLevel;
  bool get empty => onHand <= 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'code': code,
    'name': name,
    'unit': unit,
    'category': category,
    'bin': bin,
    'min_level': minLevel,
    'on_hand': onHand,
  };
}

/// The stock list, and when it was saved on this device if it is the copy
/// shown without signal.
class StoreStock {
  const StoreStock(this.items, {this.savedAt});

  final List<StoreItem> items;
  final DateTime? savedAt;

  bool get offline => savedAt != null;
}

/// The saved copy of a site's stock list, as JSON.
String encodeStock(List<StoreItem> items, DateTime at) => jsonEncode({
  'at': at.toUtc().toIso8601String(),
  'items': [for (final i in items) i.toJson()],
});

StoreStock? decodeStock(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return StoreStock([
      for (final i in j['items'] as List)
        StoreItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ], savedAt: DateTime.parse(j['at'] as String).toLocal());
  } catch (_) {
    return null;
  }
}

/// How a movement reads: "+120 m received", "−20 m to J-0012",
/// "+6 m back from Tinashe", "−2 m adjusted", "−5 m on count".
String moveTitle(StockMove m, String unit, String? who) {
  final q = '${m.qty > 0 ? '+' : '−'}${qtyText(m.qty.abs())} $unit';
  return switch (m.kind) {
    'receive' => '$q received',
    'issue' => '$q to ${who ?? 'someone'}',
    'return' => '$q back${who == null ? '' : ' from $who'}',
    'adjust' => '$q adjusted',
    'count' => '$q on count',
    _ => q,
  };
}

/// Stock count differences: how far each counted item is from stock on
/// hand (counted minus on hand), only for items that differ.
Map<String, double> countDifferences(
  List<StoreItem> items,
  Map<String, double> counted,
) => {
  for (final i in items)
    if (counted[i.id] case final double c when c != i.onHand)
      i.id: c - i.onHand,
};

class StockMove {
  StockMove.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      qty = _num(j['qty']),
      balanceAfter = _num(j['balance_after']),
      jobCardId = j['job_card_id'] as String?,
      jobCardNumber = (j['job_card'] as Map?)?['number'] as String?,
      toUser = j['to_user'] as String?,
      toName = j['to_name'] as String?,
      note = j['note'] as String?,
      createdBy = j['created_by'] as String?,
      createdAt = DateTime.parse(j['created_at'] as String).toLocal();

  final String id;
  final String kind;
  final double qty;
  final double balanceAfter;
  final String? jobCardId;
  final String? jobCardNumber;
  final String? toUser;
  final String? toName;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;
}

String _cacheKey(String site) => 'store_stock_$site';

/// The current site's items (or every site's, with All my sites), by name.
/// Online it saves a copy on the device; without signal it shows that copy.
final storeItemsProvider = FutureProvider<StoreStock>((ref) async {
  final filter = ref.watch(siteFilterProvider);
  if (filter == null && !ref.watch(allSitesProvider)) {
    return const StoreStock([]);
  }
  final site = filter ?? 'all';
  try {
    var q = ref
        .watch(supabaseProvider)
        .from('store_items')
        .select()
        .eq('is_archived', false);
    if (filter != null) q = q.eq('site_id', filter);
    final rows = await q
        .order('name')
        // Weak signal retries for a long time; show the saved copy instead.
        .timeout(const Duration(seconds: 8));
    final items = [for (final r in rows) StoreItem.fromJson(r)];
    try {
      await ref
          .read(sharedPrefsProvider)
          .setString(_cacheKey(site), encodeStock(items, DateTime.now()));
    } catch (_) {}
    return StoreStock(items);
  } catch (e) {
    StoreStock? saved;
    try {
      saved = decodeStock(
        ref.read(sharedPrefsProvider).getString(_cacheKey(site)),
      );
    } catch (_) {}
    if (saved == null) rethrow;
    return saved;
  }
});

final storeItemProvider = FutureProvider.autoDispose.family<StoreItem?, String>(
  (ref, id) async {
    try {
      final row = await ref
          .watch(supabaseProvider)
          .from('store_items')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : StoreItem.fromJson(row);
    } catch (_) {
      // Without signal, the saved stock list.
      final stock = await ref.read(storeItemsProvider.future);
      final hit = stock.items.where((i) => i.id == id).firstOrNull;
      if (hit == null) rethrow;
      return hit;
    }
  },
);

/// An item's moves, newest first.
final stockMovesProvider = FutureProvider.autoDispose
    .family<List<StockMove>, String>((ref, itemId) async {
      ref.watch(storeItemProvider(itemId));
      final rows = await ref
          .watch(supabaseProvider)
          .from('stock_moves')
          .select('*, job_card:job_cards(number)')
          .eq('item_id', itemId)
          .order('created_at', ascending: false)
          .limit(200);
      return [for (final r in rows) StockMove.fromJson(r)];
    });

/// Open job cards at the current site, to issue stock to.
final openJobCardsProvider =
    FutureProvider.autoDispose<
      List<({String id, String number, String title})>
    >((ref) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      if (site == null) return const [];
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_cards')
          .select('id, number, title')
          .eq('site_id', site)
          .eq('is_archived', false)
          .not('status', 'in', '(closed,cancelled)')
          .order('registered_at', ascending: false)
          .limit(200);
      return [
        for (final r in rows)
          (
            id: r['id'] as String,
            number: r['number'] as String,
            title: r['title'] as String? ?? '',
          ),
      ];
    });

final storeActionsProvider = Provider((ref) => StoreActions(ref));

/// Store writes go through the outbox, so they are kept without signal and
/// sent when the phone is back online.
class StoreActions {
  StoreActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<void> _send(String action, Map<String, dynamic> p, String id) async {
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue(action, p, clientRef: id, flushNow: false);
    await outbox.flush();
    _ref.invalidate(storeItemsProvider);
  }

  Future<String> saveItem({
    StoreItem? item,
    required String siteId,
    required String name,
    required String unit,
    required String category,
    String? bin,
    double minLevel = 0,
    bool archived = false,
  }) async {
    final id = item?.id ?? _uuid.v4();
    await _send('fn_save_item', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_name': name.trim(),
      'p_unit': unit,
      'p_category': category,
      'p_bin': bin?.trim(),
      'p_min_level': minLevel,
      'p_archived': archived,
    }, id);
    _ref.invalidate(storeItemProvider(id));
    return id;
  }

  Future<void> receive(StoreItem item, double qty, {String? note}) async {
    final id = _uuid.v4();
    await _send('fn_receive_stock', {
      'p_client_ref': id,
      'p_item': item.id,
      'p_qty': qty,
      'p_note': note?.trim(),
    }, id);
    _ref.invalidate(storeItemProvider(item.id));
  }

  Future<void> issue(
    StoreItem item,
    double qty, {
    String? jobCardId,
    String? toUser,
    String? toName,
    String? note,
  }) async {
    final id = _uuid.v4();
    await _send('fn_issue_stock', {
      'p_client_ref': id,
      'p_item': item.id,
      'p_qty': qty,
      'p_job_card': jobCardId,
      'p_to': toUser,
      'p_to_name': toName?.trim(),
      'p_note': note?.trim(),
    }, id);
    _ref.invalidate(storeItemProvider(item.id));
  }

  /// Unused stock coming back from a job card or a person.
  Future<void> giveBack(
    StoreItem item,
    double qty, {
    String? jobCardId,
    String? fromUser,
    String? fromName,
    String? note,
  }) async {
    final id = _uuid.v4();
    await _send('fn_return_stock', {
      'p_client_ref': id,
      'p_item': item.id,
      'p_qty': qty,
      'p_job_card': jobCardId,
      'p_from': fromUser,
      'p_from_name': fromName?.trim(),
      'p_note': note?.trim(),
    }, id);
    _ref.invalidate(storeItemProvider(item.id));
  }

  /// Corrects stock by [delta] (negative takes it off), with the reason.
  Future<void> adjust(StoreItem item, double delta, String reason) async {
    final id = _uuid.v4();
    await _send('fn_adjust_stock', {
      'p_client_ref': id,
      'p_item': item.id,
      'p_delta': delta,
      'p_reason': reason.trim(),
    }, id);
    _ref.invalidate(storeItemProvider(item.id));
  }

  /// Records a count: what is on the shelf for each counted item, and when
  /// it was counted, so the server corrects stock as it was then (moves
  /// since stay).
  Future<void> submitCount(
    String siteId,
    Map<String, double> counted, {
    Map<String, DateTime> countedAt = const {},
    String? note,
  }) async {
    final id = _uuid.v4();
    await _send('fn_submit_count', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_lines': [
        for (final e in counted.entries)
          {
            'item_id': e.key,
            'counted': e.value,
            if (countedAt[e.key] case final DateTime at)
              'counted_at': at.toUtc().toIso8601String(),
          },
      ],
      'p_note': note?.trim(),
    }, id);
    _ref.invalidate(stockCountsProvider);
  }
}

/// A count in progress, kept on the device so leaving the screen (a call,
/// another app) does not lose it: what was counted, when, and the note.
class CountDraft {
  const CountDraft({
    this.counted = const {},
    this.countedAt = const {},
    this.note = '',
  });

  final Map<String, double> counted;
  final Map<String, DateTime> countedAt;
  final String note;

  bool get isEmpty => counted.isEmpty && note.trim().isEmpty;

  String encode() => jsonEncode({
    'note': note,
    'lines': {
      for (final e in counted.entries)
        e.key: {
          'c': e.value,
          if (countedAt[e.key] case final DateTime at)
            'at': at.toIso8601String(),
        },
    },
  });

  static CountDraft decode(String? json) {
    if (json == null || json.isEmpty) return const CountDraft();
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final counted = <String, double>{};
      final at = <String, DateTime>{};
      for (final e in (m['lines'] as Map<String, dynamic>? ?? {}).entries) {
        final l = e.value as Map<String, dynamic>;
        final c = (l['c'] as num?)?.toDouble();
        if (c == null || c < 0) continue;
        counted[e.key] = c;
        if (DateTime.tryParse(l['at'] as String? ?? '') case final DateTime t) {
          at[e.key] = t;
        }
      }
      return CountDraft(
        counted: counted,
        countedAt: at,
        note: m['note'] as String? ?? '',
      );
    } catch (_) {
      return const CountDraft();
    }
  }
}

/// Where a person's count in progress for a site is kept.
String countDraftKey(String userId, String siteId) =>
    'count_draft_${userId}_$siteId';

/// A saved stock count, newest first in [stockCountsProvider].
typedef StockCountSummary = ({
  String id,
  String siteId,
  String? note,
  int items,
  int differences,
  DateTime at,
  String by,
});

/// One counted item whose count differed from stock on hand.
typedef StockCountLine = ({
  String code,
  String name,
  String unit,
  double expected,
  double counted,
});

/// Past stock counts for the site filter (or every site), newest first.
final stockCountsProvider = FutureProvider.autoDispose<List<StockCountSummary>>(
  (ref) async {
    final filter = ref.watch(siteFilterProvider);
    if (filter == null && !ref.watch(allSitesProvider)) return const [];
    var q = ref
        .watch(supabaseProvider)
        .from('stock_counts')
        .select(
          'id, site_id, note, items, differences, created_at, '
          'profiles(full_name)',
        );
    if (filter != null) q = q.eq('site_id', filter);
    final rows = await q.order('created_at', ascending: false).limit(100);
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          siteId: r['site_id'] as String,
          note: r['note'] as String?,
          items: r['items'] as int,
          differences: r['differences'] as int,
          at: DateTime.parse(r['created_at'] as String).toLocal(),
          by: (r['profiles'] as Map?)?['full_name'] as String? ?? '',
        ),
    ];
  },
);

/// The lines of one count that differed, largest difference first.
final stockCountLinesProvider = FutureProvider.autoDispose
    .family<List<StockCountLine>, String>((ref, countId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('stock_count_lines')
          .select('expected, counted, store_items(code, name, unit)')
          .eq('count_id', countId);
      final lines = [
        for (final r in rows)
          if ((r['expected'] as num) != (r['counted'] as num))
            (
              code: (r['store_items'] as Map)['code'] as String,
              name: (r['store_items'] as Map)['name'] as String,
              unit: (r['store_items'] as Map)['unit'] as String,
              expected: (r['expected'] as num).toDouble(),
              counted: (r['counted'] as num).toDouble(),
            ),
      ];
      lines.sort(
        (a, b) => (b.counted - b.expected).abs().compareTo(
          (a.counted - a.expected).abs(),
        ),
      );
      return lines;
    });
