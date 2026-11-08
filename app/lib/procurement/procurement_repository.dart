import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../projects/projects_repository.dart' show isoDay;
import '../services/core_providers.dart';
import '../services/session_controller.dart';

/// Material requests, purchases and BOQs (API.md section 19).

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _ts(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

const mrStatuses = {
  'pending': 'Waiting for approval',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'part_issued': 'Partly issued',
  'issued': 'Issued',
  'cancelled': 'Cancelled',
};

const poStatuses = {
  'requested': 'To order',
  'ordered': 'Ordered',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
};

/// A line on a request, a purchase or a BOQ: a store item, or something
/// not stocked.
class OrderLine {
  OrderLine.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      itemId = j['item_id'] as String?,
      itemCode = (j['item'] as Map?)?['code'] as String?,
      description = j['description'] as String? ?? '',
      unit = j['unit'] as String? ?? 'pcs',
      qty = _num(j['qty']),
      done = _num(j['issued_qty'] ?? j['received_qty']),
      unitPrice = (j['unit_price'] as num?)?.toDouble(),
      mrLineId = j['mr_line_id'] as String?;

  final String id;
  final String? itemId;
  final String? itemCode;
  final String description;
  final String unit;
  final double qty;

  /// Issued (on a request) or received (on a purchase).
  final double done;
  final double? unitPrice;
  final String? mrLineId;

  double get left => (qty - done).clamp(0, double.infinity);
  bool get stocked => itemId != null;
}

class MaterialRequest {
  MaterialRequest.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      jobCardId = j['job_card_id'] as String?,
      jobCardNumber = (j['job_card'] as Map?)?['number'] as String?,
      projectId = j['project_id'] as String?,
      projectCode = (j['project'] as Map?)?['code'] as String?,
      requestedBy = j['requested_by'] as String?,
      neededBy = j['needed_by'] == null
          ? null
          : DateTime.parse(j['needed_by'] as String),
      note = j['note'] as String?,
      status = j['status'] as String,
      decidedBy = j['decided_by'] as String?,
      decisionNote = j['decision_note'] as String?,
      createdAt = _ts(j['created_at'])!,
      lines = [
        for (final l in (j['lines'] as List? ?? const []))
          OrderLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ];

  final String id;
  final String siteId;
  final String code;
  final String? jobCardId;
  final String? jobCardNumber;
  final String? projectId;
  final String? projectCode;
  final String? requestedBy;
  final DateTime? neededBy;
  final String? note;
  final String status;
  final String? decidedBy;
  final String? decisionNote;
  final DateTime createdAt;
  final List<OrderLine> lines;

  bool get canIssue => status == 'approved' || status == 'part_issued';

  /// What it is for: a job card, a project, or the site.
  String get forWhat => [?jobCardNumber, ?projectCode].join(' · ').isEmpty
      ? 'General'
      : [?jobCardNumber, ?projectCode].join(' · ');
}

class PurchaseOrder {
  PurchaseOrder.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      siteId = j['site_id'] as String,
      code = j['code'] as String,
      supplierName = (j['supplier'] as Map?)?['name'] as String?,
      poNumber = j['po_number'] as String?,
      status = j['status'] as String,
      expectedDate = j['expected_date'] == null
          ? null
          : DateTime.parse(j['expected_date'] as String),
      note = j['note'] as String?,
      createdAt = _ts(j['created_at'])!,
      lines = [
        for (final l in (j['lines'] as List? ?? const []))
          OrderLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ];

  final String id;
  final String siteId;
  final String code;
  final String? supplierName;
  final String? poNumber;
  final String status;
  final DateTime? expectedDate;
  final String? note;
  final DateTime createdAt;
  final List<OrderLine> lines;

  bool get open => status == 'requested' || status == 'ordered';

  double get total => lines.fold(0, (t, l) => t + (l.unitPrice ?? 0) * l.qty);
}

/// A BOQ line against what was issued, requested, ordered and in stock.
class BoqLine {
  BoqLine.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      itemId = j['item_id'] as String?,
      description = j['description'] as String,
      unit = j['unit'] as String,
      qty = _num(j['qty']),
      issued = _num(j['issued']),
      requested = _num(j['requested']),
      onOrder = _num(j['on_order']),
      inStock = _num(j['in_stock']),
      stillNeeded = _num(j['still_needed']),
      toRequest = _num(j['to_request']);

  final String id;
  final String? itemId;
  final String description;
  final String unit;
  final double qty;
  final double issued;
  final double requested;
  final double onOrder;
  final double inStock;
  final double stillNeeded;
  final double toRequest;
}

/// Reads BOQ lines pasted from a spreadsheet or a CSV file: one line per
/// row, "description, unit, quantity" (tabs, commas or semicolons). A
/// header row and rows without a quantity are skipped.
List<({String description, String unit, double qty})> parseBoq(String text) {
  final out = <({String description, String unit, double qty})>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final sep = line.contains('\t')
        ? '\t'
        : line.contains(';')
        ? ';'
        : ',';
    final cells = [
      for (final c in line.split(sep))
        c.trim().replaceAll(RegExp(r'^"|"$'), ''),
    ];
    if (cells.length < 2) continue;
    final qty = double.tryParse(
      cells.last.replaceAll(' ', '').replaceAll(',', '.'),
    );
    if (qty == null || qty <= 0) continue;
    final description = cells.first;
    if (description.length < 2) continue;
    final unit = cells.length >= 3 && cells[cells.length - 2].isNotEmpty
        ? cells[cells.length - 2]
        : 'pcs';
    out.add((description: description, unit: unit, qty: qty));
  }
  return out;
}

