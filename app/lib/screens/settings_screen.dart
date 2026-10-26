import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_repository.dart';
import '../config/env.dart';
import '../data/app_error.dart';
import '../data/site_data.dart';
import '../services/core_providers.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../tools/tools_repository.dart';
import '../ui/bits.dart';
import '../ui/charts.dart' show GlassSegmented;
import '../ui/form_sheet.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/app_back_button.dart';

/// Settings in one place, grouped like iOS: you, this device, admin (for
/// administrators) and about. Opened from the Menu.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionProvider);
    final push = ref.watch(pushProvider);
    final mode = ref.watch(themeModeProvider);
    final profile = session.profile;
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final name = (profile?.fullName.isNotEmpty ?? false)
        ? profile!.fullName
        : email;
    final homeSite = session.siteById(profile?.homeSiteId);
    final codes = session.perms.codes.toList()..sort();
    final admin = session.perms.canEverywhere('admin.users');
    final sitesAdmin = session.perms.canEverywhere('admin.sites');
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/menu'),
        title: const Text('Settings'),
        flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            top + Space.md,
            Space.md,
            Space.xl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceCard(
                      gradient: BrandColors.brandGradient,
                      padding: const EdgeInsets.all(Space.lg),
                      onTap: () =>
                          showFormSheet(context, const _ProfileSheet()),
                      child: Row(
                        children: [
                          AppAvatar(name: name, size: 64),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  [email, ?profile?.phone].join(' · '),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                if (homeSite != null)
                                  Text(
                                    'Home site · ${homeSite.name}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.pencil_circle_fill,
                            color: Colors.white,
                            size: 28,
                          ),
                        ],
                      ),
                    ).entrance(context),

                    const SectionHeader('You'),
                    _Group(
                      children: [
                        _Row(
                          icon: CupertinoIcons.person_crop_circle,
                          title: 'Name, phone and home site',
                          onTap: () =>
                              showFormSheet(context, const _ProfileSheet()),
                        ),
                        _Row(
                          icon: CupertinoIcons.lock,
                          title: 'Change password',
                          onTap: () =>
                              showFormSheet(context, const _PasswordSheet()),
                        ),
                        _Row(
                          icon: CupertinoIcons.location,
                          title: 'My sites',
                          subtitle: session.mySites
                              .map((s) => s.code)
                              .join(' · '),
                          onTap: () => _sheet(
                            context,
                            'My sites',
                            Column(
                              children: [
                                for (final s in session.mySites)
                                  ListTile(
                                    leading: Pill(label: s.code),
                                    title: Text(s.name),
                                    subtitle: Text(
                                      '${session.areasAt(s.id).length} areas',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _Row(
                          icon: CupertinoIcons.checkmark_shield,
                          title: 'What I can do',
                          subtitle: '${codes.length} permissions',
                          onTap: () => _sheet(
                            context,
                            'What I can do',
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [for (final c in codes) Pill(label: c)],
                            ),
                          ),
                        ),
                      ],
                    ).entrance(context, index: 1),

                    const SectionHeader('This device'),
                    _Group(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(Space.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Appearance',
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: Space.xs),
                              GlassSegmented<ThemeMode>(
                                value: mode,
                                segments: const {
                                  ThemeMode.system: 'Automatic',
                                  ThemeMode.light: 'Light',
                                  ThemeMode.dark: 'Dark',
                                },
                                onChanged: ref
                                    .read(themeModeProvider.notifier)
                                    .set,
                              ),
                            ],
                          ),
                        ),
                        if (push != PushState.unavailable)
                          _Row(
                            icon: CupertinoIcons.bell,
                            title: 'Alerts on this device',
                            subtitle: push == PushState.blocked
                                ? 'Blocked. Allow notifications in your '
                                      'phone or browser settings.'
                                : 'Job cards, chats and calls',
                            trailing: Switch.adaptive(
                              value: push == PushState.on,
                              onChanged: push == PushState.blocked
                                  ? null
                                  : (on) => on
                                        ? ref
                                              .read(pushProvider.notifier)
                                              .enable()
                                        : ref
                                              .read(pushProvider.notifier)
                                              .disable(),
                            ),
                          ),
                        const _Waiting(),
                        _Row(
                          icon: CupertinoIcons.arrow_2_circlepath,
                          title: 'Reload everything',
                          subtitle:
                              'Fetch people, equipment, tools and '
                              'chats again',
                          onTap: () => _reload(context, ref),
                        ),
                      ],
                    ).entrance(context, index: 2),

                    if (admin || sitesAdmin) ...[
                      const SectionHeader('Admin'),
                      _Group(
                        children: [
                          if (admin)
                            _Row(
                              icon: CupertinoIcons.person_2,
                              title: 'People',
                              subtitle: 'Accounts and roles',
                              onTap: () => context.push('/admin/users'),
                            ),
                          if (sitesAdmin)
                            _Row(
                              icon: CupertinoIcons.map,
                              title: 'Sites and areas',
                              subtitle: '${session.sites.length} sites',
                              onTap: () => context.push('/admin/sites'),
                            ),
                          if (admin) ...[
                            _Row(
                              icon: CupertinoIcons.slider_horizontal_3,
                              title: 'Job card settings',
                              subtitle: 'Priorities, numbering, categories',
                              onTap: () => context.push('/admin/job-settings'),
                            ),
                            _Row(
                              icon: CupertinoIcons.clock,
                              title: 'Activity log',
                              subtitle: 'Every change',
                              onTap: () => context.push('/admin/audit'),
                            ),
                          ],
                        ],
                      ).entrance(context, index: 3),
                    ],

                    const SectionHeader('About'),
                    _Group(
                      children: [
                        _Row(
                          icon: CupertinoIcons.info,
                          title: 'Bravura Electrical',
                          subtitle: Env.flavor == 'prod'
                              ? 'Electrical Department'
                              : 'Test version (${Env.flavor})',
                          trailing: const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(authUserIdProvider.notifier).signOut(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Reloading…')));
    await Future.wait([
      ref.read(sessionProvider.notifier).refresh(),
      ref.read(siteDataProvider.notifier).refresh(),
      ref.read(toolsSyncProvider.notifier).refresh(),
      ref.read(conversationsProvider.notifier).refresh(),
    ]);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Up to date')));
  }

  void _sheet(BuildContext context, String title, Widget body) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            Flexible(child: SingleChildScrollView(child: body)),
          ],
        ),
      ),
    );
  }
}

