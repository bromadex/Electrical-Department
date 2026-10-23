import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../data/permission_set.dart';

/// Who is signed in and what they may do: profile, permissions, sites and
/// areas. Loaded after sign-in and cached on the device (API.md section 5).
class SessionController extends ChangeNotifier {
  SessionController(this._client, this._db);

  final SupabaseClient _client;
  final LocalDb _db;

  LocalProfile? profile;
  PermissionSet permissions = PermissionSet.empty();
  List<LocalSite> sites = const [];
  List<LocalArea> areas = const [];

  bool loading = false;

  /// Set when the latest refresh failed; cached data is still shown.
  AppError? error;

  /// True once a refresh from Supabase has succeeded this session.
  bool refreshed = false;

  bool can(String code, {String? siteId}) =>
      permissions.can(code, siteId: siteId);

  List<LocalSite> get activeSites => sites.where((s) => !s.isArchived).toList();

  LocalSite? siteById(String? id) {
    for (final s in sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Shows cached data at once, then refreshes from Supabase.
  Future<void> load() async {
    await _readCache();
    await refresh();
  }

  Future<void> refresh() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        _client.from('profiles').select().eq('id', userId).maybeSingle(),
        _client.rpc('my_permissions'),
        _client.from('sites').select().order('name'),
        _client.from('areas').select().order('name'),
      ]);

      final p = results[0] as Map<String, dynamic>?;
      await _db.replaceSession(
        profile: p == null
            ? null
            : LocalProfile(
                id: p['id'] as String,
                fullName: p['full_name'] as String? ?? '',
                phone: p['phone'] as String?,
                homeSiteId: p['home_site_id'] as String?,
                avatarUrl: p['avatar_url'] as String?,
                active: p['active'] as bool? ?? false,
              ),
        permissions: [
          for (final r in results[1] as List)
            LocalPermissionsCompanion.insert(
              code: r['code'] as String,
              siteId: Value(r['site_id'] as String?),
            ),
        ],
        sites: [
          for (final r in results[2] as List)
            LocalSite(
              id: r['id'] as String,
              code: r['code'] as String,
              name: r['name'] as String,
              isArchived: r['is_archived'] as bool? ?? false,
            ),
        ],
        areas: [
          for (final r in results[3] as List)
            LocalArea(
              id: r['id'] as String,
              siteId: r['site_id'] as String,
              name: r['name'] as String,
              isArchived: r['is_archived'] as bool? ?? false,
            ),
        ],
      );
      error = null;
      refreshed = true;
      await _readCache();
    } catch (e) {
      error = AppError.from(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    profile = null;
    permissions = PermissionSet.empty();
    sites = const [];
    areas = const [];
    error = null;
    refreshed = false;
    await _db.clearAll();
    notifyListeners();
  }

  Future<void> _readCache() async {
    final userId = _client.auth.currentUser?.id;
    final cachedProfile = await _db.select(_db.localProfiles).getSingleOrNull();
    if (cachedProfile != null && cachedProfile.id != userId) {
      // Cache belongs to someone else (e.g. sign-out never finished).
      await _db.clearAll();
      return;
    }
    profile = cachedProfile;
    permissions = PermissionSet(
      (await _db.select(_db.localPermissions).get()).map(
        (p) => (code: p.code, siteId: p.siteId),
      ),
    );
    sites = await (_db.select(
      _db.localSites,
    )..orderBy([(s) => OrderingTerm.asc(s.name)])).get();
    areas = await (_db.select(
      _db.localAreas,
    )..orderBy([(a) => OrderingTerm.asc(a.name)])).get();
    notifyListeners();
  }
}
