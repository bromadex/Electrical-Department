import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'issue_forms_repository.dart';
import 'tools_repository.dart';

const _burgundy = PdfColor.fromInt(0xFF7A1F2B);
const _grey = PdfColor.fromInt(0xFF5F5A66);
const _line = PdfColor.fromInt(0xFFCCC7D0);

String _d(DateTime? t) => t == null
    ? ''
    : '${t.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][t.month - 1]} ${t.year}';

String _condition(String? v) => v == null ? '' : ToolCondition.parse(v).label;

/// The tool issue form as an A4 PDF, laid out like the company's paper
/// form: details, the tools with condition on issue and on return, the
/// declaration, and the issue and return signatures. [signatures] maps a
/// storage path to its PNG bytes.
Future<Uint8List> buildIssueFormPdf({
  required IssueForm form,
  required String siteName,
  required String? issuedByName,
  required String? receivedBackByName,
  required Map<String, Uint8List> signatures,
}) async {
  final f = form;
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/branding/logo.png')).buffer.asUint8List(),
  );
  // The app's font, so names with accents print.
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-SemiBold.ttf')),
  );
  const small = pw.TextStyle(fontSize: 8.5);
  final bold = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

  pw.Widget detail(String label, String? value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 95, child: pw.Text(label, style: bold)),
        pw.Expanded(child: pw.Text(value ?? '', style: small)),
      ],
    ),
  );

  pw.Widget heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 9, bottom: 4),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        color: _burgundy,
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  pw.Widget signer(String role, String? name, String? path, DateTime? date) {
    final png = path == null ? null : signatures[path];
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(role, style: bold),
          pw.SizedBox(height: 2),
          pw.Text('Name: ${name ?? ''}', style: small),
          pw.SizedBox(height: 2),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Signature: ', style: small),
              pw.Container(
                width: 90,
                height: 26,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _line)),
                ),
                child: png == null
                    ? null
                    : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text('Date: ${png == null ? '' : _d(date)}', style: small),
        ],
      ),
    );
  }

  final lead = f.teamLead;
  final company = f.company == null ? '' : ' (${f.company})';
  final returnedDate =
      f.returnedAt ??
      (f.lines.any((l) => l.back)
          ? f.lines.where((l) => l.back).first.returnedAt
          : null);

  final doc = pw.Document(title: '${f.code} Tool issue form');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 24),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Image(logo, height: 30),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Bravura Zimbabwe Ltd',
                  style: pw.TextStyle(
                    color: _burgundy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(f.code, style: const pw.TextStyle(color: _grey)),
              ],
            ),
          ],
        ),
      ),
      footer: (c) => pw.Center(
        child: pw.Text(
          'Bravura Zimbabwe Ltd | Tool Issue Form ${f.code} | '
          'Page ${c.pageNumber} of ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _grey),
        ),
      ),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            'TOOL ISSUE FORM',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  detail('Issued by:', 'Bravura Zimbabwe Ltd'),
                  detail(
                    'Issued to:',
                    [
                      f.recipientName,
                      if (f.recipientRole != null) '(${f.recipientRole})',
                    ].join(' '),
                  ),
                  detail('Company:', f.company),
                  detail('Project Team Lead:', lead),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                children: [
                  detail('Date of issue:', _d(f.issuedAt)),
                  detail('Expected return date:', _d(f.dueBack)),
                  detail(
                    'Site / Location:',
                    [siteName, ?f.location].join(' · '),
                  ),
                  if (f.jobCardNumber != null)
                    detail('Job card:', f.jobCardNumber),
                ],
              ),
            ),
          ],
        ),
        heading('Tools Issued'),
        pw.TableHelper.fromTextArray(
          headers: [
            'No.',
            'Description',
            'Serial No.',
            'Qty',
            'Condition on Issue',
            'Condition on Return',
          ],
          data: [
            for (final (i, l) in f.lines.indexed)
              [
                '${i + 1}',
                [l.name, if (l.code != null) '(${l.code})'].join(' '),
                l.serialNo ?? '',
                '${l.qty}',
                _condition(l.issueCondition),
                [
                  _condition(l.returnCondition),
                  ?l.returnNote,
                ].where((s) => s.isNotEmpty).join(': '),
              ],
            [
              '',
              'Total items',
              '',
              '${f.lines.fold<int>(0, (n, l) => n + l.qty)}',
              '',
              '',
            ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: _burgundy),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 2.5,
          ),
          headerPadding: const pw.EdgeInsets.all(4),
          cellAlignments: {0: pw.Alignment.center, 3: pw.Alignment.center},
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FixedColumnWidth(28),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.8),
          },
          border: pw.TableBorder.all(color: _line, width: 0.5),
        ),
        heading('Declaration'),
        pw.Text(
          'I, the undersigned, acknowledge receipt of the tools listed above '
          'from Bravura Zimbabwe Ltd in the condition stated. I accept '
          'responsibility for their safekeeping and proper use, and undertake '
          'to return all items in the same condition, fair wear and tear '
          'excepted. Any tool lost or damaged through negligence or misuse '
          'will be reported immediately and may be charged to the receiving '
          'company.',
          style: small,
        ),
        heading('Issue'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            signer(
              'Issued by (Bravura Zimbabwe)',
              issuedByName,
              f.issuerSignature,
              f.issuedAt,
            ),
            pw.SizedBox(width: 12),
            signer(
              'Received by (${f.recipientRole ?? 'Recipient'})',
              f.recipientName,
              f.recipientSignature,
              f.issuedAt,
            ),
            pw.SizedBox(width: 12),
            signer(
              'Project Team Lead$company',
              lead,
              f.leadSignature,
              f.issuedAt,
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            heading('Return'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                signer(
                  'Received back by (Bravura)',
                  receivedBackByName,
                  f.returnIssuerSignature,
                  returnedDate,
                ),
                pw.SizedBox(width: 12),
                signer(
                  'Returned by (${f.recipientRole ?? 'Recipient'})',
                  f.recipientName,
                  f.returnRecipientSignature,
                  returnedDate,
                ),
                pw.SizedBox(width: 12),
                signer(
                  'Project Team Lead$company',
                  lead,
                  f.returnLeadSignature,
                  returnedDate,
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Remarks: ${[?f.remarks, ?f.returnRemarks].join(' · ')}',
              style: small,
            ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
