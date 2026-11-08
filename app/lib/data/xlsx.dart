import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the first sheet of an Excel .xlsx file as rows of text, for
/// imports (BOQ, inventory items, tools). Numbers come back as written in
/// the file ("12", "2.5"); empty cells as "". Throws [FormatException] for
/// a file that is not an .xlsx workbook.
List<List<String>> readXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('That is not an .xlsx file');
  }
  String? text(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content);
  }

  // Shared strings: cells of type "s" hold an index into this list.
  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final sheetName = _firstSheet(zip, text);
  final sheet = sheetName == null ? null : text(sheetName);
  if (sheet == null) throw const FormatException('The workbook has no sheet');

  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheet).findAllElements('row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : columnIndex(ref);
      next = col + 1;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText;
      final value = switch (type) {
        's' => v == null ? '' : shared[int.parse(v)],
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        'b' => v == '1' ? 'TRUE' : 'FALSE',
        _ => v ?? '',
      };
      cells[col] = value.trim();
    }
    if (cells.values.every((v) => v.isEmpty)) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return rows;
}

/// The first sheet in the workbook's order, via its relationships; falls
/// back to the lowest-numbered worksheet file.
String? _firstSheet(Archive zip, String? Function(String) text) {
  final workbook = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  if (workbook != null && rels != null) {
    final first = XmlDocument.parse(workbook)
        .findAllElements('sheet')
        .firstOrNull;
    final id =
        first?.getAttribute('r:id') ??
        first?.attributes
            .where((a) => a.name.local == 'id')
            .map((a) => a.value)
            .firstOrNull;
    final target = XmlDocument.parse(rels)
        .findAllElements('Relationship')
        .where((r) => r.getAttribute('Id') == id)
        .map((r) => r.getAttribute('Target'))
        .firstOrNull;
    if (target != null) {
      final path = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      if (zip.findFile(path) != null) return path;
    }
  }
  final sheets =
      [
        for (final f in zip.files)
          if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) f.name,
      ]..sort(
        (a, b) => int.parse(
          RegExp(r'\d+').firstMatch(a.substring(14))![0]!,
        ).compareTo(int.parse(RegExp(r'\d+').firstMatch(b.substring(14))![0]!)),
      );
  return sheets.firstOrNull;
}

/// "A1" → 0, "C7" → 2, "AA3" → 26.
int columnIndex(String ref) {
  var n = 0;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Rows from an .xlsx file or a text file (CSV, TSV or pasted cells), so
/// imports accept either.
List<List<String>> readTable(String fileName, Uint8List bytes) {
  if (fileName.toLowerCase().endsWith('.xlsx')) return readXlsx(bytes);
  final text = utf8.decode(bytes, allowMalformed: true);
  return [
    for (final raw in text.split(RegExp(r'\r?\n')))
      if (raw.trim().isNotEmpty)
        [
          for (final c in raw.split(
            raw.contains('\t')
                ? '\t'
                : raw.contains(';')
                ? ';'
                : ',',
          ))
            c.trim().replaceAll(RegExp(r'^"|"$'), ''),
        ],
  ];
}
