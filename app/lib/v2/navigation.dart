import 'package:flutter/material.dart';

import '../data/permission_set.dart';

/// A Job Cards Version 2 menu entry, shown only to people whose permissions
/// allow it. Assets, notifications and people stay in Version 1 screens.
class NavItem {
  const NavItem(
    this.path,
    this.label,
    this.icon,
    this.selectedIcon,
    this.visible,
  );

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool Function(PermissionSet p) visible;
}

final navItems = <NavItem>[
  NavItem(
    '/v2/dashboard',
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
    (p) => p.can('jc.view'),
  ),
  NavItem(
    '/v2/job-cards',
    'Job Cards',
    Icons.assignment_outlined,
    Icons.assignment_rounded,
    (p) => p.can('jc.view'),
  ),
  NavItem(
    '/v2/requests',
    'Incoming Requests',
    Icons.move_to_inbox_outlined,
    Icons.move_to_inbox_rounded,
    (p) => p.can('req.triage'),
  ),
  NavItem(
    '/v2/my-jobs',
    'My Assigned Jobs',
    Icons.engineering_outlined,
    Icons.engineering_rounded,
    (p) => p.can('jc.execute'),
  ),
  NavItem(
    '/v2/my-requests',
    'My Requests',
    Icons.outbox_outlined,
    Icons.outbox_rounded,
    (p) => p.can('req.submit'),
  ),
  NavItem(
    '/v2/audit',
    'Audit Logs',
    Icons.history_edu_outlined,
    Icons.history_edu_rounded,
    (p) => p.canEverywhere('audit.view'),
  ),
  NavItem(
    '/v2/settings',
    'Settings',
    Icons.settings_outlined,
    Icons.settings_rounded,
    (p) => p.canEverywhere('settings.manage'),
  ),
];

List<NavItem> visibleNavItems(PermissionSet p) => [
  for (final i in navItems)
    if (i.visible(p)) i,
];

/// Up to four entries for the phone's bottom bar, field work first.
List<NavItem> phoneNavItems(PermissionSet p) {
  const order = [
    '/v2/my-jobs',
    '/v2/dashboard',
    '/v2/job-cards',
    '/v2/requests',
    '/v2/my-requests',
    '/v2/settings',
  ];
  final visible = visibleNavItems(p);
  return [for (final path in order) ...visible.where((i) => i.path == path)]
      .take(4)
      .toList();
}

/// Where Version 2 opens; people with no part in it go back to Version 1.
String homePath(PermissionSet p) {
  if (p.can('jc.view')) return '/v2/dashboard';
  if (p.can('req.submit')) return '/v2/my-requests';
  return '/home';
}

/// The menu entry a location belongs to (for highlighting and titles).
NavItem? navItemFor(String location, List<NavItem> items) {
  NavItem? best;
  for (final i in items) {
    if (location == i.path || location.startsWith('${i.path}/')) {
      if (best == null || i.path.length > best.path.length) best = i;
    }
  }
  return best;
}
