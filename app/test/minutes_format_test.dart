import 'dart:io';

import 'package:electrical_department/meetings/meeting_pdf.dart';
import 'package:electrical_department/meetings/meetings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Meeting sample() => Meeting.fromJson({
  'id': 'm1',
  'site_id': 's1',
  'conversation_id': 'c1',
  'code': 'KAM-M-0007',
  'title': 'Electrical Works & Infrastructure Update (Kamativi Project)',
  'agenda': null,
  'starts_at': '2026-10-22T08:00:00Z',
  'duration_min': 60,
  'chair_id': 'u3',
  'status': 'scheduled',
  'minutes_status': 'approved',
  'minutes': {
    'meeting_type': 'Technical Project Review Meeting',
    'venue': 'Online Meeting',
    'minutes_by': 'Gerald Zulu',
    'attendance': [
      {
        'name': 'Crispen Katsande',
        'position': 'Head of Department',
        'organisation': 'Bravura',
      },
      {
        'name': 'Lewis Karambwe',
        'position': 'Electrical Engineer',
        'organisation': 'Bravura',
      },
      {
        'name': 'Clement Mpala',
        'position': 'Junior Electrical Engineer',
        'organisation': 'Bravura',
      },
    ],
    'updates':
        'C.M. reported that Kamativi had received three (3) 50,000-litre '
        'tanks by the date of the meeting.',
    'summary':
        'The meeting reviewed progress on the Kamativi electrical and '
        'infrastructure works.',
    'decisions': <String>[],
    'actions': [
      {
        'text': 'Project start date remains scheduled for 01 December 2026.',
        'owner_name': 'Lewis Karambwe',
        'due': '2026-12-01',
        'status': '',
      },
      {
        'text': 'Genset transportation is awaiting the generator house.',
        'owner_name': 'Lewis Karambwe / Clement Mpala',
        'due': null,
        'status': 'Pending civil works',
      },
      {
        'text': 'Transportation of diesel tanks has started.',
        'owner_name': 'Crispen Katsande / Procurement',
        'due': null,
        'status': 'Ongoing',
      },
    ],
    'status_summary': [
      {'area': 'Storage tanks', 'status': '3 × 50,000-litre tanks received.'},
      {'area': 'Lighting', 'status': '13 light masts completed.'},
    ],
    'next_agenda': ['Review progress on civil works.'],
    'reviewed_by': 'T. Chikuku',
    'approved_by': 'C. Katsande',
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('names and initials as the department writes them', () {
    expect(minutesInitials('Clement Mpala'), 'C.M');
    expect(minutesInitials('C. Mpala'), 'C.M');
    expect(minutesInitials('Procurement'), 'P');
    expect(minutesShortName('Gerald Zulu'), 'G. Zulu');
    expect(minutesShortName('Crispen Tafara Katsande'), 'C. Tafara Katsande');
  });

  test('responsible people show as initials; others as written', () {
    final m = sample().minutes;
    expect(
      responsibleText('Lewis Karambwe / Clement Mpala', m.attendance),
      'L.K / C.M',
    );
    expect(
      responsibleText('Crispen Katsande / Procurement', m.attendance),
      'C.K / Procurement',
    );
    expect(responsibleText(null, m.attendance), '');
  });

  test('due date and status share a column', () {
    final a = sample().minutes.actions;
    expect(dueOrStatus(a[0]), '01/12/2026');
    expect(dueOrStatus(a[1]), 'Pending civil works');
  });

  test('the new fields survive a save and reload', () {
    final m = sample().minutes;
    final back = Minutes.fromJson(m.toJson());
    expect(back.meetingType, 'Technical Project Review Meeting');
    expect(back.attendance.map((a) => a.initials), ['C.K', 'L.K', 'C.M']);
    expect(back.actions[1].status, 'Pending civil works');
    expect(back.statusSummary.first.area, 'Storage tanks');
    expect(back.nextAgenda, ['Review progress on civil works.']);
    expect(back.approvedBy, 'C. Katsande');
  });

  test('old minutes (summary, decisions, actions only) still load', () {
    final old = Minutes.fromJson({
      'summary': 'Short meeting.',
      'decisions': ['Buy cable'],
      'actions': [
        {'text': 'Order it', 'owner_name': 'Clement Mpala', 'due': null},
      ],
    });
    expect(old.attendance, isEmpty);
    expect(old.actions.single.status, '');
  });

  test('the PDF builds in the department format', () async {
    final bytes = await buildMinutesPdf(
      meeting: sample(),
      chairName: 'Tafara Chikuku',
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final out = Platform.environment['MINUTES_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
