import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';

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

/// 12.5 → "12.5", 12.0 → "12".
String qtyText(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

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
}

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

/// The current site's items, by name (online).
final storeItemsProvider = FutureProvider<List<StoreItem>>((ref) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('store_items')
      .select()
      .eq('site_id', site)
      .eq('is_archived', false)
      .order('name');
  return [for (final r in rows) StoreItem.fromJson(r)];
});

final storeItemProvider = FutureProvider.autoDispose.family<StoreItem?, String>(
  (ref, id) async {
    final row = await ref
        .watch(supabaseProvider)
        .from('store_items')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : StoreItem.fromJson(row);
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
}
