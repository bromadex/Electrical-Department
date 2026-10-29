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

  test('views at every site, work only where you have a role', () {
    final p = PermissionSet([
      (code: 'docs.view', siteId: null),
      (code: 'jc.execute', siteId: 'kam'),
      (code: 'site.member', siteId: 'kam'),
    ]);
    expect(p.can('docs.view', siteId: 'hre'), isTrue);
    expect(p.hasAnyAt('hre'), isTrue);
    expect(p.worksAt('kam'), isTrue);
    expect(p.worksAt('hre'), isFalse);
  });

  test('before the server sends site.member, any grant at a site counts', () {
    expect(perms.worksAt('kam'), isTrue);
    expect(perms.worksAt('xyz'), isTrue); // stats.view at all sites
    expect(
      PermissionSet([(code: 'jobs.view', siteId: 'kam')]).worksAt('sel'),
      isFalse,
    );
  });

  test('empty set grants nothing', () {
    expect(PermissionSet.empty().can('jobs.view'), isFalse);
    expect(PermissionSet.empty().isEmpty, isTrue);
  });
}
