import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../documents/documents_repository.dart';
import '../requests/requests_screen.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));
    final mode = ref.watch(themeModeProvider);
    final push = ref.watch(pushProvider);
    final toSign = ref.watch(toSignCountProvider);
    final newRequests = ref.watch(newRequestCountProvider);
    final profile = session.profile;
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final name = (profile?.fullName.isNotEmpty ?? false)
        ? profile!.fullName
        : email;
    final homeSite = session.siteById(profile?.homeSiteId);
    final codes = session.perms.codes.toList()..sort();

    return PageScroll(
      maxWidth: 720,
      onRefresh: ref.read(sessionProvider.notifier).refresh,
      children: [
        SurfaceCard(
          gradient: BrandColors.brandGradient,
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
                child: AppAvatar(name: name, size: 64),
              ),
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
                      email,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    if (homeSite != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        'Home site · ${homeSite.name}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ).entrance(context),

        const SectionHeader('Appearance'),
        SurfaceCard(
          child: Row(
            children: [
              Icon(Icons.palette_outlined, color: scheme.primary),
              const SizedBox(width: Space.sm),
              const Expanded(child: Text('Theme')),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    tooltip: 'System',
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                    tooltip: 'Light',
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                    tooltip: 'Dark',
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ],
          ),
        ).entrance(context, index: 1),

        const SectionHeader('Account'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              _Row(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                trailing: unread > 0
                    ? Badge(label: Text('$unread'))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/notifications'),
              ),
              if (push != PushState.unavailable)
                _Row(
                  icon: Icons.notifications_active_outlined,
                  title: 'Alerts on this device',
                  subtitle: push == PushState.blocked
                      ? 'Blocked. Allow notifications in your settings.'
                      : null,
                  trailing: Switch.adaptive(
                    value: push == PushState.on,
                    onChanged: push == PushState.blocked
                        ? null
                        : (on) => on
                              ? ref.read(pushProvider.notifier).enable()
                              : ref.read(pushProvider.notifier).disable(),
                  ),
                ),
              _Row(
                icon: Icons.place_outlined,
                title: 'My sites',
                subtitle: session.mySites.map((s) => s.code).join(' · '),
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
                icon: Icons.verified_user_outlined,
                title: 'My permissions',
                subtitle: '${codes.length} granted',
                onTap: () => _sheet(
                  context,
                  'My permissions',
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final c in codes) Pill(label: c)],
                  ),
                ),
              ),
            ],
          ),
        ).entrance(context, index: 2),

        const SectionHeader('Library'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              _Row(
                icon: Icons.move_to_inbox_outlined,
                title: 'Requests',
                subtitle: newRequests > 0
                    ? '$newRequests waiting for a decision'
                    : 'Work asked for by other departments',
                trailing: newRequests > 0
                    ? Badge(label: Text('$newRequests'))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/requests'),
              ),
              _Row(
                icon: Icons.fact_check_outlined,
                title: 'Checklists',
                subtitle: 'Daily, weekly and monthly rounds',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/checklists'),
              ),
              _Row(
                icon: Icons.menu_book_outlined,
                title: 'Documents & SOPs',
                subtitle: toSign > 0
                    ? '$toSign to read and sign'
                    : 'SOPs, drawings and manuals',
                trailing: toSign > 0
                    ? Badge(label: Text('$toSign'))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/documents'),
              ),
              _Row(
                icon: Icons.precision_manufacturing_outlined,
                title: 'Assets',
                subtitle: 'Plant register and job history',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/assets'),
              ),
            ],
          ),
        ),

        if (session.perms.canEverywhere('admin.users')) ...[
          const SectionHeader('Admin'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                _Row(
                  icon: Icons.group_outlined,
                  title: 'People',
                  subtitle: 'Accounts, roles and sites',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/admin/users'),
                ),
                _Row(
                  icon: Icons.timer_outlined,
                  title: 'Priority targets',
                  subtitle: 'Response and finish times',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/admin/targets'),
                ),
                _Row(
                  icon: Icons.history_rounded,
                  title: 'Audit log',
                  subtitle: 'Every change, who and when',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/admin/activity'),
                ),
              ],
            ),
          ).entrance(context, index: 3),
        ],

        const SizedBox(height: Space.lg),
        Pressable(
          onTap: () => ref.read(authUserIdProvider.notifier).signOut(),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(authUserIdProvider.notifier).signOut(),
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ).entrance(context, index: 3),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text(
            'Bravura Electrical · ${Env.flavor}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
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
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    );
  }
}