const _mrSelect =
    '*, job_card:job_cards(number), project:projects(code), '
    'lines:mr_lines(*, item:store_items(code))';
const _poSelect =
    '*, supplier:suppliers(name), lines:po_lines(*, item:store_items(code))';

/// Requests at the current site, newest first; with [projectId], only that
/// project's.
final materialRequestsProvider = FutureProvider.autoDispose
    .family<List<MaterialRequest>, String?>((ref, projectId) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      if (site == null) return const [];
      var q = ref
          .watch(supabaseProvider)
          .from('material_requests')
          .select(_mrSelect)
          .eq('site_id', site);
      if (projectId != null) q = q.eq('project_id', projectId);
      final rows = await q.order('created_at', ascending: false).limit(200);
      return [for (final r in rows) MaterialRequest.fromJson(r)];
    });

final materialRequestProvider = FutureProvider.autoDispose
    .family<MaterialRequest?, String>((ref, id) async {
      final row = await ref
          .watch(supabaseProvider)
          .from('material_requests')
          .select(_mrSelect)
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : MaterialRequest.fromJson(row);
    });

final purchasesProvider = FutureProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) async {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('purchase_orders')
      .select(_poSelect)
      .eq('site_id', site)
      .order('created_at', ascending: false)
      .limit(200);
  return [for (final r in rows) PurchaseOrder.fromJson(r)];
});

final purchaseProvider = FutureProvider.autoDispose
    .family<PurchaseOrder?, String>((ref, id) async {
      final row = await ref
          .watch(supabaseProvider)
          .from('purchase_orders')
          .select(_poSelect)
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : PurchaseOrder.fromJson(row);
    });

final suppliersProvider =
    FutureProvider.autoDispose<List<({String id, String name})>>((ref) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('suppliers')
          .select('id, name')
          .eq('is_archived', false)
          .order('name');
      return [
        for (final r in rows)
          (id: r['id'] as String, name: r['name'] as String),
      ];
    });

final boqProvider = FutureProvider.autoDispose.family<List<BoqLine>, String>((
  ref,
  projectId,
) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('boq_status')
      .select()
      .eq('project_id', projectId)
      .order('description');
  return [for (final r in rows) BoqLine.fromJson(r)];
});

/// A line being written on a new request or purchase.
typedef DraftLine = ({
  String? itemId,
  String description,
  String unit,
  double qty,
  double? unitPrice,
  String? mrLineId,
});

final procurementActionsProvider = Provider((ref) => ProcurementActions(ref));

