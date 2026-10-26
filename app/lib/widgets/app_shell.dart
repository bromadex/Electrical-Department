import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart';
import '../config/env.dart';
import '../router.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'brand_logo.dart';
import 'notifications_button.dart';
import 'site_picker.dart';
import 'sync_banner.dart';
import 'theme_toggle.dart';

/// Phone: iOS-style large title and floating glass tab bar.
/// Wider screens: floating capsule menu beside a large glass window.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.children});

  /// Below this width the app uses the phone layout.
  static const phoneMaxWidth = 720.0;

  /// Height reserved at the bottom for the floating tab bar on phones.
  static const phoneBarSpace = 96.0;

  /// Height of the phone top bar below the status bar.
  static const phoneTopBar = 60.0;

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final phone = MediaQuery.sizeOf(context).width < phoneMaxWidth;
    final title = shellTabs[shell.currentIndex].label;

    void go(int i) {
      HapticFeedback.selectionClick();
      shell.goBranch(i, initialLocation: i == shell.currentIndex);
    }

    final content = _AccountGate(
      session: session,
      child: _AnimatedBranches(index: shell.currentIndex, children: children),
    );

    if (phone) {
      final inset = MediaQuery.paddingOf(context);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: MeshBackground(
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: inset.copyWith(
                      top: inset.top + phoneTopBar,
                      bottom: inset.bottom + phoneBarSpace,
                    ),
                  ),
                  child: content,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _PhoneTopBar(title: title),
              ),
              Positioned(
                top: inset.top + phoneTopBar,
                left: 0,
                right: 0,
                child: const SyncBanner(),
              ),
              Positioned(
                left: Space.md,
                right: Space.md,
                bottom: inset.bottom + Space.sm,
                child: _FloatingTabBar(index: shell.currentIndex, onTap: go),
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
                  child: _NavCapsule(index: shell.currentIndex, onTap: go),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: GlassSurface(
                    radius: 34,
                    child: Column(
                      children: [
                        _WindowHeader(title: title),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: MediaQuery.removePadding(
                                  context: context,
                                  removeTop: true,
                                  removeBottom: true,
                                  child: content,
                                ),
                              ),
                              const Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: SyncBanner(),
                              ),
                            ],
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
}

