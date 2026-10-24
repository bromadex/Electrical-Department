import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_db.dart';
import '../reference/reference_data.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/data_table.dart';
import '../ui/format.dart';
import '../ui/page.dart';
import 'repository.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.perms.canEverywhere('admin.users')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Administrators only',
        message: 'Only a system administrator can manage users.',
      );
    }
    final users = ref.watch(adminUsersProvider);
    final data = ref.watch(referenceDataProvider).value;
    String siteCode(String? id) =>
        id == null ? 'All sites' : session.siteById(id)?.code ?? '?';

    return AppPage(
      title: 'User Management',
      subtitle: 'Accounts, roles and access by site',
      actions: [
        FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _UserDialog(),
          ),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Add user'),
        ),
      ],
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: AsyncView(
          value: users,
          onRetry: () => ref.invalidate(adminUsersProvider),
          data: (list) => PagedTable<AdminUser>(
            rows: list,
            total: list.length,
            page: 0,
            pageSize: list.isEmpty ? 1 : list.length,
            onPage: (_) {},
            onTap: (u) => showDialog<void>(
              context: context,
              builder: (_) => _UserDialog(user: u),
            ),
            highlight: (u) =>
                u.active ? null : AppColors.neutral.withValues(alpha: 0.08),
            cardBuilder: (u) => Card(
              child: ListTile(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _UserDialog(user: u),
                ),
                leading: AppAvatar(
                  name: u.fullName.isEmpty ? u.email : u.fullName,
                ),
                title: Text(u.fullName.isEmpty ? u.email : u.fullName),
                subtitle: Text(
                  [
                    u.email,
                    ...u.roles.map(
                      (g) => '${g.roleName} (${siteCode(g.siteId)})',
                    ),
                  ].join('\n'),
                ),
                trailing: u.active
                    ? null
                    : const Pill(
                        label: 'Inactive',
                        dense: true,
                        color: AppColors.neutral,
                      ),
              ),
            ),
            columns: [
              TableCol(
                'Name',
                (u) => Text(u.fullName.isEmpty ? '—' : u.fullName),
              ),
              TableCol('Email', (u) => Text(u.email)),
              TableCol(
                'Roles',
                (u) => SizedBox(
                  width: 260,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final g in u.roles)
                        Pill(
                          label: '${g.roleName} · ${siteCode(g.siteId)}',
                          dense: true,
                        ),
                      if (u.roles.isEmpty)
                        const Pill(
                          label: 'No role',
                          dense: true,
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                ),
              ),
              TableCol(
                'Department',
                (u) => Text(data?.departmentName(u.departmentId) ?? '—'),
              ),
              TableCol(
                'Home site',
                (u) =>
                    Text(u.homeSiteId == null ? '—' : siteCode(u.homeSiteId)),
              ),
              TableCol(
                'Status',
                (u) => u.active
                    ? const Pill(
                        label: 'Active',
                        dense: true,
                        color: AppColors.success,
                      )
                    : const Pill(
                        label: 'Inactive',
                        dense: true,
                        color: AppColors.neutral,
                      ),
              ),
              TableCol(
                'Last sign-in',
                (u) => Text(
                  u.lastSignInAt == null
                      ? 'Never'
                      : fmtDateTime(u.lastSignInAt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add a user (with a temporary password) or edit one: profile, active
/// flag, roles per site and password reset.
class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.user});

  final AdminUser? user;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.user?.email);
  late final _name = TextEditingController(text: widget.user?.fullName);
  late final _phone = TextEditingController(text: widget.user?.phone);
  final _password = TextEditingController();
  late String? _departmentId = widget.user?.departmentId;
  late String? _homeSiteId = widget.user?.homeSiteId;
  late bool _active = widget.user?.active ?? true;
  late final List<RoleGrant> _roles = [...?widget.user?.roles];
  bool _busy = false;
  bool _showPassword = false;

  bool get _isNew => widget.user == null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_roles.isEmpty && !await _confirmNoRole()) return;
    setState(() => _busy = true);
    final admin = ref.read(adminActionsProvider);
    try {
      if (_isNew) {
        await admin.createUser(
          email: _email.text,
          fullName: _name.text,
          password: _password.text,
          phone: _phone.text,
          departmentId: _departmentId,
          homeSiteId: _homeSiteId,
          roles: _roles,
        );
      } else {
        await admin.saveUser(
          id: widget.user!.id,
          fullName: _name.text,
          phone: _phone.text,
          departmentId: _departmentId,
          homeSiteId: _homeSiteId,
          active: _active,
          roles: _roles,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(
        context,
        _isNew
            ? 'User created; give them the temporary password in person'
            : 'User saved',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<bool> _confirmNoRole() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No role'),
          content: const Text(
            'Without a role this person can sign in but see nothing. Save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set a temporary password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (at least 8 characters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => controller.text.length >= 8
                ? Navigator.pop(context, controller.text)
                : null,
            child: const Text('Set password'),
          ),
        ],
      ),
    );
    if (password == null) return;
    try {
      await ref
          .read(adminActionsProvider)
          .resetPassword(widget.user!.id, password);
      if (mounted) {
        showSnack(context, 'Password changed; give it to the person in person');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final data = ref.watch(referenceDataProvider).value;
    final roles = ref.watch(rolesProvider).value ?? const <RoleInfo>[];
    final sites = session.sites.where((s) => !s.isArchived).toList();
    return AlertDialog(
      title: Text(
        _isNew
            ? 'Add user'
            : 'Edit ${widget.user!.fullName.isEmpty ? widget.user!.email : widget.user!.fullName}',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  enabled: _isNew,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                  validator: (v) =>
                      (v == null ||
                          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(v.trim()))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter the full name'
                      : null,
                ),
                if (_isNew) ...[
                  const SizedBox(height: Space.sm),
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Temporary password *',
                      helperText: 'At least 8 characters. Give it to the person in person.',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Hide' : 'Show',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'At least 8 characters'
                        : null,
                  ),
                ],
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<String?>(
                  initialValue: _departmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final d
                        in data?.activeDepartments ?? const <Department>[])
                      DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<String?>(
                  initialValue: _homeSiteId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Home site'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final s in sites)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _homeSiteId = v),
                ),
                if (!_isNew)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text(
                      'Inactive people cannot see or change anything',
                    ),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                const SectionHeader('Roles'),
                for (final (i, g) in _roles.indexed)
                  _RoleRow(
                    key: ObjectKey(g),
                    grant: g,
                    roles: roles,
                    sites: sites,
                    onChanged: (n) => setState(() => _roles[i] = n),
                    onRemove: () => setState(() => _roles.removeAt(i)),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: roles.isEmpty
                        ? null
                        : () => setState(
                            () => _roles.add(
                              RoleGrant(
                                roles.first.id,
                                roles.first.name,
                                sites.isEmpty ? null : sites.first.id,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add role'),
                  ),
                ),
                if (!_isNew)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _resetPassword,
                      icon: const Icon(Icons.password_rounded),
                      label: const Text('Set a temporary password'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isNew ? 'Create user' : 'Save'),
        ),
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    super.key,
    required this.grant,
    required this.roles,
    required this.sites,
    required this.onChanged,
    required this.onRemove,
  });

  final RoleGrant grant;
  final List<RoleInfo> roles;
  final List<LocalSite> sites;
  final ValueChanged<RoleGrant> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: roles.any((r) => r.id == grant.roleId)
                  ? grant.roleId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Role',
              ),
              items: [
                for (final r in roles)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) {
                final r = roles.firstWhere((x) => x.id == v);
                onChanged(RoleGrant(r.id, r.name, grant.siteId));
              },
            ),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              initialValue: grant.siteId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Site',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All sites')),
                for (final s in sites)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) =>
                  onChanged(RoleGrant(grant.roleId, grant.roleName, v)),
            ),
          ),
          IconButton(
            tooltip: 'Remove role',
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}
