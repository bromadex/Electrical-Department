import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:electrical_department/data/xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small workbook as Excel writes it: shared strings, numbers, an
/// inline string, a skipped column and an empty row.
Uint8List workbook() {
  final files = {
    'xl/workbook.xml':
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="BOQ" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>',
    'xl/sharedStrings.xml':
        '<sst><si><t>Description</t></si><si><t>Unit</t></si><si><t>Qty</t></si>'
        '<si><t>2.5mm twin and earth</t></si><si><r><t>Isolator </t></r><r><t>63A</t></r></si>'
        '<si><t>m</t></si><si><t>pcs</t></si></sst>',
    'xl/worksheets/sheet1.xml':
        '<worksheet><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>5</v></c><c r="C2"><v>500</v></c></row>'
        '<row r="3"></row>'
        '<row r="4"><c r="A4" t="s"><v>4</v></c><c r="B4" t="s"><v>6</v></c><c r="C4"><v>2.5</v></c></row>'
        '<row r="5"><c r="A5" t="inlineStr"><is><t>Lugs</t></is></c><c r="C5"><v>20</v></c></row>'
        '</sheetData></worksheet>',
  };
  final archive = Archive();
  for (final e in files.entries) {
    final data = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('reads the first sheet of a workbook as rows of text', () {
    expect(readXlsx(workbook()), [
      ['Description', 'Unit', 'Qty'],
      ['2.5mm twin and earth', 'm', '500'],
      ['Isolator 63A', 'pcs', '2.5'],
      ['Lugs', '', '20'],
    ]);
  });

  test('a file that is not a workbook is refused', () {
    expect(
      () => readXlsx(Uint8List.fromList(utf8.encode('just text'))),
      throwsFormatException,
    );
  });

  test('columns by letter', () {
    expect(columnIndex('A1'), 0);
    expect(columnIndex('C7'), 2);
    expect(columnIndex('AA3'), 26);
  });

  test('CSV and pasted cells read the same way as a workbook', () {
    expect(readTable('boq.csv', utf8.encode('Lugs,pcs,20\nCable;m;5')), [
      ['Lugs', 'pcs', '20'],
      ['Cable', 'm', '5'],
    ]);
    expect(readTable('boq.xlsx', workbook()).length, 4);
  });
}
