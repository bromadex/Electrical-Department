import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/page.dart';
import '../ui/surfaces.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
    'Sunday',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionProvider);
    final notes = ref.watch(notificationsProvider);
    final site = ref.watch(currentSiteProvider);
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final first = (session.profile?.fullName ?? '').split(' ').first;
    final now = harareNow();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final stats = [
      _Stat(
        icon: Icons.notifications_active_outlined,
        label: 'Unread',
        value: notes.unread,
        color: BrandColors.coral,
        onTap: () => context.push('/notifications'),
      ),
      _Stat(
        icon: Icons.place_outlined,
        label: 'My sites',
        value: session.mySites.length,
        color: BrandColors.info,
      ),
      _Stat(
        icon: Icons.grid_view_rounded,
        label: 'Areas here',
        value: site == null ? 0 : session.areasAt(site.id).length,
        color: BrandColors.success,
      ),
      _Stat(
        icon: Icons.verified_user_outlined,
        label: 'Permissions',
        value: session.perms.codes.length,
        color: BrandColors.warning,
      ),
    ];

    return PageScroll(
      onRefresh: () async {
        await Future.wait([
          ref.read(sessionProvider.notifier).refresh(),
          ref.read(notificationsProvider.notifier).refresh(),
        ]);
      },
      children: [
        // Hero
        SurfaceCard(
          gradient: BrandColors.brandGradient,
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_days[now.weekday - 1]}, ${now.day} '
                      '${_months[now.month - 1]}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(
                      first.isEmpty ? greeting : '$greeting, $first',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    if (site != null) ...[
                      const SizedBox(height: Space.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              site.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (wide)
                Floating(
                  child: AppAvatar(
                    name: session.profile?.fullName ?? email,
                    size: 72,
                  ),
                ),
            ],
          ),
        ).entrance(context),
        const SizedBox(height: Space.md),

        // Stats
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final (j, s) in stats.indexed)
                  SizedBox(width: w, child: s).entrance(context, index: 1 + j),
              ],
            );
          },
        ),

        const SectionHeader('Quick actions'),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
            final actions = [
              (Icons.add_task_rounded, 'New job', 'Phase 1'),
              (Icons.checklist_rounded, 'Start round', 'Phase 2'),
              (Icons.handyman_outlined, 'Issue tool', 'Phase 3'),
              (Icons.local_shipping_outlined, 'Request material', 'Phase 4'),
            ];
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final (j, a) in actions.indexed)
                  SizedBox(
                    width: w,
                    child: _QuickAction(icon: a.$1, label: a.$2, phase: a.$3),
                  ).entrance(context, index: 6 + j),
              ],
            );
          },
        ),

        SectionHeader(
          'Latest',
          trailing: TextButton(
            onPressed: () => context.push('/notifications'),
            child: const Text('See all'),
          ),
        ),
        if (notes.items.isEmpty)
          SurfaceCard(
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: Space.sm),
                Text(
                  'Nothing new. You are all caught up.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ).entrance(context, index: 10)
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                for (final (j, n) in notes.items.take(3).indexed)
                  ListTile(
                    onTap: () => context.push('/notifications'),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Icon(
                        Icons.notifications_outlined,
                        color: scheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: n.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: n.body == null
                        ? null
                        : Text(
                            n.body!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: n.isRead
                        ? null
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ).entrance(context, index: 10 + j),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: SurfaceCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: Space.sm),
            AnimatedCount(value: value, style: theme.textTheme.headlineMedium),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.phase,
  });

  final IconData icon;
  final String label;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void tap() => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label arrives in $phase.')));
    return Pressable(
      onTap: tap,
      child: SurfaceCard(
        onTap: tap,
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    phase,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
