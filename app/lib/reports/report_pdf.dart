import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'reports_repository.dart';

const _burgundy = PdfColor.fromInt(0xFF7A1F2B);
const _grey = PdfColor.fromInt(0xFF5F5A66);

/// The day's report as an A4 PDF: summary, jobs, rounds, everyone's
/// updates with their photos, and the approval.
Future<Uint8List> buildReportPdf({
  required ReportDay day,
  required String siteName,
  required Map<String, String> people,
  required Map<String, String> photoUrls,
}) async {
  final r = day.report;
  final images = <String, pw.ImageProvider>{};
  for (final u in day.updates) {
    for (final p in u.photoPaths.take(4)) {
      final url = photoUrls[p];
      if (url == null) continue;
      try {
        images[p] = await networkImage(url);
      } catch (_) {}
    }
  }
  final date =
      '${r.date.day.toString().padLeft(2, '0')}/${r.date.month.toString().padLeft(2, '0')}/${r.date.year}';

  pw.Widget heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
    child: pw.Text(
      t.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 9,
        letterSpacing: 1.2,
        color: _burgundy,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
  pw.Widget line(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(t, style: const pw.TextStyle(fontSize: 10)),
  );
  pw.Widget stat(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ],
      ),
    ),
  );

  final opened = r.list('jobs_opened');
  final closed = r.list('jobs_closed');
  final done = r.list('checklists_done');
  final missed = r.names('checklists_missed');

  final doc = pw.Document(title: '${r.code} $siteName $date');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Bravura Electrical · Daily report',
            style: pw.TextStyle(
              color: _burgundy,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            '${r.code} · $siteName · $date',
            style: const pw.TextStyle(color: _grey),
          ),
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
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            stat('Jobs opened', '${opened.length}'),
            stat('Jobs closed', '${closed.length}'),
            stat('Still open', '${r.count('jobs_open_now')}'),
            stat('Rounds done', '${done.length}'),
            stat('Rounds missed', '${missed.length}'),
            stat('Tools out', '${r.count('tools_out')}'),
          ],
        ),
        heading('Jobs closed'),
        if (closed.isEmpty) line('None.'),
        for (final j in closed)
          line(
            '${j['code']}  ${j['title']}'
            '${j['by'] == null ? '' : ' · by ${j['by']}'}'
            '${j['note'] == null ? '' : ' - ${j['note']}'}',
          ),
        heading('Jobs opened'),
        if (opened.isEmpty) line('None.'),
        for (final j in opened)
          line(
            '${j['code']}  ${j['title']} · ${j['priority']} · ${'${j['status']}'.replaceAll('_', ' ')}',
          ),
        heading('Checklist rounds'),
        for (final c in done)
          line(
            'Done: ${c['name']}'
            '${c['by'] == null ? '' : ' · ${c['by']}'}'
            '${(c['failed'] as num? ?? 0) > 0 ? ' · ${c['failed']} failed' : ''}',
          ),
        for (final m in missed) line('Missed: $m'),
        if (done.isEmpty && missed.isEmpty) line('No rounds were due.'),
        heading('Tools'),
        line(
          '${r.count('tools_issued')} issued · ${r.count('tools_returned')} returned · '
          '${r.count('tools_out')} out now',
        ),
        heading("Today's updates"),
        if (day.updates.isEmpty) line('No updates.'),
        for (final u in day.updates) ...[
          pw.Text(
            people[u.userId] ?? 'Someone',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          line(u.body),
          if (u.photoPaths.any(images.containsKey))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in u.photoPaths)
                    if (images[p] != null)
                      pw.Image(
                        images[p]!,
                        width: 120,
                        height: 90,
                        fit: pw.BoxFit.cover,
                      ),
                ],
              ),
            ),
        ],
        heading('Approval'),
        line(
          r.approved
              ? 'Approved by ${people[r.approvedBy] ?? 'a supervisor'}'
                    '${r.comment == null ? '' : ' - ${r.comment}'}'
              : 'Not approved yet.',
        ),
      ],
    ),
  );
  return doc.save();
}
