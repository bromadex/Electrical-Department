import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_error.dart';
import '../reference/reference_data.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../ui/format.dart';

class RoleGrant {
  const RoleGrant(this.roleId, this.roleName, this.siteId);

  final String roleId;
  final String roleName;

  /// Null = all sites.
  final String? siteId;
}

class AdminUser {
  AdminUser(Map<String, dynamic> r)
    : id = r['id'] as String,
      email = r['email'] as String? ?? '',
      fullName = r['full_name'] as String? ?? '',
      phone = r['phone'] as String?,
      departmentId = r['department_id'] as String?,
      homeSiteId = r['home_site_id'] as String?,
      active = r['active'] as bool? ?? false,
      lastSignInAt = parseTime(r['last_sign_in_at']),
      roles = [
        for (final g in (r['roles'] as List? ?? const []))
          RoleGrant(
            (g as Map)['role_id'] as String,
            g['role'] as String,
            g['site_id'] as String?,
          ),
      ];

  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? departmentId;
  final String? homeSiteId;
  final bool active;
  final DateTime? lastSignInAt;
  final List<RoleGrant> roles;
}

class RoleInfo {
  const RoleInfo(this.id, this.name);

  final String id;
  final String name;
}

/// Bumped after any administrative change, to reload the admin lists.
final adminRevisionProvider = NotifierProvider<AdminRevision, int>(
  AdminRevision.new,
);

class AdminRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((
  ref,
) async {
  ref.watch(adminRevisionProvider);
  final rows = await ref.watch(supabaseProvider).rpc('fn_admin_users');
  return [
    for (final r in rows as List) AdminUser(Map<String, dynamic>.from(r)),
  ];
});

final rolesProvider = FutureProvider.autoDispose<List<RoleInfo>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('roles')
      .select('id, name')
      .eq('is_archived', false)
      .order('name');
  return [
    for (final r in rows) RoleInfo(r['id'] as String, r['name'] as String),
  ];
});

final escalationContactsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(adminRevisionProvider);
      final rows = await ref
          .watch(supabaseProvider)
          .from('escalation_contacts')
          .select('*, person:profiles(full_name), site:sites(code, name)')
          .eq('is_archived', false)
          .order('priority_code');
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    });

final adminActionsProvider = Provider<AdminActions>(AdminActions.new);

