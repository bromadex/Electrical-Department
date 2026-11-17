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
  return _readSheet(sheet, shared);
}

/// One sheet's rows; empty rows are left out. Stops after [maxRows].
List<List<String>> _readSheet(
  String xml,
  List<String> shared, {
  int maxRows = 1 << 30,
}) {
  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(xml).findAllElements('row')) {
    if (rows.length >= maxRows) break;
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : columnIndex(ref);
      next = col + 1;
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText;
      final value = switch (type) {
        's' =>
          v == null || (int.tryParse(v) ?? -1) >= shared.length
              ? ''
              : shared[int.parse(v)],
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        'b' => v == '1' ? 'TRUE' : 'FALSE',
        _ => v ?? '',
      };
      cells[col] = value.trim();
    }
    if (cells.isEmpty || cells.values.every((v) => v.isEmpty)) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return rows;
}

/// A sheet of a workbook, for the file viewer.
typedef XlsxSheet = ({String name, List<List<String>> rows});

/// Every sheet of an .xlsx workbook in order, with its name (up to
/// [maxRows] rows each). Throws [FormatException] for a file that is not an
/// .xlsx workbook.
List<XlsxSheet> readXlsxSheets(Uint8List bytes, {int maxRows = 5000}) {
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

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final workbook = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  final out = <XlsxSheet>[];
  if (workbook != null && rels != null) {
    final targets = {
      for (final r in XmlDocument.parse(rels).findAllElements('Relationship'))
        r.getAttribute('Id'): r.getAttribute('Target'),
    };
    for (final s in XmlDocument.parse(workbook).findAllElements('sheet')) {
      final id = s.attributes
          .where((a) => a.name.local == 'id')
          .map((a) => a.value)
          .firstOrNull;
      final target = targets[id];
      if (target == null) continue;
      final path = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      final xml = text(path);
      if (xml == null) continue;
      out.add((
        name: s.getAttribute('name') ?? 'Sheet ${out.length + 1}',
        rows: _readSheet(xml, shared, maxRows: maxRows),
      ));
    }
  }
  if (out.isEmpty) {
    final first = _firstSheet(zip, text);
    final xml = first == null ? null : text(first);
    if (xml == null) throw const FormatException('The workbook has no sheet');
    out.add((name: 'Sheet 1', rows: _readSheet(xml, shared, maxRows: maxRows)));
  }
  return out;
}

/// CSV (or TSV / semicolons) with quoted fields: "a, b" stays one cell and
/// "" inside quotes is a quote.
List<List<String>> parseCsv(String text, {int maxRows = 5000}) {
  final firstLine = text.split('\n').first;
  final sep = firstLine.contains('\t')
      ? '\t'
      : (firstLine.split(';').length > firstLine.split(',').length ? ';' : ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
      if (rows.length >= maxRows) return rows;
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
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
