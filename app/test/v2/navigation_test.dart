import 'package:electrical_department/data/permission_set.dart';
import 'package:electrical_department/v2/navigation.dart';
import 'package:flutter_test/flutter_test.dart';

PermissionSet _grants(List<String> codes, {String? site}) =>
    PermissionSet([for (final c in codes) (code: c, siteId: site)]);

List<String> _paths(PermissionSet p) => [
  for (final i in visibleNavItems(p)) i.path,
];

void main() {
  final electrician = _grants([
    'jc.view',
    'jc.execute',
    'assets.view',
  ], site: 'kam');
  final engineer = _grants([
    'jc.view',
    'jc.register',
    'jc.assess',
    'jc.assign',
    'jc.review',
    'req.triage',
    'assets.manage',
  ], site: 'kam');
  final requester = _grants(['req.submit'], site: 'kam');
  final admin = _grants([
    'jc.view',
    'req.triage',
    'req.submit',
    'audit.view',
    'settings.manage',
    'jc.execute',
  ]);

  test('an electrician sees field work, not settings or triage', () {
    final paths = _paths(electrician);
    expect(
      paths,
      containsAll(['/v2/dashboard', '/v2/job-cards', '/v2/my-jobs']),
    );
    expect(paths, isNot(contains('/v2/settings')));
    expect(paths, isNot(contains('/v2/requests')));
  });

  test('an engineer triages requests but cannot change settings', () {
    final paths = _paths(engineer);
    expect(paths, contains('/v2/requests'));
    expect(paths, isNot(contains('/v2/my-jobs')));
    expect(paths, isNot(contains('/v2/settings')));
  });

  test('a requester only sees their requests', () {
    expect(_paths(requester), ['/v2/my-requests']);
    expect(homePath(requester), '/v2/my-requests');
  });

  test('settings and the audit log need the grant at all sites', () {
    expect(_paths(admin), containsAll(['/v2/audit', '/v2/settings']));
    final siteAdmin = _grants(['audit.view', 'settings.manage'], site: 'kam');
    expect(_paths(siteAdmin), isNot(contains('/v2/settings')));
  });

  test('version 2 menus never point outside version 2', () {
    for (final i in visibleNavItems(admin)) {
      expect(i.path, startsWith('/v2/'));
    }
  });

  test('the phone bar puts field work first and keeps three entries', () {
    final bar = phoneNavItems(admin);
    expect(bar, hasLength(3));
    expect(bar.first.path, '/v2/my-jobs');
  });

  test('a detail page highlights its menu entry', () {
    final items = visibleNavItems(admin);
    expect(
      navItemFor('/v2/job-cards/EL-JC-2026-0001', items)?.path,
      '/v2/job-cards',
    );
    expect(navItemFor('/v2/settings', items)?.path, '/v2/settings');
    expect(navItemFor('/home', items), isNull);
  });

  test('version 2 opens on the first screen people can use', () {
    expect(homePath(electrician), '/v2/dashboard');
    expect(homePath(PermissionSet.empty()), '/home');
  });
}
