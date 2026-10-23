import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../router.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'brand_logo.dart';
import 'notifications_button.dart';
import 'site_picker.dart';
import 'sync_banner.dart';

/// Phone: floating glass tab bar. Wider screens: collapsible sidebar.
/// Shows account problems instead of the tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.children});

  /// Below this width the app uses the phone layout.
  static const phoneMaxWidth = 720.0;

  /// Height reserved at the bottom for the floating tab bar on phones.
  static const phoneBarSpace = 96.0;

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final phone = MediaQuery.sizeOf(context).width < phoneMaxWidth;

    void go(int i) =>
        shell.goBranch(i, initialLocation: i == shell.currentIndex);

    final content = _AccountGate(
      session: session,
      child: _AnimatedBranches(index: shell.currentIndex, children: children),
    );

    final main = Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.paddingOf(context).copyWith(
                top: MediaQuery.paddingOf(context).top + 64,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    (phone ? phoneBarSpace : 0),
              ),
            ),
            child: content,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(title: shellTabs[shell.currentIndex].label),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 64,
          left: 0,
          right: 0,
          child: const SyncBanner(),
        ),
        if (phone)
          Positioned(
            left: Space.md,
            right: Space.md,
            bottom: MediaQuery.paddingOf(context).bottom + Space.md,
            child: _FloatingTabBar(index: shell.currentIndex, onTap: go),
          ),
      ],
    );

    return Scaffold(
      body: phone
          ? main
          : Row(
              children: [
                _Sidebar(index: shell.currentIndex, onTap: go),
                Expanded(child: main),
              ],
            ),
    );
  }
}

/// Keeps every tab alive and cross-fades between them (fade-through).
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
              curve: i == index ? const Interval(0.35, 1) : Curves.easeOut,
              child: AnimatedScale(
                scale: i == index ? 1 : 0.985,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return GlassSurface(
      radius: 0,
      blur: 20,
      opacity: theme.brightness == Brightness.dark ? 0.7 : 0.78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.md + 4, top, Space.xs, 0),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  switchInCurve: Motion.emphasized,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.25),
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
                    children: [
                      Text(title, style: theme.textTheme.headlineSmall),
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
                ),
              ),
              const SitePicker(),
              const NotificationsButton(),
            ],
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: GlassSurface(
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
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Radii.lg),
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
        scale: 0.9,
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  key: ValueKey(selected),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: Motion.of(context, Motion.medium),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
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

class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  bool? _expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = _expanded ?? MediaQuery.sizeOf(context).width >= 1100;
    final profile = ref.watch(sessionProvider.select((s) => s.profile));
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final name = (profile?.fullName.isNotEmpty ?? false)
        ? profile!.fullName
        : email;

    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.emphasized,
      width: expanded ? 256 : 84,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    const BrandLogo(width: 44),
                    if (expanded)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: Space.sm),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bravura',
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                              ),
                              Text(
                                'Electrical',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.fade,
                                softWrap: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              for (var i = 0; i < shellTabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SideItem(
                    tab: shellTabs[i],
                    selected: i == widget.index,
                    expanded: expanded,
                    onTap: () => widget.onTap(i),
                  ),
                ),
              const Spacer(),
              _SideButton(
                icon: expanded
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded,
                label: 'Collapse',
                expanded: expanded,
                onTap: () => setState(() => _expanded = !expanded),
              ),
              const SizedBox(height: Space.xs),
              Container(
                padding: const EdgeInsets.all(Space.xs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    AppAvatar(name: name, size: 40),
                    if (expanded) ...[
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
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
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        onPressed: () =>
                            ref.read(authUserIdProvider.notifier).signOut(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.tab,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final ShellTab tab;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: expanded ? '' : tab.label,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.emphasized,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(selected ? tab.selectedIcon : tab.icon, color: color),
              if (expanded) ...[
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    tab.label,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: Motion.of(context, Motion.medium),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              if (expanded) ...[
                const SizedBox(width: Space.sm),
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
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
        body = const Center(
          key: ValueKey('loading'),
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
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
    if (body.key != const ValueKey('app')) {
      body = Center(key: body.key, child: body);
    }

    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.slow),
      child: Padding(
        key: body.key,
        padding: body.key == const ValueKey('app')
            ? EdgeInsets.zero
            : MediaQuery.paddingOf(context) + const EdgeInsets.all(Space.lg),
        child: body,
      ),
    );
  }
}
