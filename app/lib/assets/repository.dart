import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../jobcards/models.dart' show PagedResult;
import '../services/core_providers.dart';
import 'models.dart';

const _select =
    '*, category:asset_categories(name), area:areas(name), site:sites(code, name)';

String _clean(String s) => s.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();

/// Bumped after this device saves an asset.
final assetsRevisionProvider = NotifierProvider<AssetsRevision, int>(
  AssetsRevision.new,
);

class AssetsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final assetsPageProvider = FutureProvider.autoDispose
    .family<PagedResult<Asset>, AssetFilter>((ref, f) async {
      ref.watch(assetsRevisionProvider);
      final client = ref.watch(supabaseProvider);
      var q = client.from('assets').select(_select).eq('is_archived', false);
      if (f.siteId != null) q = q.eq('site_id', f.siteId!);
      if (f.categoryId != null) q = q.eq('category_id', f.categoryId!);
      if (f.status != null) q = q.eq('operational_status', f.status!);
      final s = _clean(f.search);
      if (s.isNotEmpty) {
        q = q.or(
          'asset_no.ilike.*$s*,name.ilike.*$s*,serial_no.ilike.*$s*,location.ilike.*$s*,manufacturer.ilike.*$s*',
        );
      }
      final from = f.page * AssetFilter.pageSize;
      final res = await q
          .order('asset_no', ascending: true)
          .range(from, from + AssetFilter.pageSize - 1)
          .count(CountOption.exact);
      return PagedResult([for (final r in res.data) Asset(r)], res.count);
    });

final assetProvider = FutureProvider.autoDispose.family<Asset, String>((
  ref,
  id,
) async {
  ref.watch(assetsRevisionProvider);
  final row = await ref
      .watch(supabaseProvider)
      .from('assets')
      .select(_select)
      .eq('id', id)
      .maybeSingle();
  if (row == null) {
    throw const AppError(
      'NOT_FOUND',
      'Equipment not found, or you cannot see it.',
    );
  }
  return Asset(row);
});

/// Equipment at a site matching a search (for pickers).
final assetLookupProvider = FutureProvider.autoDispose
    .family<List<Asset>, (String, String)>((ref, args) async {
      final (siteId, query) = args;
      var q = ref
          .watch(supabaseProvider)
          .from('assets')
          .select(_select)
          .eq('site_id', siteId)
          .eq('is_archived', false);
      final s = _clean(query);
      if (s.isNotEmpty) {
        q = q.or('asset_no.ilike.*$s*,name.ilike.*$s*,location.ilike.*$s*');
      }
      final rows = await q.order('asset_no', ascending: true).limit(30);
      return [for (final r in rows) Asset(r)];
    });

final assetActionsProvider = Provider<AssetActions>(AssetActions.new);

class AssetActions {
  AssetActions(this._ref);

  final Ref _ref;

  static String? _t(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
  static String? _d(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String> save({
    String? id,
    required String siteId,
    String? areaId,
    required String assetNo,
    required String name,
    String? categoryId,
    String? location,
    String? manufacturer,
    String? model,
    String? serialNo,
    String? rating,
    num? voltage,
    num? current,
    num? power,
    DateTime? installedOn,
    required String status,
    required String criticality,
    String? departmentId,
    String? maintenanceFrequency,
    DateTime? warrantyExpiresOn,
    String? warrantyNotes,
    String? notes,
    bool archived = false,
  }) async {
    try {
      final row = await _ref
          .read(supabaseProvider)
          .rpc(
            'fn_save_asset',
            params: {
              'p_id': id ?? const Uuid().v4(),
              'p_site': siteId,
              'p_area': areaId,
              'p_asset_no': assetNo.trim(),
              'p_name': name.trim(),
              'p_category': categoryId,
              'p_location': _t(location),
              'p_manufacturer': _t(manufacturer),
              'p_model': _t(model),
              'p_serial_no': _t(serialNo),
              'p_rating': _t(rating),
              'p_voltage_v': voltage,
              'p_current_a': current,
              'p_power_kw': power,
              'p_installed_on': _d(installedOn),
              'p_status': status,
              'p_criticality': criticality,
              'p_department': departmentId,
              'p_maintenance_frequency': _t(maintenanceFrequency),
              'p_warranty_expires_on': _d(warrantyExpiresOn),
              'p_warranty_notes': _t(warrantyNotes),
              'p_notes': _t(notes),
              'p_archived': archived,
            },
          );
      _ref.read(assetsRevisionProvider.notifier).bump();
      return (row as Map)['id'] as String;
    } catch (e) {
      throw AppError.from(e);
    }
  }
}