/// Requests queue offline; approving, issuing, ordering and receiving are
/// online so a refusal ("already approved", "only 3 left") is shown.
class ProcurementActions {
  ProcurementActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) =>
      _ref.read(supabaseProvider).rpc(fn, params: params);

  void _reload({String? mr, String? po, String? project}) {
    _ref.invalidate(materialRequestsProvider);
    _ref.invalidate(purchasesProvider);
    if (mr != null) _ref.invalidate(materialRequestProvider(mr));
    if (po != null) _ref.invalidate(purchaseProvider(po));
    if (project != null) _ref.invalidate(boqProvider(project));
  }

  List<Map<String, dynamic>> _lines(List<DraftLine> lines) => [
    for (final l in lines)
      {
        'item_id': l.itemId,
        'description': l.description,
        'unit': l.unit,
        'qty': l.qty,
        'unit_price': l.unitPrice,
        'mr_line_id': l.mrLineId,
      },
  ];

  Future<String> createRequest({
    required String siteId,
    String? jobCardId,
    String? projectId,
    DateTime? neededBy,
    String? note,
    required List<DraftLine> lines,
  }) async {
    final id = _uuid.v4();
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue(
      'fn_create_mr',
      {
        'p_client_ref': id,
        'p_site': siteId,
        'p_job_card': jobCardId,
        'p_project': projectId,
        'p_needed_by': neededBy == null ? null : isoDay(neededBy),
        'p_note': note?.trim(),
        'p_lines': _lines(lines),
      },
      clientRef: id,
      flushNow: false,
    );
    await outbox.flush();
    _reload(project: projectId);
    return id;
  }

  Future<void> decide(MaterialRequest r, bool approve, String? note) async {
    await _rpc('fn_decide_mr', {
      'p_mr': r.id,
      'p_approve': approve,
      'p_note': note?.trim(),
    });
    _reload(mr: r.id);
  }

  Future<void> issue(MaterialRequest r, Map<String, double> qtyByLine) async {
    await _rpc('fn_issue_mr', {
      'p_client_ref': _uuid.v4(),
      'p_mr': r.id,
      'p_lines': [
        for (final e in qtyByLine.entries)
          if (e.value > 0) {'line_id': e.key, 'qty': e.value},
      ],
    });
    _reload(mr: r.id, project: r.projectId);
  }

  Future<void> cancel(MaterialRequest r) async {
    await _rpc('fn_cancel_mr', {'p_mr': r.id});
    _reload(mr: r.id, project: r.projectId);
  }

  Future<String> saveSupplier(
    String siteId,
    String name, {
    String? phone,
  }) async {
    final id = _uuid.v4();
    await _rpc('fn_save_supplier', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_name': name.trim(),
      'p_contact': null,
      'p_phone': phone?.trim(),
      'p_email': null,
      'p_archived': false,
    });
    _ref.invalidate(suppliersProvider);
    return id;
  }

  Future<String> createPurchase({
    required String siteId,
    String? supplierId,
    String? poNumber,
    DateTime? expected,
    String? note,
    required List<DraftLine> lines,
  }) async {
    final id = _uuid.v4();
    await _rpc('fn_create_po', {
      'p_client_ref': id,
      'p_site': siteId,
      'p_supplier': supplierId,
      'p_po_number': poNumber?.trim(),
      'p_expected': expected == null ? null : isoDay(expected),
      'p_note': note?.trim(),
      'p_lines': _lines(lines),
    });
    _reload(po: id);
    for (final l in lines) {
      if (l.mrLineId != null) _ref.invalidate(materialRequestProvider);
    }
    return id;
  }

  Future<void> setPurchaseStatus(
    PurchaseOrder o,
    String status, {
    String? poNumber,
    DateTime? expected,
  }) async {
    await _rpc('fn_set_po_status', {
      'p_po': o.id,
      'p_status': status,
      'p_po_number': poNumber?.trim(),
      'p_expected': expected == null ? null : isoDay(expected),
    });
    _reload(po: o.id);
  }

  Future<void> receive(
    PurchaseOrder o,
    Map<String, double> qtyByLine, {
    String? note,
  }) async {
    await _rpc('fn_receive_po', {
      'p_client_ref': _uuid.v4(),
      'p_po': o.id,
      'p_lines': [
        for (final e in qtyByLine.entries)
          if (e.value > 0) {'line_id': e.key, 'qty': e.value},
      ],
      'p_note': note?.trim(),
    });
    _reload(po: o.id);
    _ref.invalidate(materialRequestProvider);
  }

  Future<int> importBoq(
    String projectId,
    List<({String description, String unit, double qty})> lines, {
    bool replace = false,
  }) async {
    final n = await _rpc('fn_import_boq', {
      'p_project': projectId,
      'p_lines': [
        for (final l in lines)
          {'description': l.description, 'unit': l.unit, 'qty': l.qty},
      ],
      'p_replace': replace,
    });
    _reload(project: projectId);
    return (n as num).toInt();
  }

  /// The BOQ's shortfall as one request; null when nothing is short.
  Future<String?> shortfallToRequest(String projectId) async {
    final id = _uuid.v4();
    final r = await _rpc('fn_boq_shortfall_to_mr', {
      'p_client_ref': id,
      'p_project': projectId,
      'p_needed_by': null,
    });
    _reload(project: projectId);
    // A null record comes back as an object of nulls.
    return r == null || (r is Map && r['id'] == null) ? null : id;
  }
}
