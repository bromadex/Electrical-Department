import 'package:electrical_department/documents/offline/offline_docs.dart';
import 'package:electrical_department/documents/viewer/file_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each file type opens in the right viewer', () {
    expect(viewerFor('LOTO.PDF')?.name, 'PDF');
    expect(viewerFor('panel photo.jpeg')?.name, 'Image');
    expect(viewerFor('readings.csv')?.name, 'Table');
    expect(viewerFor('stock.xlsx')?.name, 'Excel');
    expect(viewerFor('report.docx')?.name, 'Word');
    expect(viewerFor('index.HTML')?.name, 'Web page');
    expect(viewerFor('MCC-3.dxf')?.name, 'Drawing');
    expect(viewerFor('notes.txt')?.name, 'Text');
    expect(viewerFor('MCC-3.dwg'), isNull);
    expect(viewerFor('no extension'), isNull);
  });

  test('types the app cannot show say so', () {
    expect(viewerLabel('MCC-3.dwg'), 'DWG drawing (open elsewhere)');
    expect(viewerLabel('old.doc'), 'Word 97 document (open elsewhere)');
    expect(viewerLabel('LOTO.pdf'), 'PDF');
    expect(canViewInApp('a.png'), isTrue);
    expect(canViewInApp('a.zip'), isFalse);
  });

  test('a kept copy survives being saved and read back', () {
    final c = OfflineCopy(
      docId: 'd1',
      version: 3,
      fileName: 'loto.pdf',
      file: 'd1-v3-loto.pdf',
      size: 2048,
      savedAt: DateTime.utc(2026, 11, 17, 9),
    );
    final back = OfflineCopy.fromJson(c.toJson());
    expect(back.docId, 'd1');
    expect(back.version, 3);
    expect(back.file, 'd1-v3-loto.pdf');
    expect(back.size, 2048);
    expect(back.savedAt, c.savedAt);
  });
}
