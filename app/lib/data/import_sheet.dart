import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'app_error.dart';
import 'xlsx.dart';

/// One column an import understands, and the headers that mean it.
typedef ImportField = ({String key, String label, List<String> aliases});

/// Matches a spreadsheet's header row to [fields] (case and spaces
/// ignored; a header containing an alias counts). Returns field key →
/// column index for the fields found.
Map<String, int> matchColumns(List<String> header, List<ImportField> fields) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final out = <String, int>{};
  for (final f in fields) {
    final names = [f.key, f.label, ...f.aliases].map(norm).toList();
    for (var i = 0; i < header.length; i++) {
      if (out.containsValue(i)) continue;
      final h = norm(header[i]);
      if (h.isEmpty) continue;
      if (names.any((n) => h == n) ||
          names.any((n) => n.length > 3 && h.contains(n))) {
        out[f.key] = i;
        break;
      }
    }
  }
  return out;
}

/// The rows under the header as maps of field key → text.
List<Map<String, String>> rowsAsMaps(
  List<List<String>> table,
  Map<String, int> columns,
) => [
  for (final row in table.skip(1))
    {
      for (final c in columns.entries)
        if (c.value < row.length && row[c.value].trim().isNotEmpty)
          c.key: row[c.value].trim(),
    },
];

/// A sheet that reads an .xlsx or CSV file, shows which columns it
/// understood and the first rows, then hands the rows to [onImport], which
/// returns a line to show ("12 added, 3 updated").
class ImportSheet extends StatefulWidget {
  const ImportSheet({
    super.key,
    required this.title,
    required this.help,
    required this.fields,
    required this.required,
    required this.onImport,
  });

  final String title;
  final String help;
  final List<ImportField> fields;

  /// Field keys a row must have.
  final List<String> required;
  final Future<String> Function(List<Map<String, String>> rows) onImport;

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  String? _file;
  Map<String, int> _columns = const {};
  List<Map<String, String>> _rows = const [];
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt', 'tsv'],
    );
    if (f == null) return;
    try {
      final table = readTable(f.name, await f.xFile.readAsBytes());
      if (table.length < 2) {
        throw const FormatException('The file needs a header row and data');
      }
      final columns = matchColumns(table.first, widget.fields);
      final missing = [
        for (final r in widget.required)
          if (!columns.containsKey(r))
            widget.fields.firstWhere((x) => x.key == r).label,
      ];
      if (missing.isNotEmpty) {
        throw FormatException('No column for ${missing.join(', ')}');
      }
      final rows = [
        for (final r in rowsAsMaps(table, columns))
          if (widget.required.every(r.containsKey)) r,
      ];
      setState(() {
        _file = f.name;
        _columns = columns;
        _rows = rows;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final done = await widget.onImport(_rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = AppError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shownFields = [
      for (final f in widget.fields)
        if (_columns.containsKey(f.key)) f,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.headlineSmall),
          Text(widget.help, style: theme.textTheme.bodySmall),
          const SizedBox(height: Space.sm),
          Text(
            'Columns: ${widget.fields.map((f) => widget.required.contains(f.key) ? '${f.label} (needed)' : f.label).join(', ')}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(CupertinoIcons.doc),
            label: Text(_file ?? 'Pick the Excel or CSV file'),
          ),
          if (_file != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              '${_rows.length} ${_rows.length == 1 ? 'row' : 'rows'} to import · '
              'columns found: ${shownFields.map((f) => f.label).join(', ')}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: Space.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 32,
                columns: [
                  for (final f in shownFields) DataColumn(label: Text(f.label)),
                ],
                rows: [
                  for (final r in _rows.take(5))
                    DataRow(
                      cells: [
                        for (final f in shownFields)
                          DataCell(Text(r[f.key] ?? '')),
                      ],
                    ),
                ],
              ),
            ),
            if (_rows.length > 5)
              Text(
                'and ${_rows.length - 5} more',
                style: theme.textTheme.labelSmall,
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _busy || _rows.isEmpty ? null : _import,
            child: Text(
              _rows.isEmpty ? 'Import' : 'Import ${_rows.length} rows',
            ),
          ),
        ],
      ),
    );
  }
}

/// A number as typed in a spreadsheet ("1,5", " 300 ") as text Postgres
/// reads, or null.
String? importNumber(String? v) {
  if (v == null) return null;
  final t = v.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  return double.tryParse(t) == null ? null : t;
}

/// A date from a spreadsheet as yyyy-mm-dd: an Excel date number (days since
/// 30 Dec 1899), 2027-01-31, or 31/01/2027 (day first, as written here).
String? importDate(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final t = v.trim();
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final serial = double.tryParse(t);
  if (serial != null && serial > 20000 && serial < 80000) {
    return iso(DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor())));
  }
  final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (ymd != null) {
    return iso(
      DateTime(int.parse(ymd[1]!), int.parse(ymd[2]!), int.parse(ymd[3]!)),
    );
  }
  final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
  if (dmy != null) {
    return iso(
      DateTime(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!)),
    );
  }
  return null;
}
