import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:electrical_department/data/xlsx.dart';
import 'package:electrical_department/documents/viewer/docx.dart';
import 'package:electrical_department/documents/viewer/dxf.dart';
import 'package:electrical_department/documents/viewer/table_view.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('every sheet of a workbook, with its name', () {
    final bytes = _zip({
      'xl/workbook.xml':
          '<workbook xmlns:r="r"><sheets>'
          '<sheet name="Stock" r:id="rId1"/><sheet name="Prices" r:id="rId2"/>'
          '</sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<Relationships>'
          '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Target="worksheets/sheet2.xml"/>'
          '</Relationships>',
      'xl/sharedStrings.xml':
          '<sst><si><t>Cable</t></si><si><t>Qty</t></si></sst>',
      'xl/worksheets/sheet1.xml':
          '<worksheet><sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
          '<row r="2"><c r="A2" t="inlineStr"><is><t>6mm</t></is></c><c r="C2"><v>12</v></c></row>'
          '</sheetData></worksheet>',
      'xl/worksheets/sheet2.xml': '<worksheet><sheetData><row r="1"><c r="A1"><v>3.5</v></c></row></sheetData></worksheet>',
    });
    final sheets = readXlsxSheets(bytes);
    expect(sheets.map((s) => s.name), ['Stock', 'Prices']);
    expect(sheets[0].rows, [
      ['Cable', 'Qty'],
      ['6mm', '', '12'],
    ]);
    expect(sheets[1].rows, [
      ['3.5'],
    ]);
    expect(
      () => readXlsxSheets(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('CSV keeps quoted commas and quotes', () {
    expect(
      parseCsv('Item,Note\r\n"Cable, 6mm","Says ""keep dry"""\n\nLug,ok'),
      [
        ['Item', 'Note'],
        ['Cable, 6mm', 'Says "keep dry"'],
        ['Lug', 'ok'],
      ],
    );
    expect(parseCsv('a;b;c\n1;2;3'), [
      ['a', 'b', 'c'],
      ['1', '2', '3'],
    ]);
    expect(columnName(0), 'A');
    expect(columnName(25), 'Z');
    expect(columnName(26), 'AA');
  });

  test('a Word document becomes headings, styled runs, lists and tables', () {
    const w = 'xmlns:w="w"';
    final bytes = _zip({
      'word/document.xml':
          '<w:document $w><w:body>'
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>LOTO</w:t></w:r></w:p>'
          '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Isolate</w:t></w:r>'
          '<w:r><w:t xml:space="preserve"> first</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/></w:numPr></w:pPr><w:r><w:t>Lock</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr><w:r><w:t>Tag</w:t></w:r></w:p>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
          '</w:body></w:document>',
    });
    final blocks = readDocx(bytes);
    final h = blocks[0] as DocxParagraph;
    expect((h.heading, h.text), (1, 'LOTO'));
    final p = blocks[1] as DocxParagraph;
    expect(p.text, 'Isolate first');
    expect(p.runs.first.bold, isTrue);
    expect(p.runs.last.bold, isFalse);
    expect((blocks[2] as DocxParagraph).listLevel, 1);
    expect(
      (blocks[3] as DocxParagraph).listLevel,
      0,
      reason: 'a List Bullet style is a list too',
    );
    final t = blocks[4] as DocxTable;
    expect(t.rows.single.map((c) => c.single.text), ['A', 'B']);
    expect(() => readDocx(Uint8List.fromList([0, 1])), throwsFormatException);
  });

  test('a DXF drawing gives its shapes, blocks placed and layer colours', () {
    const dxf = '''0
SECTION
2
TABLES
0
LAYER
2
POWER
62
1
0
ENDSEC
0
SECTION
2
BLOCKS
0
BLOCK
2
LAMP
10
0
20
0
0
CIRCLE
10
0
20
0
40
1
0
ENDBLK
0
ENDSEC
0
SECTION
2
ENTITIES
0
LINE
8
POWER
10
0
20
0
11
10
21
0
0
LWPOLYLINE
90
3
70
1
10
0
20
0
10
5
20
0
10
5
20
5
0
TEXT
10
1
20
1
40
2
1
MCC-3
0
INSERT
2
LAMP
10
20
20
10
41
2
0
ENDSEC
0
EOF
''';
    final d = readDxf(dxf);
    final line = d.shapes.whereType<DxfLine>().single;
    expect(line.color, 1, reason: 'by layer: POWER is red');
    final poly = d.shapes.whereType<DxfPolyline>().single;
    expect((poly.points.length, poly.closed), (3, true));
    expect(d.shapes.whereType<DxfText>().single.text, 'MCC-3');
    final lamp = d.shapes.whereType<DxfCircle>().single;
    expect(lamp.centre.dx, 20);
    expect(lamp.centre.dy, 10);
    expect(lamp.radius, 2, reason: 'the block is placed at 2× size');
    expect(d.bounds.right, 22);
    expect(() => readDxf('hello'), throwsFormatException);
  });
}
