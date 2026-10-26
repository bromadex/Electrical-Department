import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/permission_set.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../widgets/brand_logo.dart';
import '../widgets/notifications_button.dart';
import '../widgets/theme_toggle.dart';
import 'navigation.dart';
import 'reference/reference_data.dart';
import 'ui/bits.dart';
import 'widgets/global_search.dart';
import 'widgets/site_picker.dart';

/// The frame around the job cards section, in the main app's liquid-glass look:
/// the mesh wallpaper, a floating glass menu beside a large glass window on
/// wide screens, and a glass top bar with a floating tab bar on phones. The
/// menu always offers the way back to the main app.
class V2Shell extends ConsumerWidget {
  const V2Shell({super.key, required this.child});

  /// Below this width the phone layout is used (as in the main app).
  static const phoneMaxWidth = 720.0;
  static const phoneBarSpace = 96.0;
  static const phoneTopBar = 60.0;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // Lists, settings and the site time zone, loaded once per session.
    ref.watch(referenceDataProvider);
    final items = visibleNavItems(session.perms);
    final location = GoRouterState.of(context).uri.path;
    final current = navItemFor(location, items);
    final title = current?.label ?? 'Job Cards';
    final content = _AccountGate(session: session, child: child);

    if (MediaQuery.sizeOf(context).width < phoneMaxWidth) {
      final inset = MediaQuery.paddingOf(context);
      final bar = phoneNavItems(session.perms);
      final creates = createOptions(session.perms);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: MeshBackground(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: inset.top + phoneTopBar,
                    bottom: inset.bottom + phoneBarSpace,
                  ),
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    child: content,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _PhoneTopBar(title: title),
              ),
              Positioned(
                left: Space.md,
                right: Space.md,
                bottom: inset.bottom + Space.sm,
                child: _FloatingTabBar(
                  items: bar,
                  current: current,
                  onMenu: () => _showMenu(context, items, current),
                  onCreate: creates.isEmpty
                      ? null
                      : () => _showCreate(context, creates),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MeshBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: [
                Center(
                  child: _NavCapsule(items: items, current: current),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: GlassSurface(
                    radius: 34,
                    child: Column(
                      children: [
                        _WindowHeader(title: title),
                        Expanded(
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            child: content,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Phones: every job cards screen, and the way back, in a glass sheet.
  static void _showMenu(
    BuildContext context,
    List<NavItem> items,
    NavItem? current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: GlassSurface(
            radius: 30,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in [versionOneItem, ...items])
                  ListTile(
                    leading: Icon(
                      identical(i, current) ? i.selectedIcon : i.icon,
                    ),
                    title: Text(i.label),
                    selected: identical(i, current),
                    onTap: () {
                      Navigator.pop(sheet);
                      context.go(i.path);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the phone bar's + can start, by permission.
List<NavItem> createOptions(PermissionSet p) => [
  if (p.can('jc.register'))
    NavItem(
      '/v2/job-cards/new',
      'New job card',
      Icons.assignment_add,
      Icons.assignment_add,
      (_) => true,
    ),
  if (p.can('req.submit'))
    NavItem(
      '/v2/my-requests/new',
      'New request',
      Icons.outbox_outlined,
      Icons.outbox_rounded,
      (_) => true,
    ),
];

/// Phones: the + opens the only option at once, or a sheet to choose.
void _showCreate(BuildContext context, List<NavItem> options) {
  HapticFeedback.lightImpact();
  if (options.length == 1) {
    context.go(options.single.path);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: GlassSurface(
          radius: 30,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                ListTile(
                  leading: Icon(o.icon),
                  title: Text(o.label),
                  onTap: () {
                    Navigator.pop(sheet);
                    context.go(o.path);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The way back to the main app (Home), first in every job cards menu.
final versionOneItem = NavItem(
  '/home',
  'Back to main app',
  Icons.arrow_back_rounded,
  Icons.arrow_back_rounded,
  (_) => true,
);

class _WindowHeader extends StatelessWidget {
  const _WindowHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOB CARDS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: BrandColors.coral,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  title,
                  style: theme.textTheme.headlineMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SitePicker(),
          const SizedBox(width: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: const GlobalSearchField(),
          ),
          const SizedBox(width: Space.sm),
          const ThemeToggle(glass: true),
          const SizedBox(width: Space.sm),
          const NotificationsButton(glass: true),
        ],
      ),
    );
  }
}

class _PhoneTopBar extends StatelessWidget {
  const _PhoneTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return GlassSurface(
      radius: 0,
      blur: 30,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.xxs, top, Space.xs, 0),
        child: SizedBox(
          height: V2Shell.phoneTopBar,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to main app',
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JOB CARDS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: BrandColors.coral,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const GlobalSearchButton(),
              const ThemeToggle(),
              const NotificationsButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating glass capsule (desktop navigation): the way back to the main
/// app, then the job cards screens, with the main app's gradient pill.
class _NavCapsule extends StatelessWidget {
  const _NavCapsule({required this.items, required this.current});

  final List<NavItem> items;
  final NavItem? current;

  static const _item = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = MediaQuery.sizeOf(context).width >= 1100;
    final width = labels ? 212.0 : _item;
    final index = items.indexWhere((i) => identical(i, current));

    Widget entry(NavItem item, {required bool selected}) => Tooltip(
      message: labels ? '' : item.label,
      preferBelow: false,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            context.go(item.path);
          },
          scale: 0.92,
          child: SizedBox(
            width: width,
            height: _item,
            child: Row(
              mainAxisAlignment: labels
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (labels) const SizedBox(width: 16),
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: selected ? Colors.white : scheme.onSurfaceVariant,
                ),
                if (labels) ...[
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogo(width: 64),
        const SizedBox(height: Space.md),
        GlassSurface(
          radius: labels ? 26 : 40,
          strong: true,
          padding: const EdgeInsets.all(8),
          child: entry(versionOneItem, selected: false),
        ),
        const SizedBox(height: Space.sm),
        GlassSurface(
          radius: labels ? 30 : 40,
          strong: true,
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: width,
            height: _item * items.length,
            child: Stack(
              children: [
                if (index >= 0)
                  AnimatedPositioned(
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.spring,
                    top: index * _item,
                    left: 0,
                    width: width,
                    height: _item,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        gradient: BrandColors.brandGradient,
                        boxShadow: [
                          BoxShadow(
                            color: BrandColors.maroon.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      foregroundDecoration: RimDecoration(
                        radius: Radii.pill,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.6),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                    ),
                  ),
                Column(
                  children: [
                    for (final item in items)
                      entry(item, selected: identical(item, current)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.items,
    required this.current,
    required this.onMenu,
    this.onCreate,
  });

  final List<NavItem> items;
  final NavItem? current;
  final VoidCallback onMenu;

  /// The round + in the middle, as in the main app; null hides it.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The + sits after the second entry and takes a slot of its own.
    final plusAt = onCreate == null
        ? -1
        : (items.length < 2 ? items.length : 2);
    final count = items.length + 1 + (onCreate == null ? 0 : 1);
    final found = items.indexWhere((i) => identical(i, current));
    final index = found < 0 || plusAt < 0 || found < plusAt ? found : found + 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: GlassSurface(
        radius: 34,
        blur: 30,
        strong: true,
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 60,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth / count;
              return Stack(
                children: [
                  if (index >= 0)
                    AnimatedPositioned(
                      duration: Motion.of(context, Motion.slow),
                      curve: Motion.spring,
                      left: index * w,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (final (i, item) in items.indexed) ...[
                        if (i == plusAt)
                          Expanded(
                            child: Center(
                              child: _CreateButton(onTap: onCreate!),
                            ),
                          ),
                        Expanded(
                          child: _TabItem(
                            icon: identical(item, current)
                                ? item.selectedIcon
                                : item.icon,
                            label: _short(item.label),
                            selected: identical(item, current),
                            onTap: () => context.go(item.path),
                          ),
                        ),
                      ],
                      if (plusAt == items.length)
                        Expanded(
                          child: Center(child: _CreateButton(onTap: onCreate!)),
                        ),
                      Expanded(
                        child: _TabItem(
                          icon: Icons.menu_rounded,
                          label: 'Menu',
                          selected: false,
                          onTap: onMenu,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _short(String label) => switch (label) {
    'My Assigned Jobs' => 'My Jobs',
    'Incoming Requests' => 'Incoming',
    'My Requests' => 'Requests',
    _ => label,
  };
}

/// The round + in the middle of the phone tab bar (as in the main app).
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.88,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BrandColors.brandGradient,
            boxShadow: [
              BoxShadow(
                color: BrandColors.maroon.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(CupertinoIcons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.86,
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps people without a working account (no profile, deactivated, or no
/// part in job cards) out of the screens, with a clear reason and a way back.
class _AccountGate extends ConsumerWidget {
  const _AccountGate({required this.session, required this.child});

  final SessionState session;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget blocked(String title, String message) => EmptyState(
      icon: Icons.lock_outline_rounded,
      title: title,
      message: message,
      action: FilledButton.icon(
        onPressed: () => context.go('/home'),
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Back to main app'),
      ),
    );

    final profile = session.profile;
    if (profile == null) {
      if (session.error != null) {
        return ErrorPanel(
          error: session.error!,
          onRetry: () => ref.read(sessionProvider.notifier).refresh(),
        );
      }
      return const LoadingPanel(label: 'Loading your account…');
    }
    if (!profile.active) {
      return blocked(
        'Account deactivated',
        'An administrator has deactivated this account.',
      );
    }
    final p = session.perms;
    if (session.refreshed && !p.can('jc.view') && !p.can('req.submit')) {
      return blocked(
        'No access to job cards',
        'Your roles do not include job cards or requests yet. Ask a system administrator.',
      );
    }
    return child;
  }
}
