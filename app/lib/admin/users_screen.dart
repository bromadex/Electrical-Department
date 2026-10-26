import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_error.dart';
import '../jobs/job_editor.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'users_repository.dart';

/// System administrators add people, set their roles per site, switch
/// accounts off and reset passwords.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminUsersProvider);
    final session = ref.watch(sessionProvider);
    final siteCodes = {for (final s in session.sites) s.id: s.code};
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('People'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFormSheet(context, const _NewUserForm()),
        icon: const Icon(CupertinoIcons.person_add),
        label: const Text('Add person'),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => ref.invalidate(adminUsersProvider),
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              children: [
                SizedBox(height: top + Space.xl),
                Center(
                  child: EmptyState(
                    icon: CupertinoIcons.wifi_slash,
                    title: 'Could not load people',
                    message: AppError.from(e).message,
                  ),
                ),
              ],
            ),
            data: (rows) {
              final q = _query.toLowerCase();
              final shown = [
                for (final u in rows)
                  if (q.isEmpty ||
                      u.displayName.toLowerCase().contains(q) ||
                      u.email.toLowerCase().contains(q))
                    u,
              ];
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  Space.md,
                  top + Space.md,
                  Space.md,
                  120,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: CupertinoSearchTextField(
                          placeholder: 'Search ${rows.length} people',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                    ),
                  ),
                  for (final (i, u) in shown.indexed)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: SurfaceCard(
                            onTap: () =>
                                showFormSheet(context, _UserForm(user: u)),
                            child: Row(
                              children: [
                                Opacity(
                                  opacity: u.active ? 1 : 0.4,
                                  child: AppAvatar(name: u.displayName),
                                ),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.displayName,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      Text(
                                        u.email,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      if (u.roles.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: [
                                            for (final r in u.roles)
                                              Pill(
                                                label:
                                                    '${r.role} · ${r.siteId == null ? 'All' : siteCodes[r.siteId] ?? '?'}',
                                                dense: true,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!u.active)
                                  Pill(
                                    label: 'Off',
                                    color: theme.colorScheme.error,
                                    dense: true,
                                  )
                                else if (u.roles.isEmpty)
                                  const Pill(
                                    label: 'No roles',
                                    color: Colors.orange,
                                    dense: true,
                                  ),
                              ],
                            ),
                          ),
                        ).entrance(context, index: i.clamp(0, 8)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Widget _label(BuildContext context, String t) => Padding(
  padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
  child: Text(t, style: Theme.of(context).textTheme.labelLarge),
);

/// A new sign-in: name, email and a first password the person changes later.
class _NewUserForm extends ConsumerStatefulWidget {
  const _NewUserForm();

  @override
  ConsumerState<_NewUserForm> createState() => _NewUserFormState();
}

class _NewUserFormState extends ConsumerState<_NewUserForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userAdminProvider)
          .create(
            email: _email.text,
            fullName: _name.text,
            password: _password.text,
          );
      HapticFeedback.mediumImpact();
      ref.invalidate(adminUsersProvider);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, '${_name.text.trim()} added. Now give them roles.');
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add person', style: theme.textTheme.headlineSmall),
          _label(context, 'Full name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
          ),
          _label(context, 'Email'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          _label(context, 'First password'),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              hintText: 'At least 8 characters; share it privately',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(CupertinoIcons.person_add),
            label: const Text('Create account'),
          ),
        ],
      ),
    );
  }
}

/// Profile, roles per site, on/off, and a password reset.
class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({required this.user});

  final AdminUser user;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  late final _name = TextEditingController(text: widget.user.fullName);
  late final _phone = TextEditingController(text: widget.user.phone);
  late String? _homeSite = widget.user.homeSiteId;
  late bool _active = widget.user.active;
  late final List<RoleGrant> _roles = [...widget.user.roles];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userAdminProvider)
          .save(
            userId: widget.user.id,
            fullName: _name.text,
            phone: _phone.text,
            homeSiteId: _homeSite,
            active: _active,
            roles: _roles,
          );
      HapticFeedback.mediumImpact();
      ref.invalidate(adminUsersProvider);
      if (widget.user.id == ref.read(authUserIdProvider)) {
        await ref.read(sessionProvider.notifier).refresh();
      }
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Saved');
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New password for ${widget.user.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'At least 8 characters'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Set password'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || !mounted) return;
    try {
      await ref.read(userAdminProvider).resetPassword(widget.user.id, password);
      if (mounted) _toast(context, 'Password changed');
    } catch (e) {
      if (mounted) setState(() => _error = AppError.from(e).message);
    }
  }

  Future<void> _addRole(List<String> roleNames) async {
    final session = ref.read(sessionProvider);
    String role = roleNames.first;
    String? site;
    final added = await showDialog<RoleGrant>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Add a role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in roleNames)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => set(() => role = v ?? role),
              ),
              const SizedBox(height: Space.sm),
              DropdownButtonFormField<String?>(
                initialValue: site,
                decoration: const InputDecoration(labelText: 'Where'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All sites')),
                  for (final s in session.sites.where((s) => !s.isArchived))
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => set(() => site = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (role: role, siteId: site)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (added != null && !_roles.contains(added)) {
      setState(() => _roles.add(added));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final roleNames = ref.watch(roleNamesProvider).value ?? const [];
    final sites = session.sites.where((s) => !s.isArchived).toList();
    final siteNames = {for (final s in session.sites) s.id: s.name};

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.user.displayName, style: theme.textTheme.headlineSmall),
          Text(widget.user.email, style: theme.textTheme.labelMedium),
          if (widget.user.lastSignIn != null)
            Text(
              'Last signed in ${MaterialLocalizations.of(context).formatMediumDate(widget.user.lastSignIn!)}',
              style: theme.textTheme.labelSmall,
            ),
          _label(context, 'Full name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
          ),
          _label(context, 'Phone'),
          TextField(controller: _phone, keyboardType: TextInputType.phone),
          _label(context, 'Home site'),
          DropdownButtonFormField<String?>(
            initialValue: sites.any((s) => s.id == _homeSite)
                ? _homeSite
                : null,
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final s in sites)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _homeSite = v),
          ),
          _label(context, 'Roles'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                for (final r in _roles)
                  ListTile(
                    dense: true,
                    leading: const Icon(CupertinoIcons.shield),
                    title: Text(r.role),
                    subtitle: Text(
                      r.siteId == null
                          ? 'All sites'
                          : siteNames[r.siteId] ?? 'Unknown site',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(CupertinoIcons.minus_circle),
                      onPressed: () => setState(() => _roles.remove(r)),
                    ),
                  ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    CupertinoIcons.add_circled,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    _roles.isEmpty ? 'No roles yet. Add one' : 'Add a role',
                  ),
                  onTap: roleNames.isEmpty ? null : () => _addRole(roleNames),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Can sign in'),
            subtitle: const Text('Switch off when someone leaves'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(CupertinoIcons.check_mark),
            label: const Text('Save'),
          ),
          const SizedBox(height: Space.xs),
          TextButton.icon(
            onPressed: _busy ? null : _resetPassword,
            icon: const Icon(CupertinoIcons.lock_rotation),
            label: const Text('Reset password'),
          ),
        ],
      ),
    );
  }
}
