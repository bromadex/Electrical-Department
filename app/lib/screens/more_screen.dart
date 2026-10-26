import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../documents/documents_repository.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/push_service.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';
import '../ui/tiles.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));
    final push = ref.watch(pushProvider);
    final toSign = ref.watch(toSignCountProvider);
    final profile = session.profile;
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final name = (profile?.fullName.isNotEmpty ?? false)
        ? profile!.fullName
        : email;
    final homeSite = session.siteById(profile?.homeSiteId);

    return PageScroll(
      maxWidth: 720,
      onRefresh: ref.read(sessionProvider.notifier).refresh,
      children: [
        SurfaceCard(
          gradient: BrandColors.brandGradient,
          padding: const EdgeInsets.all(Space.lg),
          onTap: () => context.push('/settings'),
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

        const SectionHeader('Everything'),
        TileGrid(
          tiles: [
            ShortcutTile(
              icon: Icons.summarize_outlined,
              title: 'Daily report',
              subtitle: 'Updates and approval',
              colors: const [BrandColors.maroon, BrandColors.coral],
              onTap: () => context.push('/reports'),
            ),
            if (session.can('req.triage'))
              ShortcutTile(
                icon: Icons.move_to_inbox_outlined,
                title: 'Requests',
                subtitle: 'From other departments',
                colors: const [BrandColors.info, Color(0xFF6A8FE8)],
                onTap: () => context.push('/requests'),
              ),
            if (session.can('req.submit'))
              ShortcutTile(
                icon: Icons.outbox_outlined,
                title: 'My requests',
                subtitle: 'Work you asked for',
                colors: const [Color(0xFF6A8FE8), BrandColors.blush],
                onTap: () => context.push('/my-requests'),
              ),
            if (session.can('jc.view'))
              ShortcutTile(
                icon: Icons.insights_outlined,
                title: 'Job statistics',
                subtitle: 'Trends and times',
                colors: const [BrandColors.maroonDeep, BrandColors.info],
                onTap: () => context.push('/job-stats'),
              ),
            ShortcutTile(
              icon: Icons.fact_check_outlined,
              title: 'Checklists',
              subtitle: 'Daily rounds',
              colors: const [BrandColors.success, Color(0xFF4CC195)],
              onTap: () => context.push('/checklists'),
            ),
            ShortcutTile(
              icon: Icons.menu_book_outlined,
              title: 'Documents',
              subtitle: toSign > 0 ? '$toSign to sign' : 'SOPs and drawings',
              badge: toSign,
              colors: const [BrandColors.coral, BrandColors.blush],
              onTap: () => context.push('/documents'),
            ),
            ShortcutTile(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Equipment & tools',
              subtitle: 'Plant, and who has what',
              colors: const [BrandColors.maroonDeep, BrandColors.maroon],
              onTap: () => context.push('/equipment'),
            ),
            ShortcutTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: unread > 0 ? '$unread unread' : 'All caught up',
              badge: unread,
              colors: const [Color(0xFF5B4B8A), BrandColors.info],
              onTap: () => context.push('/notifications'),
            ),
            if (session.can('jobs.assign'))
              ShortcutTile(
                icon: Icons.event_repeat_rounded,
                title: 'Planned maintenance',
                subtitle: 'Raises job cards',
                colors: const [BrandColors.success, BrandColors.info],
                onTap: () => context.push('/jobs/recurring'),
              ),
          ],
        ).entrance(context, index: 1),

        const SectionHeader('Account'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              _Row(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: [
                  'Profile, password, appearance',
                  if (push == PushState.off) 'alerts are off',
                  if (session.perms.canEverywhere('admin.users')) 'admin',
                ].join(' · '),
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ).entrance(context, index: 2),
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
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
