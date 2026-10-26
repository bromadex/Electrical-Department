import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../services/core_providers.dart';
import '../services/session_controller.dart';
import '../theme/theme_mode.dart';
import '../widgets/brand_logo.dart';
import '../widgets/notifications_button.dart';
import 'navigation.dart';
import 'reference/reference_data.dart';
import 'theme/tokens.dart';
import 'ui/bits.dart';
import 'widgets/global_search.dart';
import 'widgets/site_picker.dart';

/// The frame around Job Cards Version 2. Desktop: black sidebar + top bar.
/// Tablet: icon rail + top bar. Phone: app bar, role-based bottom bar and a
/// menu drawer. The menu always offers the way back to Version 1.
class V2Shell extends ConsumerStatefulWidget {
  const V2Shell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<V2Shell> createState() => _V2ShellState();
}

class _V2ShellState extends ConsumerState<V2Shell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Lists, settings and the site time zone, loaded once per session.
    ref.watch(referenceDataProvider);
    final width = MediaQuery.sizeOf(context).width;
    final items = visibleNavItems(session.perms);
    final location = GoRouterState.of(context).uri.path;
    final current = navItemFor(location, items);
    final body = _AccountGate(session: session, child: widget.child);

    if (width < Breakpoints.phone) {
      final bottom = phoneNavItems(session.perms);
      final index = bottom.indexWhere((i) => identical(i, current));
      return Scaffold(
        key: _scaffold,
        appBar: AppBar(
          title: Text(current?.label ?? 'Job Cards V2'),
          actions: const [
            GlobalSearchButton(),
            NotificationsButton(),
            SizedBox(width: 4),
          ],
        ),
        drawer: Drawer(
          backgroundColor: AppColors.black,
          child: _NavMenu(
            items: items,
            current: current,
            expanded: true,
            onNavigate: () => _scaffold.currentState?.closeDrawer(),
          ),
        ),
        body: body,
        bottomNavigationBar: bottom.length < 2
            ? null
            : NavigationBar(
                selectedIndex: index < 0 ? bottom.length : index,
                onDestinationSelected: (i) {
                  if (i == bottom.length) {
                    _scaffold.currentState?.openDrawer();
                  } else {
                    context.go(bottom[i].path);
                  }
                },
                destinations: [
                  for (final i in bottom)
                    NavigationDestination(
                      icon: Icon(i.icon),
                      selectedIcon: Icon(i.selectedIcon),
                      label: _short(i.label),
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.menu_rounded),
                    label: 'Menu',
                  ),
                ],
              ),
      );
    }

    final expanded = width >= Breakpoints.desktop;
    return Scaffold(
      key: _scaffold,
      body: Row(
        children: [
          Container(
            width: expanded ? 252 : 76,
            color: AppColors.black,
            child: _NavMenu(items: items, current: current, expanded: expanded),
          ),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _short(String label) => switch (label) {
    'My Assigned Jobs' => 'My Jobs',
    'Incoming Requests' => 'Incoming',
    _ => label,
  };
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const SitePicker(),
          const SizedBox(width: Space.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: const GlobalSearchField(),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          const NotificationsButton(),
        ],
      ),
    );
  }
}

final _versionOne = NavItem(
  '/home',
  'Back to main app',
  Icons.arrow_back_rounded,
  Icons.arrow_back_rounded,
  (_) => true,
);

class _NavMenu extends ConsumerWidget {
  const _NavMenu({
    required this.items,
    required this.current,
    required this.expanded,
    this.onNavigate,
  });

  final List<NavItem> items;
  final NavItem? current;
  final bool expanded;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider.select((s) => s.profile));
    void go(String path) {
      onNavigate?.call();
      context.go(path);
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              expanded ? Space.md : Space.sm,
              Space.md,
              Space.sm,
              Space.md,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: const BrandLogo(width: 44),
                ),
                if (expanded) ...[
                  const SizedBox(width: Space.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bravura',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Job Cards · Version 2',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!Env.isProd)
            Padding(
              padding: const EdgeInsets.only(
                left: Space.md,
                right: Space.md,
                bottom: Space.xs,
              ),
              child: Text(
                expanded ? 'DEV BUILD' : 'DEV',
                style: const TextStyle(
                  color: Color(0xFFFDB022),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              children: [
                _NavTile(
                  item: _versionOne,
                  selected: false,
                  expanded: expanded,
                  onTap: () => go(_versionOne.path),
                ),
                const Divider(color: Colors.white12, height: Space.md),
                for (final item in items)
                  _NavTile(
                    item: item,
                    selected: identical(item, current),
                    expanded: expanded,
                    onTap: () => go(item.path),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          _UserCard(name: profile?.fullName ?? '', expanded: expanded),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.white.withValues(alpha: 0.72);
    final tile = Material(
      color: selected ? AppColors.burgundy : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        hoverColor: Colors.white10,
        child: Container(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: expanded ? Space.sm : 0),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.rose : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: fg,
                size: 22,
              ),
              if (expanded) ...[
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: expanded ? tile : Tooltip(message: item.label, child: tile),
    );
  }
}

/// Theme and sign-out; alerts are switched on in Version 1's More screen.
class _UserCard extends ConsumerWidget {
  const _UserCard({required this.name, required this.expanded});

  final String name;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.over,
      onSelected: (v) {
        switch (v) {
          case 'light':
            ref.read(themeModeProvider.notifier).set(ThemeMode.light);
          case 'dark':
            ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
          case 'system':
            ref.read(themeModeProvider.notifier).set(ThemeMode.system);
          case 'out':
            ref.read(authUserIdProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'light',
          checked: mode == ThemeMode.light,
          child: const Text('Light theme'),
        ),
        CheckedPopupMenuItem(
          value: 'dark',
          checked: mode == ThemeMode.dark,
          child: const Text('Dark theme (night shift)'),
        ),
        CheckedPopupMenuItem(
          value: 'system',
          checked: mode == ThemeMode.system,
          child: const Text('Match device'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'out',
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Row(
          mainAxisAlignment: expanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            AppAvatar(name: name.isEmpty ? '?' : name, size: 34),
            if (expanded) ...[
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Signed in' : name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.more_vert_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Keeps people without a working account (no profile, deactivated, or no
/// role yet) out of the screens, with a clear reason and a way back.
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
        'No access to Version 2',
        'Your roles do not include job cards or requests yet. Ask a system administrator.',
      );
    }
    return child;
  }
}
