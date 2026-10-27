import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'meetings_repository.dart';

const _burgundy = PdfColor.fromInt(0xFF7A1F2B);
const _grey = PdfColor.fromInt(0xFF5F5A66);

String _d(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A meeting's minutes as an A4 PDF: details, who joined, summary,
/// decisions and the actions table.
Future<Uint8List> buildMinutesPdf({
  required Meeting meeting,
  required String chatName,
  required String chairName,
  required List<String> attendance,
}) async {
  final m = meeting;
  final min = m.minutes;
  pw.Widget heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        color: _burgundy,
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  final doc = pw.Document(title: '${m.code} ${m.title}');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Bravura Electrical · Minutes',
            style: pw.TextStyle(
              color: _burgundy,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(m.code, style: const pw.TextStyle(color: _grey)),
        ],
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${c.pageNumber} of ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _grey),
        ),
      ),
      build: (_) => [
        pw.SizedBox(height: 8),
        pw.Text(
          m.title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${_d(m.startsAt)} · ${_hm(m.startsAt)}–${_hm(m.endsAt)} · $chatName · '
          'Chair: $chairName',
          style: const pw.TextStyle(color: _grey),
        ),
        if (attendance.isNotEmpty) ...[
          heading('Present'),
          pw.Text(attendance.join(', ')),
        ],
        if ((m.agenda ?? '').isNotEmpty) ...[
          heading('Agenda'),
          pw.Text(m.agenda!),
        ],
        heading('Summary'),
        pw.Text(min.summary),
        if (min.decisions.isNotEmpty) ...[
          heading('Decisions'),
          for (final d in min.decisions) pw.Bullet(text: d),
        ],
        if (min.actions.isNotEmpty) ...[
          heading('Actions'),
          pw.TableHelper.fromTextArray(
            headers: ['Action', 'Who', 'By'],
            data: [
              for (final a in min.actions)
                [a.text, a.ownerName ?? '—', a.due == null ? '—' : _d(a.due!)],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: _burgundy),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.2),
            },
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Text(
          m.approved ? 'Approved by the chair.' : 'Draft: not yet approved.',
          style: const pw.TextStyle(color: _grey, fontSize: 9),
        ),
      ],
    ),
  );
  return doc.save();
}
