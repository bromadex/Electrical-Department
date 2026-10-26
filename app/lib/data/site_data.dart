import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/core_providers.dart';
import '../services/session_controller.dart';
import 'app_error.dart';
import 'local_db.dart';

LocalAsset assetFromRow(Map<String, dynamic> r) => LocalAsset(
  id: r['id'] as String,
  siteId: r['site_id'] as String,
  areaId: r['area_id'] as String?,
  tag: r['tag'] as String,
  name: r['name'] as String,
  kind: r['kind'] as String?,
  makeModel: r['make_model'] as String?,
  serialNo: r['serial_no'] as String?,
  notes: r['notes'] as String?,
  status: r['operational_status'] as String? ?? 'in_service',
);

class SiteDataState {
  const SiteDataState({this.loading = false, this.error, this.synced = false});

  final bool loading;
  final AppError? error;
  final bool synced;
}

/// Keeps people's names and the current site's equipment register on the
/// device, so they show without signal. The app frame watches it; it
/// reloads when the site changes and after a pull to refresh.
final siteDataProvider = NotifierProvider<SiteDataNotifier, SiteDataState>(
  SiteDataNotifier.new,
);

class SiteDataNotifier extends Notifier<SiteDataState> {
  LocalDb get _db => ref.read(localDbProvider);
  SupabaseClient get _client => ref.read(supabaseProvider);
  String? _siteId;

  @override
  SiteDataState build() {
    final userId = ref.watch(authUserIdProvider);
    final site = ref.watch(currentSiteProvider.select((s) => s?.id));
    _siteId = site;
    if (userId == null || site == null) return const SiteDataState();
    Future.microtask(refresh);
    return const SiteDataState(loading: true);
  }

  Future<void> refresh() async {
    final site = _siteId;
    if (site == null) return;
    state = SiteDataState(loading: true, synced: state.synced);
    try {
      final results = await Future.wait<dynamic>([
        _client.from('profiles').select('id, full_name'),
        _client
            .from('assets')
            .select()
            .eq('site_id', site)
            .eq('is_archived', false)
            .order('tag'),
      ]);
      if (!ref.mounted || _siteId != site) return;
      await _db.transaction(() async {
        // The register is small: replace this site's copy outright.
        await (_db.delete(
          _db.localAssets,
        )..where((a) => a.siteId.equals(site))).go();
        await _db.batch((b) {
          b.insertAll(_db.localAssets, [
            for (final r in results[1] as List) assetFromRow(r),
          ]);
          b.insertAllOnConflictUpdate(_db.localPeople, [
            for (final p in results[0] as List)
              LocalPeopleCompanion.insert(
                id: p['id'] as String,
                fullName: (p['full_name'] as String?) ?? '',
              ),
          ]);
        });
      });
      state = const SiteDataState(synced: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = SiteDataState(error: AppError.from(e), synced: state.synced);
    }
  }
}

/// Everyone's display name by id.
final peopleProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(localDbProvider);
  return db
      .select(db.localPeople)
      .watch()
      .map((rows) => {for (final p in rows) p.id: p.fullName});
});

/// The equipment register at the current site, from the device copy.
final siteAssetsProvider = StreamProvider<List<LocalAsset>>((ref) {
  final site = ref.watch(currentSiteProvider.select((s) => s?.id));
  if (site == null) return Stream.value(const []);
  final db = ref.watch(localDbProvider);
  return (db.select(db.localAssets)
        ..where((a) => a.siteId.equals(site))
        ..orderBy([(a) => OrderingTerm(expression: a.tag)]))
      .watch();
});

final assetProvider = StreamProvider.family<LocalAsset?, String>((ref, id) {
  final db = ref.watch(localDbProvider);
  return (db.select(
    db.localAssets,
  )..where((a) => a.id.equals(id))).watchSingleOrNull();
});

/// Planned maintenance plans at the current site (online).
final recurrencesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final site = ref.watch(currentSiteProvider.select((s) => s?.id));
      if (site == null) return const [];
      final rows = await ref
          .watch(supabaseProvider)
          .from('job_recurrences')
          .select()
          .eq('site_id', site)
          .eq('is_archived', false)
          .order('next_run');
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    });

class Assignee {
  const Assignee(this.id, this.name, this.openJobs);

  final String id;
  final String name;
  final int openJobs;
}

/// People who can do the work at a site, with how much they hold.
final assigneesProvider = FutureProvider.autoDispose
    .family<List<Assignee>, String>((ref, siteId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc('fn_job_assignees', params: {'p_site': siteId});
      return [
        for (final r in rows as List)
          Assignee(
            r['id'] as String,
            (r['full_name'] as String?) ?? '',
            (r['open_jobs'] as num?)?.toInt() ?? 0,
          ),
      ];
    });

final siteActionsProvider = Provider<SiteActions>(SiteActions.new);

/// Saving equipment and maintenance plans. Both queue through the outbox,
/// so they work offline.
class SiteActions {
  SiteActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  LocalDb get _db => _ref.read(localDbProvider);

  Future<void> _queue(String action, Map<String, dynamic> payload) async {
    final outbox = _ref.read(outboxProvider);
    await outbox.enqueue(action, payload, flushNow: false);
    await outbox.flush();
    if (await outbox.isEmpty) {
      unawaited(_ref.read(siteDataProvider.notifier).refresh());
    }
  }

  Future<String> saveAsset({
    String? id,
    required String siteId,
    String? areaId,
    required String tag,
    required String name,
    String? kind,
    String? makeModel,
    String? serialNo,
    String? notes,
    bool archived = false,
  }) async {
    final ref = id ?? _uuid.v4();
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    if (archived) {
      await (_db.delete(_db.localAssets)..where((a) => a.id.equals(ref))).go();
    } else {
      await _db
          .into(_db.localAssets)
          .insertOnConflictUpdate(
            // A companion, so the status the server keeps is left alone.
            LocalAssetsCompanion.insert(
              id: ref,
              siteId: siteId,
              areaId: Value(areaId),
              tag: tag.trim().toUpperCase(),
              name: name.trim(),
              kind: Value(clean(kind)),
              makeModel: Value(clean(makeModel)),
              serialNo: Value(clean(serialNo)),
              notes: Value(clean(notes)),
            ),
          );
    }
    await _queue('fn_save_asset', {
      'p_client_ref': ref,
      'p_site': siteId,
      'p_area': areaId,
      'p_tag': tag.trim(),
      'p_name': name.trim(),
      'p_kind': clean(kind),
      'p_make_model': clean(makeModel),
      'p_serial_no': clean(serialNo),
      'p_notes': clean(notes),
      'p_archived': archived,
    });
    return ref;
  }

  /// [priority] is the plan's `low`, `normal` or `urgent`; job cards raised
  /// from it get P4, P3 or P2.
  Future<void> saveRecurrence({
    String? id,
    required String siteId,
    String? areaId,
    required String title,
    String? description,
    required String priority,
    required String every,
    required DateTime nextRun,
    required int dueDays,
    String? assigneeId,
    bool archived = false,
    String? assetId,
    bool isolationRequired = false,
  }) async {
    final ref = id ?? _uuid.v4();
    final d = nextRun;
    await _queue('fn_save_recurrence', {
      'p_client_ref': ref,
      'p_site': siteId,
      'p_area': areaId,
      'p_title': title.trim(),
      'p_description': description,
      'p_priority': priority,
      'p_every': every,
      'p_next_run':
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'p_due_days': dueDays,
      'p_assignee': assigneeId,
      'p_archived': archived,
      'p_asset': assetId,
      'p_isolation_required': isolationRequired,
    });
  }
}
