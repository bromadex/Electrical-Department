import 'package:electrical_department/documents/documents_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DocFolder _f(String id, String name, [String? parent]) => DocFolder.fromJson({
  'id': id,
  'site_id': 's1',
  'name': name,
  'parent_id': parent,
});

void main() {
  final folders = [
    _f('d', 'Drawings'),
    _f('m', 'MCC-3', 'd'),
    _f('p', 'Panels', 'm'),
    _f('s', 'SOPs'),
  ];

  test('the path runs from the top down to the folder', () {
    expect(folderPath(folders, 'p').map((f) => f.name), [
      'Drawings',
      'MCC-3',
      'Panels',
    ]);
    expect(folderPath(folders, null), isEmpty);
    expect(folderPath(folders, 'gone'), isEmpty);
  });

  test('a folder tree holds the folder and everything under it', () {
    expect(folderTree(folders, 'd'), {'d', 'm', 'p'});
    expect(folderTree(folders, 'm'), {'m', 'p'});
    expect(folderTree(folders, 's'), {'s'});
  });

  test('a loop in the data does not hang', () {
    final looped = [_f('a', 'A', 'b'), _f('b', 'B', 'a')];
    expect(folderPath(looped, 'a').length, lessThanOrEqualTo(20));
    expect(folderTree(looped, 'a'), {'a', 'b'});
  });
}
