import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_repository.dart';
import '../documents/documents_repository.dart';
import '../router.dart';
import '../services/core_providers.dart';
import '../services/notifications_controller.dart';
import '../services/session_controller.dart';
import '../theme/tokens.dart';
import '../ui/motion.dart';
import '../ui/surfaces.dart';
import 'brand_logo.dart';
import 'create_sheet.dart';

/// Whether the app-wide side bar is showing (so the tab layout leaves out
/// its own navigation and keeps the computer layout).
class SideBarScope extends InheritedWidget {
  const SideBarScope({super.key, required this.shown, required super.child});

  final bool shown;

  static bool shownOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideBarScope>()?.shown ??
      false;

  @override
  bool updateShouldNotify(SideBarScope old) => old.shown != shown;
}

/// The side bar on computers and tablets, on every page (not only the
/// main tabs): New, Home, Jobs, Menu, the everyday screens, Chat, Meetings
/// and Settings, with the page you are on lit up. The button at the bottom
/// collapses it to icons and back; the choice is kept on the device.
/// Phones keep their bottom bar.
class SideBarLayer extends ConsumerStatefulWidget {
  const SideBarLayer({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Narrower than this, the phone layout (bottom bar) is used instead.
  static const minWidth = 720.0;

  static const expandedWidth = 216.0;
  static const collapsedWidth = 72.0;

  static bool hiddenOn(String path) =>
      path == '/login' ||
      path == '/first-password' ||
      path.startsWith('/guest/') ||
      path.endsWith('/call');

  @override
  ConsumerState<SideBarLayer> createState() => _SideBarLayerState();
}

class _SideBarLayerState extends ConsumerState<SideBarLayer> {
  static const _key = 'sidebar_collapsed';
  bool? _collapsed;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_changed);
    SharedPreferences.getInstance()
        .then((p) {
          if (mounted && p.containsKey(_key)) {
            setState(() => _collapsed = p.getBool(_key));
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle(bool collapsed) {
    HapticFeedback.selectionClick();
    setState(() => _collapsed = !collapsed);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_key, !collapsed))
        .catchError((_) => false);
  }

  String get _path {
    try {
      // The top page, including ones pushed on top (Chat from the green
      // button or ➕), which the address bar does not show.
      final config = widget.router.routerDelegate.currentConfiguration;
      if (config.isEmpty) return '';
      return Uri.parse(config.last.matchedLocation).path;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final signedIn = ref.watch(authUserIdProvider) != null;
    final path = _path;
    final show =
        signedIn &&
        mq.size.width >= SideBarLayer.minWidth &&
        !SideBarLayer.hiddenOn(path);
    if (!show) return SideBarScope(shown: false, child: widget.child);
    // Expanded by default on wide windows, icons only on narrower ones,
    // until someone chooses.
    final collapsed = _collapsed ?? mq.size.width < 1100;
    final width = collapsed
        ? SideBarLayer.collapsedWidth
        : SideBarLayer.expandedWidth;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SideBarScope(
      shown: true,
      child: ColoredBox(
        color: dark ? AppColors.night : AppColors.canvas,
        child: Row(
          children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Curves.easeOut,
              width: width,
              // The bar sits outside the pages, so it brings its own
              // Material (text sizes, ink) like a page would.
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 14),
                  child: _SideBar(
                    path: path,
                    collapsed: collapsed,
                    router: widget.router,
                    onToggle: () => _toggle(collapsed),
                  ),
                ),
              ),
            ),
            Expanded(
              // The page sees only the space beside the bar, so its own
              // layout (one or two columns) still fits.
              child: MediaQuery(
                data: mq.copyWith(
                  size: Size(mq.size.width - width, mq.size.height),
                  padding: mq.padding.copyWith(left: 0),
                ),
                child: ClipRect(child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideBar extends ConsumerWidget {
  const _SideBar({
    required this.path,
    required this.collapsed,
    required this.router,
    required this.onToggle,
  });

  final String path;
  final bool collapsed;
  final GoRouter router;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionProvider);
    final unreadChats = (ref.watch(conversationsProvider).value ?? const [])
        .where((c) => c.unread > 0 && !c.muted)
        .length;
    final unreadAlerts = ref.watch(
      notificationsProvider.select((s) => s.unread),
    );
    final toSign = ref.watch(toSignCountProvider);
    // The bar is the menu on wide screens: every page from the Menu tab, in
    // groups, and no "Menu" entry of its own.
    final top = <_Item>[
      for (final t in shellTabs)
        if (t.path != '/menu') (t.path, t.label, t.icon, t.selectedIcon, 0),
      if (session.can('chat.use'))
        (
          '/chat',
          'Chat',
          CupertinoIcons.chat_bubble_2,
          CupertinoIcons.chat_bubble_2_fill,
          unreadChats,
        ),
    ];
    _Item one(String p, String l, IconData i, [int badge = 0]) =>
        (p, l, i, i, badge);
    final groups = <(String, List<_Item>)>[
      (
        'Work',
        [
          if (session.can('req.triage'))
            one('/requests', 'Requests', CupertinoIcons.tray_arrow_down),
          if (session.can('req.submit'))
            one('/my-requests', 'My requests', CupertinoIcons.paperplane),
          one('/checklists', 'Checklists', CupertinoIcons.checkmark_rectangle),
          one('/reports', 'Daily report', CupertinoIcons.doc_chart),
          if (session.can('jobs.assign'))
            one(
              '/jobs/recurring',
              'Planned maintenance',
              CupertinoIcons.arrow_2_circlepath,
            ),
          if (session.can('jc.view'))
            one('/job-stats', 'Job statistics', CupertinoIcons.chart_bar),
          one('/meetings', 'Meetings', CupertinoIcons.person_3),
        ],
      ),
      (
        'Stores',
        [
          one(
            '/equipment',
            'Equipment & tools',
            Icons.home_repair_service_outlined,
          ),
          if (session.can('store.view')) ...[
            one('/inventory', 'Inventory', CupertinoIcons.cube_box),
            one('/materials', 'Materials', CupertinoIcons.cart),
          ],
          if (session.can('tools.view'))
            one('/tools/stats', 'Tool stats', CupertinoIcons.graph_square),
        ],
      ),
      (
        'Planning',
        [
          if (session.can('jc.view')) ...[
            one('/projects', 'Projects', CupertinoIcons.flag),
            one('/calendar', 'Calendar', CupertinoIcons.calendar),
            one('/roster', 'Roster', CupertinoIcons.person_2_square_stack),
          ],
          one('/documents', 'Documents', CupertinoIcons.book, toSign),
        ],
      ),
      (
        'Me',
        [
          one('/reminders', 'Reminders', CupertinoIcons.alarm),
          one(
            '/notifications',
            'Notifications',
            CupertinoIcons.bell,
            unreadAlerts,
          ),
        ],
      ),
    ];

    bool on(String p) =>
        path == p ||
        (p != '/' && path.startsWith('$p/')) ||
        (p == '/jobs' &&
            path.startsWith('/jobs') &&
            !path.startsWith('/jobs/recurring'));

    void go(String p) {
      HapticFeedback.selectionClick();
      router.go(p);
    }

    Widget item(_Item it) {
      final (p, label, icon, selected, badge) = it;
      final lit = on(p);
      final fg = lit ? Colors.white : scheme.onSurfaceVariant;
      final glyph = Badge(
        isLabelVisible: badge > 0,
        backgroundColor: const Color(0xFFE5484D),
        label: Text(badge > 99 ? '99+' : '$badge'),
        child: Icon(lit ? selected : icon, size: 21, color: fg),
      );
      return Semantics(
        label: label,
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Pressable(
            onTap: () => go(p),
            scale: 0.95,
            child: Container(
              height: 44,
              decoration: lit
                  ? BoxDecoration(
                      gradient: BrandColors.brandGradient,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    )
                  // An empty decoration still takes taps across the row.
                  : const BoxDecoration(),
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  glyph,
                  if (!collapsed) ...[
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w600,
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
    }

    // A group's name; collapsed, just a thin line.
    Widget heading(String title) => collapsed
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          );

    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
        child: GlassSurface(
          radius: 28,
          strong: true,
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              const SizedBox(height: 6),
              BrandLogo(width: collapsed ? 40 : 72),
              const SizedBox(height: Space.sm),
              // + New: the quick-create sheet.
              Semantics(
                label: 'New',
                button: true,
                child: Pressable(
                  onTap: () {
                    final ctx =
                        router.routerDelegate.navigatorKey.currentContext;
                    if (ctx != null) showCreateSheet(ctx);
                  },
                  scale: 0.94,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: BrandColors.brandGradient,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      boxShadow: [
                        BoxShadow(
                          color: BrandColors.maroon.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.add, color: Colors.white),
                        if (!collapsed) ...[
                          const SizedBox(width: Space.xs),
                          const Text(
                            'New',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final it in top) item(it),
                    for (final (title, list) in groups)
                      if (list.isNotEmpty) ...[
                        heading(title),
                        for (final it in list) item(it),
                      ],
                  ],
                ),
              ),
              item((
                '/settings',
                'Settings',
                CupertinoIcons.gear,
                CupertinoIcons.gear_solid,
                0,
              )),
              const SizedBox(height: 4),
              Semantics(
                label: collapsed ? 'Expand the menu' : 'Collapse the menu',
                button: true,
                child: Pressable(
                  onTap: onToggle,
                  scale: 0.94,
                  child: Container(
                    height: 40,
                    decoration: const BoxDecoration(),
                    child: Row(
                      mainAxisAlignment: collapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        if (!collapsed) const SizedBox(width: 14),
                        Icon(
                          collapsed
                              ? CupertinoIcons.sidebar_right
                              : CupertinoIcons.sidebar_left,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        if (!collapsed) ...[
                          const SizedBox(width: Space.sm),
                          Text(
                            'Collapse',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}

typedef _Item = (String, String, IconData, IconData, int);