class AdminActions {
  AdminActions(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  SupabaseClient get _client => _ref.read(supabaseProvider);
  static String? _t(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<dynamic> _rpc(
    String fn,
    Map<String, dynamic> params, {
    bool reference = false,
  }) async {
    try {
      final res = await _client.rpc(fn, params: params);
      _ref.read(adminRevisionProvider.notifier).bump();
      if (reference) _ref.invalidate(referenceDataProvider);
      return res;
    } catch (e) {
      throw AppError.from(e);
    }
  }

  Future<Map<String, dynamic>> _accounts(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('admin-users', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw AppError.from(e);
    }
  }

  /// Creates a sign-in (via the admin-users edge function, which holds the
  /// service key on the server), then sets the profile and roles.
  Future<void> createUser({
    required String email,
    required String fullName,
    required String password,
    String? phone,
    String? departmentId,
    String? homeSiteId,
    required List<RoleGrant> roles,
  }) async {
    final res = await _accounts({
      'action': 'create',
      'email': email.trim(),
      'full_name': fullName.trim(),
      'password': password,
    });
    final id = res['id'] as String;
    await saveUser(
      id: id,
      fullName: fullName,
      phone: phone,
      departmentId: departmentId,
      homeSiteId: homeSiteId,
      active: true,
      roles: roles,
    );
  }

  Future<void> resetPassword(String userId, String password) async {
    await _accounts({
      'action': 'reset_password',
      'user_id': userId,
      'password': password,
    });
  }

  Future<void> saveUser({
    required String id,
    required String fullName,
    String? phone,
    String? departmentId,
    String? homeSiteId,
    required bool active,
    required List<RoleGrant> roles,
  }) async {
    await _rpc('fn_set_user_profile', {
      'p_user': id,
      'p_full_name': fullName.trim(),
      'p_phone': _t(phone),
      'p_department': departmentId,
      'p_home_site': homeSiteId,
      'p_active': active,
    });
    await _rpc('fn_set_user_roles', {
      'p_user': id,
      'p_roles': [
        for (final g in roles) {'role_id': g.roleId, 'site_id': g.siteId},
      ],
    });
    if (id == _ref.read(authUserIdProvider)) {
      await _ref.read(sessionProvider.notifier).refresh();
    }
  }

  Future<void> saveSettings({
    required String timezone,
    required String jobcardPrefix,
    required String requestPrefix,
    required int numberDigits,
    required bool numberResetYearly,
    required String responseEndsAt,
    required int atRiskPercent,
    required int holdAlertHours,
    required bool handoverNoteRequired,
    required String companyName,
    required String departmentName,
    String? logoPath,
  }) => _rpc('fn_save_settings', {
    'p_timezone': timezone.trim(),
    'p_jobcard_prefix': jobcardPrefix.trim().toUpperCase(),
    'p_request_prefix': requestPrefix.trim().toUpperCase(),
    'p_number_digits': numberDigits,
    'p_number_reset_yearly': numberResetYearly,
    'p_response_ends_at': responseEndsAt,
    'p_at_risk_percent': atRiskPercent,
    'p_hold_alert_hours': holdAlertHours,
    'p_handover_note_required': handoverNoteRequired,
    'p_company_name': companyName.trim(),
    'p_department_name': departmentName.trim(),
    'p_logo_path': _t(logoPath),
  }, reference: true);

  Future<void> savePriority(
    String code, {
    required String name,
    String? description,
    required int responseMinutes,
    required int completionMinutes,
  }) => _rpc('fn_save_priority', {
    'p_code': code,
    'p_name': name.trim(),
    'p_description': _t(description),
    'p_response_minutes': responseMinutes,
    'p_completion_minutes': completionMinutes,
  }, reference: true);

  Future<void> saveDepartment({
    String? id,
    required String code,
    required String name,
    required bool isElectrical,
    bool archived = false,
  }) => _rpc('fn_save_department', {
    'p_id': id ?? _uuid.v4(),
    'p_code': code.trim().toUpperCase(),
    'p_name': name.trim(),
    'p_is_electrical': isElectrical,
    'p_archived': archived,
  }, reference: true);

  Future<void> saveJobCategory({
    String? id,
    required String name,
    String? description,
    int sortOrder = 100,
    bool archived = false,
  }) => _rpc('fn_save_job_category', {
    'p_id': id ?? _uuid.v4(),
    'p_name': name.trim(),
    'p_description': _t(description),
    'p_sort_order': sortOrder,
    'p_archived': archived,
  }, reference: true);

  Future<void> saveAssetCategory({
    String? id,
    required String name,
    int sortOrder = 100,
    bool archived = false,
  }) => _rpc('fn_save_asset_category', {
    'p_id': id ?? _uuid.v4(),
    'p_name': name.trim(),
    'p_sort_order': sortOrder,
    'p_archived': archived,
  }, reference: true);

  Future<void> saveEscalationContact({
    String? id,
    String? siteId,
    required String priority,
    required String userId,
    bool archived = false,
  }) => _rpc('fn_save_escalation_contact', {
    'p_id': id ?? _uuid.v4(),
    'p_site': siteId,
    'p_priority': priority,
    'p_user': userId,
    'p_archived': archived,
  });

  /// Work areas are simple rows written directly under row level security.
  Future<void> saveArea({
    String? id,
    required String siteId,
    required String name,
    bool archived = false,
  }) async {
    try {
      if (id == null) {
        await _client.from('areas').insert({
          'site_id': siteId,
          'name': name.trim(),
        });
      } else {
        await _client
            .from('areas')
            .update({'name': name.trim(), 'is_archived': archived})
            .eq('id', id);
      }
      await _ref.read(sessionProvider.notifier).refresh();
    } catch (e) {
      final err = AppError.from(e);
      throw err.message.contains('duplicate')
          ? const AppError(
              'INVALID',
              'That work area already exists at this site',
            )
          : err;
    }
  }
}
