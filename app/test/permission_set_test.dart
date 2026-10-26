import 'package:electrical_department/data/permission_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final perms = PermissionSet([
    (code: 'jobs.view', siteId: 'kam'),
    (code: 'jobs.view', siteId: 'sel'),
    (code: 'stats.view', siteId: null),
  ]);

  test('site-scoped grant applies only to that site', () {
    expect(perms.can('jobs.view', siteId: 'kam'), isTrue);
    expect(perms.can('jobs.view', siteId: 'hre'), isFalse);
  });

  test('all-site grant applies everywhere', () {
    expect(perms.can('stats.view', siteId: 'hre'), isTrue);
    expect(perms.canEverywhere('stats.view'), isTrue);
    expect(perms.canEverywhere('jobs.view'), isFalse);
  });

  test('without a site, any grant counts', () {
    expect(perms.can('jobs.view'), isTrue);
    expect(perms.can('jobs.assign'), isFalse);
  });

  test('empty set grants nothing', () {
    expect(PermissionSet.empty().can('jobs.view'), isFalse);
    expect(PermissionSet.empty().isEmpty, isTrue);
  });
}
