import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/xlsx.dart';
import '../../theme/tokens.dart';
import 'file_viewer.dart';

/// Excel workbooks (.xlsx): every sheet, as a tab.
class ExcelViewer extends FileViewer {
  const ExcelViewer();

  @override
  String get name => 'Excel';

  @override
  Set<String> get extensions => const {'xlsx', 'xlsm'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) {
    final List<XlsxSheet> sheets;
    try {
      sheets = readXlsxSheets(bytes);
    } on FormatException catch (e) {
      return Center(child: Text(e.message));
    }
    return SheetsView(sheets: sheets);
  }
}

/// CSV, TSV and semicolon files, as a table.
class CsvViewer extends FileViewer {
  const CsvViewer();

  @override
  String get name => 'Table';

  @override
  Set<String> get extensions => const {'csv', 'tsv'};

  @override
  Widget build(BuildContext context, Uint8List bytes, String fileName) =>
      SheetsView(
        sheets: [
          (
            name: fileName,
            rows: parseCsv(utf8.decode(bytes, allowMalformed: true)),
          ),
        ],
      );
}

/// Sheets as tabs; each a grid with column letters and row numbers. The
/// first row stays at the top while scrolling (usually the headings).
class SheetsView extends StatefulWidget {
  const SheetsView({super.key, required this.sheets});

  final List<XlsxSheet> sheets;

  @override
  State<SheetsView> createState() => _SheetsViewState();
}

class _SheetsViewState extends State<SheetsView> {
  int _at = 0;

  @override
  Widget build(BuildContext context) {
    final sheets = widget.sheets;
    if (sheets.isEmpty) return const Center(child: Text('The file is empty'));
    final sheet = sheets[_at.clamp(0, sheets.length - 1)];
    return Column(
      children: [
        if (sheets.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              children: [
                for (final (i, s) in sheets.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs, top: 6),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: i == _at,
                      onSelected: (_) => setState(() => _at = i),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _Grid(key: ValueKey(_at), rows: sheet.rows),
        ),
      ],
    );
  }
}

/// "A" for 0, "Z" for 25, "AA" for 26.
String columnName(int i) {
  var n = i + 1;
  final out = StringBuffer();
  final chars = <String>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    chars.insert(0, String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  out.writeAll(chars);
  return out.toString();
}

class _Grid extends StatelessWidget {
  const _Grid({super.key, required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (rows.isEmpty) return const Center(child: Text('This sheet is empty'));
    final cols = rows.fold<int>(0, (n, r) => math.max(n, r.length));
    // Column widths from the longest text in the first 200 rows.
    final widths = [
      for (var c = 0; c < cols; c++)
        rows
                    .take(200)
                    .map((r) => c < r.length ? r[c].length : 0)
                    .fold<int>(3, math.max)
                    .clamp(3, 40) *
                8.0 +
            20,
    ];
    const rowNo = 48.0;
    const h = 32.0;
    final total = rowNo + widths.fold<double>(0, (a, b) => a + b);
    final border = BorderSide(color: scheme.outlineVariant, width: 0.5);
    final numStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget line(int i, {bool head = false, bool letters = false}) {
      final r = letters ? const <String>[] : rows[i];
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: letters
              ? scheme.surfaceContainerHighest
              : head
              ? scheme.surfaceContainerHigh
              : (i.isEven ? scheme.surface : scheme.surfaceContainerLowest),
          border: Border(bottom: border),
        ),
        child: Row(
          children: [
            Container(
              width: rowNo,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border(right: border),
              ),
              child: Text(letters ? '' : '${i + 1}', style: numStyle),
            ),
            for (var c = 0; c < cols; c++)
              Container(
                width: widths[c],
                alignment: letters ? Alignment.center : Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(border: Border(right: border)),
                child: Text(
                  letters ? columnName(c) : (c < r.length ? r[c] : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: letters
                      ? numStyle
                      : theme.textTheme.bodySmall?.copyWith(
                          fontWeight: head ? FontWeight.w700 : null,
                        ),
                ),
              ),
          ],
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total,
          child: Column(
            children: [
              line(0, letters: true),
              line(0, head: true),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length - 1,
                  itemExtent: h,
                  itemBuilder: (context, i) => line(i + 1),
                ),
              ),
              if (rows.length >= 5000)
                Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: Text(
                    'Showing the first 5,000 rows; open it elsewhere for the rest.',
                    style: numStyle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
