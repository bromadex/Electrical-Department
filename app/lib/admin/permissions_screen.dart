import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../services/core_providers.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// Roles, every permission, and which role has which (admin.users only, by
/// the tables' own rules).
typedef PermissionGrid = ({
  List<({String id, String name})> roles,
  List<({String code, String description})> permissions,
  Set<(String, String)> granted,
});

final permissionGridProvider = FutureProvider.autoDispose<PermissionGrid>((
  ref,
) async {
  final db = ref.watch(supabaseProvider);
  final (roles, permissions, grants) = await (
    db.from('roles').select('id, name').eq('is_archived', false).order('name'),
    db
        .from('permissions')
        .select('code, description')
        .eq('is_archived', false)
        .order('code'),
    db
        .from('role_permissions')
        .select('role_id, permission_code')
        .eq('is_archived', false),
  ).wait;
  return (
    roles: [
      for (final r in roles) (id: r['id'] as String, name: r['name'] as String),
    ],
    permissions: [
      for (final p in permissions)
        (
          code: p['code'] as String,
          description: p['description'] as String? ?? '',
        ),
    ],
    granted: {
      for (final g in grants)
        (g['role_id'] as String, g['permission_code'] as String),
    },
  );
});

/// The area a permission belongs to, from its code ("jc.view" → "jc").
String permissionArea(String code) => switch (code.split('.').first) {
  'jc' || 'jobs' || 'req' => 'Job cards and requests',
  'tools' || 'assets' => 'Tools and equipment',
  'store' || 'mr' || 'po' => 'Inventory and purchases',
  'docs' || 'checklists' || 'reports' => 'Documents, checklists, reports',
  'chat' || 'meetings' => 'Chat and meetings',
  'projects' || 'stats' || 'audit' => 'Projects and statistics',
  _ => 'Administration',
};

/// Which permissions each role has. Changes save straight away and reach
/// people when their app next loads their permissions (or on Reload).
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  String? _role;
  final _saving = <String>{};

  Future<void> _toggle(
    String roleId,
    String roleName,
    String code,
    bool on,
  ) async {
    if (!on && roleName == 'Admin' && code == 'admin.users') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Admin keeps admin.users, or nobody could manage people',
          ),
        ),
      );
      return;
    }
    setState(() => _saving.add(code));
    try {
      await ref.read(supabaseProvider).from('role_permissions').upsert({
        'role_id': roleId,
        'permission_code': code,
        'is_archived': !on,
      }, onConflict: 'role_id,permission_code');
      ref.invalidate(permissionGridProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppError.from(e).message)));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grid = ref.watch(permissionGridProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const Text('Roles and permissions'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: grid.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: EmptyState(
              icon: CupertinoIcons.lock,
              title: 'Could not load permissions',
              message: AppError.from(e).message,
            ),
          ),
          data: (g) {
            final role = g.roles
                .where((r) => r.id == (_role ?? g.roles.firstOrNull?.id))
                .firstOrNull;
            final areas = <String, List<({String code, String description})>>{};
            for (final p in g.permissions) {
              (areas[permissionArea(p.code)] ??= []).add(p);
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(
                Space.md,
                top + Space.md,
                Space.md,
                Space.xl,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Pick a role, then switch what it may do. People '
                          'get the change when their app reloads.',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.xs,
                          runSpacing: Space.xs,
                          children: [
                            for (final r in g.roles)
                              ChoiceChip(
                                label: Text(
                                  '${r.name} · '
                                  '${g.granted.where((x) => x.$1 == r.id).length}',
                                ),
                                selected: r.id == role?.id,
                                onSelected: (_) => setState(() => _role = r.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.md),
                        if (role != null)
                          for (final a in areas.entries) ...[
                            Panel(
                              title: a.key,
                              child: Column(
                                children: [
                                  for (final p in a.value)
                                    SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(p.description),
                                      subtitle: Text(p.code),
                                      value: g.granted.contains((
                                        role.id,
                                        p.code,
                                      )),
                                      onChanged: _saving.contains(p.code)
                                          ? null
                                          : (on) => _toggle(
                                              role.id,
                                              role.name,
                                              p.code,
                                              on,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Space.sm),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
