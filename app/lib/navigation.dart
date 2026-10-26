import 'package:flutter/material.dart';

import 'data/permission_set.dart';

/// A main menu entry, shown only to people whose permissions allow it.
/// Modules from later phases are added here when they are built, so the
/// menu never shows a screen that does not work yet.
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
    '/dashboard',
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
    (p) => p.can('jc.view'),
  ),
  NavItem(
    '/job-cards',
    'Job Cards',
    Icons.assignment_outlined,
    Icons.assignment_rounded,
    (p) => p.can('jc.view'),
  ),
  NavItem(
    '/requests',
    'Incoming Requests',
    Icons.move_to_inbox_outlined,
    Icons.move_to_inbox_rounded,
    (p) => p.can('req.triage'),
  ),
  NavItem(
    '/my-jobs',
    'My Assigned Jobs',
    Icons.engineering_outlined,
    Icons.engineering_rounded,
    (p) => p.can('jc.execute'),
  ),
  NavItem(
    '/my-requests',
    'My Requests',
    Icons.outbox_outlined,
    Icons.outbox_rounded,
    (p) => p.can('req.submit'),
  ),
  NavItem(
    '/assets',
    'Asset Register',
    Icons.precision_manufacturing_outlined,
    Icons.precision_manufacturing_rounded,
    (p) => p.can('assets.view') || p.can('jc.view'),
  ),
  NavItem(
    '/notifications',
    'Notifications',
    Icons.notifications_outlined,
    Icons.notifications_rounded,
    (_) => true,
  ),
  NavItem(
    '/admin/users',
    'User Management',
    Icons.manage_accounts_outlined,
    Icons.manage_accounts_rounded,
    (p) => p.canEverywhere('admin.users'),
  ),
  NavItem(
    '/admin/audit',
    'Audit Logs',
    Icons.history_edu_outlined,
    Icons.history_edu_rounded,
    (p) => p.canEverywhere('audit.view'),
  ),
  NavItem(
    '/admin/settings',
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
    '/my-jobs',
    '/dashboard',
    '/job-cards',
    '/requests',
    '/my-requests',
    '/notifications',
  ];
  final visible = visibleNavItems(p);
  return [for (final path in order) ...visible.where((i) => i.path == path)]
      .take(4)
      .toList();
}

/// Where someone lands after signing in.
String homePath(PermissionSet p) {
  if (p.can('jc.view')) return '/dashboard';
  if (p.can('req.submit')) return '/my-requests';
  return '/notifications';
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