/// Changes made offline that have not reached the server yet.
class _Waiting extends ConsumerWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.watch(outboxProvider);
    return StreamBuilder<int>(
      stream: outbox.watchPending(),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return _Row(
          icon: CupertinoIcons.cloud_upload,
          title: n == 0 ? 'Everything is sent' : '$n waiting to send',
          subtitle: n == 0
              ? 'Changes made offline send when you are back online'
              : 'Tap to try now',
          trailing: n == 0
              ? const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: BrandColors.success,
                )
              : null,
          onTap: n == 0 ? null : () => unawaited(outbox.flush()),
        );
      },
    );
  }
}

/// Your name, phone and home site.
class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet();

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final _profile = ref.read(sessionProvider).profile;
  late final _name = TextEditingController(text: _profile?.fullName);
  late final _phone = TextEditingController(text: _profile?.phone);
  late String? _home = _profile?.homeSiteId;
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
          .read(supabaseProvider)
          .rpc(
            'fn_update_my_profile',
            params: {
              'p_full_name': _name.text,
              'p_phone': _phone.text,
              'p_home_site': _home,
            },
          );
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sites = ref.watch(sessionProvider).mySites;
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
          Text('Your details', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: Space.sm),
          DropdownButtonFormField<String?>(
            initialValue: sites.any((s) => s.id == _home) ? _home : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Home site'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final s in sites)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _home = v),
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
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// A new password for the signed-in account (online only).
class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters');
      return;
    }
    if (_new.text != _again.text) {
      setState(() => _error = 'The two passwords are different');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(supabaseProvider)
          .auth
          .updateUser(UserAttributes(password: _new.text));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is AuthException ? e.message : AppError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: _show ? 'Hide' : 'Show',
        icon: Icon(_show ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
        onPressed: () => setState(() => _show = !_show),
      ),
    );
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
          Text('Change password', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.md),
          TextField(
            controller: _new,
            obscureText: !_show,
            autofillHints: const [AutofillHints.newPassword],
            decoration: field('New password'),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _again,
            obscureText: !_show,
            decoration: field('New password again'),
            onSubmitted: (_) => _save(),
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
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Change password'),
          ),
        ],
      ),
    );
  }
}

/// A rounded group of rows with thin lines between them.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            c,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(icon, color: scheme.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
    );
  }
}
