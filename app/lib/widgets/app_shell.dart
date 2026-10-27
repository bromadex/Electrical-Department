import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_repository.dart';
import '../chat/presence.dart';
import '../config/env.dart';
import '../data/site_data.dart';
import '../router.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../theme/tokens.dart';
import '../ui/bits.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import '../v2/reference/reference_data.dart';
import 'brand_logo.dart';
import 'create_sheet.dart';
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
    // Lists, settings and the site time zone the job card screens rely on.
    ref.watch(referenceDataProvider);
    // People's names and the site's equipment, kept on the device.
    ref.watch(siteDataProvider);
    // Who is online and typing, for the chat list and headers.
    ref.watch(chatPresenceProvider);
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
                child: _SwipeTabBar(index: shell.currentIndex, onTap: go),
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
                    saturate: 1.3,
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
            context.go('/menu');
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

/// Desktop navigation: the New button, the tabs, then direct links to the
/// everyday screens. Icons with names on wide windows, icons alone on
/// narrower ones.
class _NavCapsule extends ConsumerWidget {
  const _NavCapsule({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _item = 52.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final labels = MediaQuery.sizeOf(context).width >= 1100;
    final width = labels ? 188.0 : _item;
    final links = shellLinks(
      ref.watch(sessionProvider),
      ref.watch(currentSiteProvider)?.id,
    );

    Widget row(IconData icon, String label, Color color, {Widget? badge}) =>
        SizedBox(
          width: width,
          height: _item,
          child: Row(
            mainAxisAlignment: labels
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (labels) const SizedBox(width: 18),
              badge ?? Icon(icon, color: color, size: 22),
              if (labels) ...[
                const SizedBox(width: Space.sm),
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ],
          ),
        );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandLogo(width: 64),
          const SizedBox(height: Space.md),
          Tooltip(
            message: labels ? '' : 'New',
            child: Pressable(
              onTap: () => showCreateSheet(context),
              scale: 0.94,
              child: Container(
                width: width + 16,
                height: 52,
                decoration: BoxDecoration(
                  gradient: BrandColors.brandGradient,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: BrandColors.maroon.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.add, color: Colors.white),
                    if (labels) ...[
                      const SizedBox(width: Space.xs),
                      const Text(
                        'New',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          GlassSurface(
            radius: labels ? 30 : 40,
            strong: true,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SizedBox(
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
                                child: row(
                                  shellTabs[i].icon,
                                  shellTabs[i].label,
                                  i == index
                                      ? Colors.white
                                      : scheme.onSurfaceVariant,
                                  badge: _TabBadge(
                                    tab: shellTabs[i],
                                    child: Icon(
                                      i == index
                                          ? shellTabs[i].selectedIcon
                                          : shellTabs[i].icon,
                                      size: 22,
                                      color: i == index
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (links.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                      width: width - 24,
                      child: Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  for (final (path, label, icon) in links)
                    Tooltip(
                      message: labels ? '' : label,
                      preferBelow: false,
                      child: Pressable(
                        onTap: () => context.push(path),
                        scale: 0.92,
                        child: row(icon, label, scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Everyday screens beside the tabs, by permission. The desktop menu and
/// the phone's navigation list the same ones.
List<(String, String, IconData)> shellLinks(
  SessionState session,
  String? siteId,
) => [
  if (session.can('req.triage', siteId: siteId))
    ('/requests', 'Requests', CupertinoIcons.tray_arrow_down),
  if (session.can('req.submit', siteId: siteId) &&
      !session.can('jc.view', siteId: siteId))
    ('/my-requests', 'My requests', CupertinoIcons.paperplane),
  if (session.can('jobs.view', siteId: siteId)) ...[
    ('/checklists', 'Checklists', CupertinoIcons.checkmark_rectangle),
    ('/reports', 'Daily report', CupertinoIcons.doc_chart),
    ('/equipment', 'Equipment & tools', Icons.home_repair_service_outlined),
    if (session.can('docs.view', siteId: siteId))
      ('/documents', 'Documents', CupertinoIcons.book),
  ],
];

/// Phone navigation: every tab and everyday screen in one floating bar that
/// scrolls sideways (the fade at the end shows there is more), with the +
/// fixed at its right end.
class _SwipeTabBar extends ConsumerWidget {
  const _SwipeTabBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final links = shellLinks(
      ref.watch(sessionProvider),
      ref.watch(currentSiteProvider)?.id,
    );
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
          child: Row(
            children: [
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.86, 1],
                  ).createShader(r),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < shellTabs.length; i++)
                        _NavButton(
                          icon: i == index
                              ? shellTabs[i].selectedIcon
                              : shellTabs[i].icon,
                          label: shellTabs[i].label,
                          selected: i == index,
                          tab: shellTabs[i],
                          onTap: () => onTap(i),
                        ),
                      if (links.isNotEmpty)
                        VerticalDivider(
                          width: 13,
                          indent: 12,
                          endIndent: 12,
                          color: scheme.outlineVariant,
                        ),
                      for (final (path, label, icon) in links)
                        _NavButton(
                          icon: icon,
                          label: label,
                          onTap: () => context.push(path),
                        ),
                      const SizedBox(width: Space.lg),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const _CreateButton(),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab or screen on the phone's bar: icon over a short name, with a
/// soft highlight when it is the open tab.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.tab,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Set for the main tabs, so Chat shows its unread badge.
  final ShellTab? tab;

  static String _short(String label) => switch (label) {
    'Equipment & tools' => 'Equipment',
    'Daily report' => 'Report',
    _ => label,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? (dark ? scheme.onSurface : scheme.primary)
        : scheme.onSurfaceVariant;
    final glyph = Icon(icon, color: color, size: 24);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.86,
        hoverScale: 1.1,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          width: 70,
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          decoration: BoxDecoration(
            // Dark glass: the open tab is a brighter pane with a top
            // highlight and a soft burgundy glow underneath.
            color: selected && !dark
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            gradient: selected && dark
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0.07),
                    ],
                  )
                : null,
            border: selected && dark
                ? Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.40),
                    ),
                  )
                : null,
            boxShadow: selected && dark
                ? [
                    BoxShadow(
                      color: BrandColors.maroon.withValues(alpha: 0.55),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              tab == null ? glyph : _TabBadge(tab: tab!, child: glyph),
              const SizedBox(height: 3),
              Text(
                _short(label),
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

/// The round + at the end of the phone's bar.
class _CreateButton extends StatelessWidget {
  const _CreateButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New',
      child: Pressable(
        onTap: () => showCreateSheet(context),
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
  const _TabBadge({required this.tab, required this.child});

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
