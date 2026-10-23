import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../data/local_db.dart';
import '../data/permission_set.dart';
import 'core_providers.dart';

/// Who is signed in and what they may do: profile, permissions, sites and
/// areas. Loaded after sign-in and cached on the device (API.md section 5).
class SessionState {
  const SessionState({
    this.profile,
    this.permissions,
    this.sites = const [],
    this.areas = const [],
    this.loading = false,
    this.refreshed = false,
    this.error,
  });

  final LocalProfile? profile;
  final PermissionSet? permissions;
  final List<LocalSite> sites;
  final List<LocalArea> areas;
  final bool loading;

  /// True once a refresh from Supabase has succeeded this session.
  final bool refreshed;

  /// Set when the latest refresh failed; cached data is still shown.
  final AppError? error;

  PermissionSet get perms => permissions ?? PermissionSet.empty();

  bool can(String code, {String? siteId}) => perms.can(code, siteId: siteId);

  /// Unarchived sites where the user holds at least one permission.
  List<LocalSite> get mySites => [
    for (final s in sites)
      if (!s.isArchived && perms.hasAnyAt(s.id)) s,
  ];

  LocalSite? siteById(String? id) {
    for (final s in sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<LocalArea> areasAt(String siteId) => [
    for (final a in areas)
      if (a.siteId == siteId && !a.isArchived) a,
  ];

  SessionState copyWith({
    bool? loading,
    bool? refreshed,
    AppError? error,
    bool clearError = false,
  }) {
    return SessionState(
      profile: profile,
      permissions: permissions,
      sites: sites,
      areas: areas,
      loading: loading ?? this.loading,
      refreshed: refreshed ?? this.refreshed,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<SessionState> {
  LocalDb get _db => ref.read(localDbProvider);

  @override
  SessionState build() {
    final userId = ref.watch(authUserIdProvider);
    if (userId == null) {
      unawaited(_db.clearAll());
      return const SessionState();
    }
    Future.microtask(() => _load(userId));
    return const SessionState(loading: true);
  }

  /// Shows cached data at once, then refreshes from Supabase.
  Future<void> _load(String userId) async {
    final cached = await _readCache(userId);
    if (!ref.mounted) return;
    if (cached != null) state = cached.copyWith(loading: true);
    await refresh();
  }

  Future<void> refresh() async {
    final userId = ref.read(authUserIdProvider);
    if (userId == null) return;
    final client = ref.read(supabaseProvider);

    state = state.copyWith(loading: true);
    try {
      final results = await Future.wait<dynamic>([
        client.from('profiles').select().eq('id', userId).maybeSingle(),
        client.rpc('my_permissions'),
        client.from('sites').select().order('name'),
        client.from('areas').select().order('name'),
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
      final fresh = await _readCache(userId);
      if (!ref.mounted || ref.read(authUserIdProvider) != userId) return;
      state = (fresh ?? const SessionState()).copyWith(refreshed: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: AppError.from(e));
    }
  }

  /// Reads the cache, or null if it is empty or belongs to another user.
  Future<SessionState?> _readCache(String userId) async {
    final profile = await _db.select(_db.localProfiles).getSingleOrNull();
    if (profile == null) return null;
    if (profile.id != userId) {
      await _db.clearAll();
      return null;
    }
    return SessionState(
      profile: profile,
      permissions: PermissionSet(
        (await _db.select(_db.localPermissions).get()).map(
          (p) => (code: p.code, siteId: p.siteId),
        ),
      ),
      sites: await (_db.select(
        _db.localSites,
      )..orderBy([(s) => OrderingTerm.asc(s.name)])).get(),
      areas: await (_db.select(
        _db.localAreas,
      )..orderBy([(a) => OrderingTerm.asc(a.name)])).get(),
    );
  }
}

/// The site the user picked in the site picker, or null for the default.
final pickedSiteIdProvider = NotifierProvider<PickedSiteNotifier, String?>(
  PickedSiteNotifier.new,
);

class PickedSiteNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authUserIdProvider);
    return null;
  }

  void pick(String siteId) => state = siteId;
}

/// The site screens work in: the picked site, else the home site, else the
/// first site the user has access to.
final currentSiteProvider = Provider<LocalSite?>((ref) {
  final session = ref.watch(sessionProvider);
  final mine = session.mySites;
  if (mine.isEmpty) return null;
  final picked = ref.watch(pickedSiteIdProvider);
  final homeId = session.profile?.homeSiteId;
  for (final id in [picked, homeId]) {
    for (final s in mine) {
      if (s.id == id) return s;
    }
  }
  return mine.first;
});
