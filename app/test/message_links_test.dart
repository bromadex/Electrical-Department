import 'package:electrical_department/chat/chat_repository.dart';
import 'package:electrical_department/chat/record_links.dart';
import 'package:electrical_department/services/push_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _doc = 'doc:11111111-1111-1111-1111-111111111111';
const _job = 'jobcard:22222222-2222-2222-2222-222222222222';

void main() {
  test('message tags are read from the row, bad entries skipped', () {
    final links = parseMessageLinks([
      {'label': '#LOTO procedure', 'link': _doc},
      {'label': 'no link'},
      'junk',
      {'label': '#EL-JC-2026-0011', 'link': _job},
    ]);
    expect(links, [
      (label: '#LOTO procedure', link: _doc),
      (label: '#EL-JC-2026-0011', link: _job),
    ]);
    expect(parseMessageLinks(null), isEmpty);
    final m = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'author_id': 'u1',
      'kind': 'text',
      'body': 'Use #LOTO procedure',
      'created_at': '2026-11-17T08:00:00Z',
      'links': [
        {'label': '#LOTO procedure', 'link': _doc},
      ],
    });
    expect(m.links.single.link, _doc);
  });

  test('tagged labels become tappable spans; the rest stays plain', () {
    final opened = <String>[];
    final span = linkedText(
      'Read #LOTO procedure before #EL-JC-2026-0011 today',
      const [
        (label: '#LOTO procedure', link: _doc),
        (label: '#EL-JC-2026-0011', link: _job),
      ],
      const TextStyle(fontWeight: FontWeight.w600),
      (part) => TextSpan(text: part),
      opened.add,
    );
    final parts = span.children!.cast<TextSpan>();
    expect(parts.map((p) => p.text).toList(), [
      'Read ',
      '#LOTO procedure',
      ' before ',
      '#EL-JC-2026-0011',
      ' today',
    ]);
    (parts[1].recognizer! as TapGestureRecognizer).onTap!();
    (parts[3].recognizer! as TapGestureRecognizer).onTap!();
    expect(opened, [_doc, _job]);
    expect(parts[0].recognizer, isNull);
  });

  test('the longest label wins when one starts another', () {
    final span = linkedText(
      'See #Pump 2 manual',
      const [
        (label: '#Pump 2', link: _job),
        (label: '#Pump 2 manual', link: _doc),
      ],
      null,
      (part) => TextSpan(text: part),
      (_) {},
    );
    final parts = span.children!.cast<TextSpan>();
    expect(parts.map((p) => p.text), ['See ', '#Pump 2 manual']);
  });

  test('tags open the right screens and show their kind', () {
    expect(notificationPath(_doc), '/documents/${_doc.substring(4)}');
    expect(notificationPath(_job), '/jobs/${_job.substring(8)}');
    expect(recordKind(_doc), 'File');
    expect(recordKind(_job), 'Job card');
    expect(recordKind('po:x'), 'Purchase');
  });
}
