import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import '../router.dart';
import '../services/session_controller.dart';
import 'notifications_button.dart';
import 'site_picker.dart';
import 'sync_banner.dart';

/// Phone: bottom navigation bar. Wider screens: side menu (API build plan,
/// week 1). Shows account problems instead of the tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  /// Below this width the app uses the phone layout.
  static const phoneMaxWidth = 720.0;

  /// From this width the side menu shows labels.
  static const wideMinWidth = 1100.0;

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < phoneMaxWidth;
    final tab = shellTabs[shell.currentIndex];

    void go(int i) =>
        shell.goBranch(i, initialLocation: i == shell.currentIndex);

    final body = Column(
      children: [
        const SyncBanner(),
        if (session.error != null && session.profile != null)
          MaterialBanner(
            leading: const Icon(Icons.wifi_off),
            content: Text('Showing saved data. ${session.error!.message}'),
            actions: [
              TextButton(
                onPressed: ref.read(sessionProvider.notifier).refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: _AccountGate(session: session, child: shell),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(tab.label),
            if (!Env.isProd) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(Env.flavor.toUpperCase()),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        actions: const [
          SitePicker(),
          NotificationsButton(),
          SizedBox(width: 8),
        ],
      ),
      body: phone
          ? body
          : Row(
              children: [
                NavigationRail(
                  extended: width >= wideMinWidth,
                  labelType: width >= wideMinWidth
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: go,
                  destinations: [
                    for (final t in shellTabs)
                      NavigationRailDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        label: Text(t.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
      bottomNavigationBar: phone
          ? NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: go,
              destinations: [
                for (final t in shellTabs)
                  NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.selectedIcon),
                    label: t.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _AccountGate extends StatelessWidget {
  const _AccountGate({required this.session, required this.child});

  final SessionState session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (session.profile == null) {
      if (session.error != null) {
        return _Message(
          icon: Icons.wifi_off,
          title: 'Could not load your account',
          body: session.error!.message,
        );
      }
      if (!session.refreshed) {
        return const Center(child: CircularProgressIndicator());
      }
      return const _Message(
        icon: Icons.person_off_outlined,
        title: 'Account not active',
        body:
            'Your account is not active or has not been set up yet. '
            'Ask an admin to activate it and give you a role.',
      );
    }
    if (session.perms.isEmpty) {
      return const _Message(
        icon: Icons.lock_outline,
        title: 'No role yet',
        body: 'Ask an admin to give you a role so you can start working.',
      );
    }
    return child;
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