/// Keeps every tab alive and cross-fades between them.
class _AnimatedBranches extends StatelessWidget {
  const _AnimatedBranches({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.medium);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: AnimatedOpacity(
              opacity: i == index ? 1 : 0,
              duration: d,
              curve: i == index ? const Interval(0.3, 1) : Curves.easeOut,
              child: AnimatedSlide(
                offset: i == index ? Offset.zero : const Offset(0, 0.015),
                duration: d,
                curve: Motion.emphasized,
                child: TickerMode(enabled: i == index, child: children[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _TitleText extends StatelessWidget {
  const _TitleText({required this.title, required this.style});

  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.emphasized,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Row(
        key: ValueKey(title),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: style),
          if (!Env.isProd) ...[
            const SizedBox(width: Space.xs),
            Pill(
              label: Env.flavor.toUpperCase(),
              color: BrandColors.warning,
              dense: true,
            ),
          ],
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
        padding: EdgeInsets.fromLTRB(Space.md + 4, top, Space.xs, 0),
        child: SizedBox(
          height: AppShell.phoneTopBar,
          child: Row(
            children: [
              Expanded(
                child: _TitleText(
                  title: title,
                  style: theme.textTheme.headlineMedium?.copyWith(fontSize: 30),
                ),
              ),
              const SitePicker(),
              const ThemeToggle(),
              const NotificationsButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowHeader extends ConsumerWidget {
  const _WindowHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            child: _TitleText(
              title: title,
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SitePicker(large: true),
          const SizedBox(width: Space.sm),
          const ThemeToggle(glass: true),
          const SizedBox(width: Space.sm),
          const NotificationsButton(glass: true),
          const SizedBox(width: Space.sm),
          const _ProfileChip(),
        ],
      ),
    );
  }
}

class _ProfileChip extends ConsumerWidget {
  const _ProfileChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = Glass.of(context);
    final profile = ref.watch(sessionProvider.select((s) => s.profile));
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final name = (profile?.fullName.isNotEmpty ?? false)
        ? profile!.fullName
        : email;
    final mode = ref.watch(themeModeProvider);

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 60),
      onSelected: (v) {
        switch (v) {
          case 'system':
            ref.read(themeModeProvider.notifier).set(ThemeMode.system);
          case 'light':
            ref.read(themeModeProvider.notifier).set(ThemeMode.light);
          case 'dark':
            ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
          case 'more':
            context.go('/more');
          case 'signout':
            ref.read(authUserIdProvider.notifier).signOut();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'more',
          child: ListTile(
            leading: Icon(Icons.person_outline_rounded),
            title: Text('Profile'),
          ),
        ),
        const PopupMenuDivider(),
        for (final (m, label, icon) in [
          (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
          (ThemeMode.light, 'Light', Icons.light_mode_outlined),
          (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
        ])
          PopupMenuItem(
            value: m.name,
            child: ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: m == mode ? const Icon(Icons.check_rounded) : null,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(
          color: g.fill,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: g.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(name: name, size: 36),
            const SizedBox(width: Space.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    email,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.xs),
            Icon(
              Icons.expand_more_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating glass capsule (desktop navigation): icons with their names on
/// wide windows, icons alone on narrower ones.
class _NavCapsule extends StatelessWidget {
  const _NavCapsule({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _item = 56.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = MediaQuery.sizeOf(context).width >= 1100;
    final width = labels ? 188.0 : _item;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogo(width: 64),
        const SizedBox(height: Space.lg),
        GlassSurface(
          radius: labels ? 30 : 40,
          strong: true,
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: width,
            height: _item * shellTabs.length,
            child: Stack(
              children: [
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
                    for (var i = 0; i < shellTabs.length; i++)
                      Tooltip(
                        message: labels ? '' : shellTabs[i].label,
                        preferBelow: false,
                        child: Pressable(
                          onTap: () => onTap(i),
                          scale: 0.92,
                          child: SizedBox(
                            width: width,
                            height: _item,
                            child: Row(
                              mainAxisAlignment: labels
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                if (labels) const SizedBox(width: 18),
                                AnimatedSwitcher(
                                  duration: Motion.of(context, Motion.medium),
                                  child: _TabBadge(
                                    key: ValueKey(i == index),
                                    tab: shellTabs[i],
                                    child: Icon(
                                      i == index
                                          ? shellTabs[i].selectedIcon
                                          : shellTabs[i].icon,
                                      color: i == index
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (labels) ...[
                                  const SizedBox(width: Space.sm),
                                  Text(
                                    shellTabs[i].label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: i == index
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
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
  const _FloatingTabBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              final w = c.maxWidth / shellTabs.length;
              return Stack(
                children: [
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
                      for (var i = 0; i < shellTabs.length; i++)
                        Expanded(
                          child: _TabItem(
                            tab: shellTabs[i],
                            selected: i == index,
                            onTap: () => onTap(i),
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
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: Pressable(
        onTap: onTap,
        scale: 0.86,
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: _TabBadge(
                  key: ValueKey(selected),
                  tab: tab,
                  child: Icon(
                    selected ? tab.selectedIcon : tab.icon,
                    color: color,
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: Motion.of(context, Motion.medium),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(tab.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountGate extends StatelessWidget {
  const _AccountGate({required this.session, required this.child});

  final SessionState session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (session.profile == null) {
      if (session.error != null) {
        body = EmptyState(
          key: const ValueKey('error'),
          icon: Icons.wifi_off_rounded,
          title: 'Could not load your account',
          message: session.error!.message,
        );
      } else if (!session.refreshed) {
        body = const SizedBox.square(
          key: ValueKey('loading'),
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
      } else {
        body = const EmptyState(
          key: ValueKey('inactive'),
          icon: Icons.person_off_outlined,
          title: 'Account not active',
          message:
              'Your account is not active or has not been set up yet. '
              'Ask an admin to activate it and give you a role.',
        );
      }
    } else if (session.perms.isEmpty) {
      body = const EmptyState(
        key: ValueKey('norole'),
        icon: Icons.lock_outline_rounded,
        title: 'No role yet',
        message: 'Ask an admin to give you a role so you can start working.',
      );
    } else {
      body = KeyedSubtree(key: const ValueKey('app'), child: child);
    }

    final isApp = body.key == const ValueKey('app');
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.slow),
      child: isApp
          ? body
          : Padding(
              key: body.key,
              padding:
                  MediaQuery.paddingOf(context) +
                  const EdgeInsets.all(Space.lg),
              child: Center(child: body),
            ),
    );
  }
}

/// Unread chat messages on the Chat tab.
class _TabBadge extends ConsumerWidget {
  const _TabBadge({super.key, required this.tab, required this.child});

  final ShellTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = tab.path == '/chat' ? ref.watch(chatUnreadProvider) : 0;
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: BrandColors.maroon,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}
