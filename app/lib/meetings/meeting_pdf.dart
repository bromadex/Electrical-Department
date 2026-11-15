import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'meetings_repository.dart';

/// The department's minutes colours: navy table headers, blue headings.
const _navy = PdfColor.fromInt(0xFF1F3864);
const _blue = PdfColor.fromInt(0xFF2E5597);
const _grey = PdfColor.fromInt(0xFF7F7F7F);
const _line = PdfColor.fromInt(0xFF9E9E9E);

String _d(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "22 October 2026".
String minutesLongDate(DateTime t) =>
    '${t.day} ${_months[t.month - 1]} ${t.year}';

/// "L.K / T.C": each responsible person as their initials when they are on
/// the attendance list, otherwise as written.
String responsibleText(String? owner, List<Attendee> attendance) {
  if (owner == null || owner.trim().isEmpty) return '';
  return owner
      .split('/')
      .map((part) {
        final p = part.trim();
        final hit = attendance.where(
          (a) => a.name.toLowerCase() == p.toLowerCase(),
        );
        return hit.isEmpty ? p : hit.first.initials;
      })
      .join(' / ');
}

/// "26/10/2026" and/or the status ("Ongoing").
String dueOrStatus(MeetingAction a) => [
  if (a.due != null) _d(a.due!),
  if (a.status.trim().isNotEmpty) a.status.trim(),
].join('\n');

/// A meeting's minutes as an A4 PDF in the department's format: logo and
/// title, meeting details, attendance, updates, then lettered sections
/// (executive summary, decisions, the numbered action table, project
/// status, next meeting's agenda) and sign-off.
Future<Uint8List> buildMinutesPdf({
  required Meeting meeting,
  required String chairName,

  /// Who spoke how long (from live captions), with names; empty to leave
  /// the table out.
  List<({String name, String time})> talking = const [],
}) async {
  final m = meeting;
  final min = m.minutes;
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/branding/logo.png')).buffer.asUint8List(),
  );
  final theme =
      pw.ThemeData.withFont(
        base: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
        ),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf')),
      ).copyWith(
        defaultTextStyle: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.5),
      );
  final title = m.title.toUpperCase();

  var letter = 0;
  pw.Widget section(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      '${String.fromCharCode(65 + letter++)}. $t',
      style: pw.TextStyle(
        color: _blue,
        fontSize: 11.5,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
  pw.Widget plainHeading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        color: _blue,
        fontSize: 11.5,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
  pw.Widget detail(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: value),
        ],
      ),
    ),
  );
  pw.Widget table({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> widths,
    Set<int> centred = const {},
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: pw.TableBorder.all(color: _line, width: 0.5),
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
      fontSize: 9,
    ),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    headerAlignment: pw.Alignment.center,
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignments: {for (final i in centred) i: pw.Alignment.center},
    cellAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    columnWidths: widths,
  );

  final doc = pw.Document(title: '${m.code} ${m.title}', theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      footer: (c) => pw.Container(
        width: double.infinity,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              title,
              style: const pw.TextStyle(fontSize: 7.5, color: _grey),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${m.code} · Page ${c.pageNumber} of ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _grey),
            ),
          ],
        ),
      ),
      build: (_) => [
        pw.Center(child: pw.Image(logo, height: 56)),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'BRAVURA ELECTRICAL DEPARTMENT',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'MEETING MINUTES – $title',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (!m.approved)
          pw.Center(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'DRAFT – NOT YET APPROVED',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.red800,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        pw.SizedBox(height: 14),
        detail('Meeting Date', minutesLongDate(m.startsAt)),
        if (min.meetingType.trim().isNotEmpty)
          detail('Meeting Type', min.meetingType.trim()),
        if (min.venue.trim().isNotEmpty) detail('Venue', min.venue.trim()),
        detail('Chairperson', minutesShortName(chairName)),
        if (min.minutesBy.trim().isNotEmpty)
          detail('Minutes Taken By', min.minutesBy.trim()),
        if (min.attendance.isNotEmpty) ...[
          plainHeading('Attendance'),
          table(
            headers: ['ID', 'Name', 'Position', 'Organisation'],
            rows: [
              for (final (i, a) in min.attendance.indexed)
                [
                  '${i + 1}',
                  '${a.shortName} (${a.initials})',
                  a.position,
                  a.organisation,
                ],
            ],
            widths: const {
              0: pw.FixedColumnWidth(28),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(2),
            },
            centred: const {0},
          ),
        ],
        if (talking.isNotEmpty) ...[
          plainHeading('Talking Time'),
          table(
            headers: ['Name', 'Time'],
            rows: [
              for (final t in talking) [t.name, t.time],
            ],
            widths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(2)},
          ),
        ],
        if ((m.agenda ?? '').trim().isNotEmpty) ...[
          plainHeading('Agenda'),
          pw.Text(m.agenda!.trim()),
        ],
        if (min.updates.trim().isNotEmpty) ...[
          plainHeading('UPDATES'),
          pw.Text(min.updates.trim(), textAlign: pw.TextAlign.justify),
        ],
        section('Executive Summary & Overview'),
        pw.Text(min.summary, textAlign: pw.TextAlign.justify),
        if (min.decisions.isNotEmpty) ...[
          section('Decisions'),
          for (final d in min.decisions)
            pw.Bullet(text: d, style: const pw.TextStyle(fontSize: 9.5)),
        ],
        if (min.actions.isNotEmpty) ...[
          section('Actions & Discussion'),
          table(
            headers: [
              'No.',
              'Action / Discussion',
              'Responsible',
              'Due Date / Status',
            ],
            rows: [
              for (final (i, a) in min.actions.indexed)
                [
                  '${i + 1}',
                  a.text,
                  responsibleText(a.ownerName, min.attendance),
                  dueOrStatus(a),
                ],
            ],
            widths: const {
              0: pw.FixedColumnWidth(28),
              1: pw.FlexColumnWidth(6),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1.8),
            },
            centred: const {0},
          ),
        ],
        if (min.statusSummary.isNotEmpty) ...[
          section('Project Status Summary'),
          table(
            headers: ['Area', 'Current Status'],
            rows: [
              for (final s in min.statusSummary) [s.area, s.status],
            ],
            widths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(6)},
            centred: const {0},
          ),
        ],
        if (min.nextAgenda.isNotEmpty) ...[
          section('Next Meeting – Proposed Agenda'),
          for (final a in min.nextAgenda)
            pw.Bullet(text: a, style: const pw.TextStyle(fontSize: 9.5)),
        ],
        pw.SizedBox(height: 24),
        if (min.minutesBy.trim().isNotEmpty)
          detail('Minutes Prepared By', min.minutesBy.trim()),
        if (min.reviewedBy.trim().isNotEmpty)
          detail('Document Reviewed By', min.reviewedBy.trim()),
        if (min.approvedBy.trim().isNotEmpty)
          detail('Minutes Approved By', min.approvedBy.trim())
        else if (m.approved)
          detail('Minutes Approved By', minutesShortName(chairName)),
      ],
    ),
  );
  return doc.save();
}
