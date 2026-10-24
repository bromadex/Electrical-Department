import 'package:electrical_department/data/permission_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final perms = PermissionSet([
    (code: 'jc.view', siteId: 'kam'),
    (code: 'jc.view', siteId: 'sel'),
    (code: 'reports.view', siteId: null),
  ]);

  test('site-scoped grant applies only to that site', () {
    expect(perms.can('jc.view', siteId: 'kam'), isTrue);
    expect(perms.can('jc.view', siteId: 'hre'), isFalse);
  });

  test('all-site grant applies everywhere', () {
    expect(perms.can('reports.view', siteId: 'hre'), isTrue);
    expect(perms.canEverywhere('reports.view'), isTrue);
    expect(perms.canEverywhere('jc.view'), isFalse);
  });

  test('without a site, any grant counts', () {
    expect(perms.can('jc.view'), isTrue);
    expect(perms.can('jc.assign'), isFalse);
  });

  test('any permission at a site gives access to it', () {
    expect(perms.hasAnyAt('sel'), isTrue);
    expect(
      perms.hasAnyAt('hre'),
      isTrue,
    ); // reports.view is granted at all sites
    expect(
      PermissionSet([(code: 'jc.view', siteId: 'kam')]).hasAnyAt('hre'),
      isFalse,
    );
  });

  test('empty set grants nothing', () {
    expect(PermissionSet.empty().can('jc.view'), isFalse);
    expect(PermissionSet.empty().isEmpty, isTrue);
  });
}
