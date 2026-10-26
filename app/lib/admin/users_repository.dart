import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';

/// One role a person holds; [siteId] null means all sites.
typedef RoleGrant = ({String role, String? siteId});

/// A person as the users screen sees them (fn_admin_users, API.md section 9).
class AdminUser {
  AdminUser.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      email = (j['email'] as String?) ?? '',
      fullName = (j['full_name'] as String?) ?? '',
      phone = j['phone'] as String?,
      homeSiteId = j['home_site_id'] as String?,
      active = j['active'] as bool? ?? true,
      lastSignIn = DateTime.tryParse((j['last_sign_in_at'] as String?) ?? '')
          ?.toLocal(),
      roles = [
        for (final r in (j['roles'] as List? ?? const []))
          (role: (r as Map)['role'] as String, siteId: r['site_id'] as String?),
      ];

  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? homeSiteId;
  final bool active;
  final DateTime? lastSignIn;
  final List<RoleGrant> roles;

  String get displayName => fullName.isEmpty ? email : fullName;
}

/// Everyone, for system administrators. Online only: user management is
/// rare and must see the latest state.
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((
  ref,
) async {
  final rows = await ref.read(supabaseProvider).rpc('fn_admin_users') as List;
  return [for (final r in rows) AdminUser.fromJson(r as Map<String, dynamic>)];
});

/// Role names to choose from.
final roleNamesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final rows = await ref
      .read(supabaseProvider)
      .from('roles')
      .select('name')
      .eq('is_archived', false)
      .order('name');
  return [for (final r in rows) r['name'] as String];
});

final userAdminProvider = Provider((ref) => UserAdmin(ref));

class UserAdmin {
  UserAdmin(this._ref);

  final Ref _ref;

  SupabaseClient get _db => _ref.read(supabaseProvider);

  /// Creates a sign-in through the admin-users function; returns the new id.
  Future<String> create({
    required String email,
    required String fullName,
    required String password,
  }) async {
    final res = await _call({
      'action': 'create',
      'email': email.trim(),
      'full_name': fullName.trim(),
      'password': password,
    });
    return res['id'] as String;
  }

  Future<void> resetPassword(String userId, String password) => _call({
    'action': 'reset_password',
    'user_id': userId,
    'password': password,
  });

  Future<void> save({
    required String userId,
    required String fullName,
    required String? phone,
    required String? homeSiteId,
    required bool active,
    required List<RoleGrant> roles,
  }) async {
    try {
      await _db.rpc(
        'fn_set_user_profile',
        params: {
          'p_user': userId,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_home_site': homeSiteId,
          'p_active': active,
        },
      );
      await _db.rpc(
        'fn_set_user_roles',
        params: {
          'p_user': userId,
          'p_roles': [
            for (final r in roles) {'role': r.role, 'site_id': r.siteId},
          ],
        },
      );
    } catch (e) {
      throw AppError.from(e);
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke('admin-users', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final text = details is Map ? details['error'] as String? : null;
      final match = RegExp(r'^([A-Z_]+): (.+)$').firstMatch(text ?? '');
      if (match != null) throw AppError(match.group(1)!, match.group(2)!);
      throw AppError('SERVER', text ?? 'The account service failed.');
    } catch (e) {
      throw AppError.from(e);
    }
  }
}
