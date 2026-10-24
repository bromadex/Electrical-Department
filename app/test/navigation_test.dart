import 'package:electrical_department/data/permission_set.dart';
import 'package:electrical_department/navigation.dart';
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
    'admin.users',
    'settings.manage',
    'jc.execute',
  ]);

  test('an electrician sees field work, not administration or triage', () {
    final paths = _paths(electrician);
    expect(
      paths,
      containsAll([
        '/dashboard',
        '/job-cards',
        '/my-jobs',
        '/assets',
        '/notifications',
      ]),
    );
    expect(paths, isNot(contains('/admin/users')));
    expect(paths, isNot(contains('/admin/settings')));
    expect(paths, isNot(contains('/requests')));
  });

  test('an engineer triages requests but cannot administer', () {
    final paths = _paths(engineer);
    expect(paths, contains('/requests'));
    expect(paths, isNot(contains('/my-jobs')));
    expect(paths, isNot(contains('/admin/users')));
  });

  test('a requester only sees their requests and notifications', () {
    expect(_paths(requester), ['/my-requests', '/notifications']);
    expect(homePath(requester), '/my-requests');
  });

  test('administration needs the grant at all sites', () {
    expect(_paths(admin), containsAll(['/admin/users', '/admin/settings']));
    final siteAdmin = _grants(['admin.users', 'settings.manage'], site: 'kam');
    expect(_paths(siteAdmin), isNot(contains('/admin/users')));
  });

  test('the phone bar puts field work first and keeps four entries', () {
    final bar = phoneNavItems(admin);
    expect(bar, hasLength(4));
    expect(bar.first.path, '/my-jobs');
  });

  test('a detail page highlights its menu entry', () {
    final items = visibleNavItems(admin);
    expect(navItemFor('/job-cards/EL-JC-2026-0001', items)?.path, '/job-cards');
    expect(navItemFor('/admin/settings', items)?.path, '/admin/settings');
    expect(navItemFor('/elsewhere', items), isNull);
  });

  test('people land on the first screen they can use', () {
    expect(homePath(electrician), '/dashboard');
    expect(homePath(PermissionSet.empty()), '/notifications');
  });
}
