import 'package:electrical_department/chat/call_controller.dart';
import 'package:electrical_department/chat/calls_screen.dart';
import 'package:electrical_department/chat/chat_fab.dart';
import 'package:electrical_department/chat/chat_list_screen.dart';
import 'package:electrical_department/chat/chat_repository.dart';
import 'package:electrical_department/chat/chat_video.dart';
import 'package:electrical_department/chat/conversation_screen.dart';
import 'package:electrical_department/chat/location_poll.dart';
import 'package:electrical_department/data/avatars.dart';
import 'package:electrical_department/meetings/meetings_list_screen.dart';
import 'package:electrical_department/theme/app_theme.dart';
import 'package:electrical_department/ui/bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _chat([Map<String, dynamic> extra = const {}]) => {
  'id': 'c1',
  'kind': 'group',
  'title': 'Kamativi',
  'unread': 2,
  ...extra,
};

void main() {
  group('chat list data (migrations 0046, 0049)', () {
    test('mute, archive, favourites, mentions and the last tick', () {
      final c = Conversation.fromJson(
        _chat({
          'muted_until': DateTime.now()
              .add(const Duration(hours: 8))
              .toUtc()
              .toIso8601String(),
          'archived': true,
          'favourite': true,
          'mentions': 1,
          'last_author_id': 'me',
          'last_kind': 'photo',
          'last_tick': 'read',
          'description': 'Shift team',
        }),
      );
      expect(c.muted, isTrue);
      expect(c.archived, isTrue);
      expect(c.favourite, isTrue);
      expect(c.mentions, 1);
      expect(c.lastKind, 'photo');
      expect(c.lastTick, 'read');
      expect(c.description, 'Shift team');
    });

    test('muted for always (infinity) still counts as muted', () {
      final c = Conversation.fromJson(_chat({'muted_until': 'infinity'}));
      expect(c.muted, isTrue);
    });

    test('a chat from before 0049 still reads (defaults)', () {
      final c = Conversation.fromJson(_chat());
      expect(c.muted, isFalse);
      expect(c.favourite, isFalse);
      expect(c.mentions, 0);
      expect(c.lastTick, isNull);
    });
  });

  group('editing (migration 0046)', () {
    ChatMessage msg({
      String kind = 'text',
      String? author = 'me',
      int ago = 1,
    }) => ChatMessage(
      id: 'm',
      conversationId: 'c',
      authorId: author,
      kind: kind,
      createdAt: DateTime.now().subtract(Duration(minutes: ago)),
      body: 'x',
    );

    test('your own text within 15 minutes can be edited', () {
      expect(msg().canEdit('me'), isTrue);
    });
    test('not after 15 minutes, not others\', not photos', () {
      expect(msg(ago: 16).canEdit('me'), isFalse);
      expect(msg(author: 'you').canEdit('me'), isFalse);
      expect(msg(kind: 'photo').canEdit('me'), isFalse);
    });
    test('edited_at is read', () {
      final m = ChatMessage.fromJson({
        'id': 'm',
        'conversation_id': 'c',
        'kind': 'text',
        'created_at': '2026-11-16T10:00:00Z',
        'edited_at': '2026-11-16T10:05:00Z',
      });
      expect(m.editedAt, isNotNull);
    });
  });

  group('times and lengths', () {
    test('call length on the call screen', () {
      final now = DateTime(2026, 11, 16, 12);
      expect(
        formatCallLength(now.subtract(const Duration(seconds: 187)), now: now),
        '3:07',
      );
      expect(
        formatCallLength(
          now.subtract(const Duration(hours: 1, minutes: 2, seconds: 7)),
          now: now,
        ),
        '1:02:07',
      );
    });

    test('call length in the calls list', () {
      expect(callLengthLabel(0), '');
      expect(callLengthLabel(45), '45 s');
      expect(callLengthLabel(240), '4 min');
      expect(callLengthLabel(3900), '1 h 5 min');
    });

    test('video length', () {
      expect(videoLength(null), '');
      expect(videoLength(65000), '1:05');
    });

    test('a call log row', () {
      final e = CallLogEntry.fromRow({
        'call_id': 'k',
        'conversation_id': 'c',
        'title': 'Ben',
        'is_direct': true,
        'video': true,
        'direction': 'missed',
        'started_at': '2026-11-16T10:00:00Z',
        'seconds': 0,
        'live': false,
      });
      expect(e.missed, isTrue);
      expect(e.video, isTrue);
    });
  });

  group('talking time (Phase 4)', () {
    test('counts words per person, longest first', () {
      final t = talkingTime([
        (userId: 'a', body: 'one two three four five'),
        (userId: 'b', body: 'one two three four five six seven eight nine ten'),
        (userId: 'a', body: 'six seven'),
      ]);
      expect(t.first.userId, 'b');
      expect(t.first.time, const Duration(seconds: 4));
      expect(t.last.time, const Duration(milliseconds: 2800));
    });
    test('labels', () {
      expect(talkingLabel(const Duration(seconds: 45)), '45 s');
      expect(
        talkingLabel(const Duration(minutes: 4, seconds: 10)),
        '4 min 10 s',
      );
    });
  });

  group('chat looks', () {
    test('search marks every match, any case', () {
      final span = highlightMatches(
        'Isolator 3 and isolator 4',
        'ISOLATOR',
        null,
      );
      final marked = [
        for (final c in span.children ?? const <InlineSpan>[])
          if (c is TextSpan && c.style?.backgroundColor != null) c.text,
      ];
      expect(marked, ['Isolator', 'isolator']);
      expect(highlightMatches('abc', '', null).text, 'abc');
    });

    test('each person keeps one name colour', () {
      expect(senderColor('user-1', false), senderColor('user-1', false));
      expect(senderColor('user-1', true), isNot(senderColor('user-1', false)));
    });

    test('the chat button hides in chat, calls and sign-in', () {
      for (final p in [
        '/chat',
        '/chat/abc',
        '/calls',
        '/starred',
        '/guest/x',
        '/login',
        '/first-password',
      ]) {
        expect(ChatFabLayer.hiddenOn(p), isTrue, reason: p);
      }
      expect(ChatFabLayer.hiddenOn('/home'), isFalse);
      expect(ChatFabLayer.isTab('/jobs'), isTrue);
      expect(ChatFabLayer.isTab('/jobs/EL-1'), isFalse);
    });

    test('initials', () {
      expect(AppAvatar.initials('Tafara Chikuku'), 'TC');
      expect(AppAvatar.initials('  '), '?');
    });

    testWidgets('in chat, avatars are pale WhatsApp colours, not maroon', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [avatarUrlsProvider.overrideWith((ref) async => const {})],
          child: MaterialApp(
            theme: AppTheme.chat(Brightness.light),
            home: const Scaffold(body: AppAvatar(name: 'Nyasha Ncube')),
          ),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container).first);
      final d = box.decoration as BoxDecoration;
      expect(d.gradient, isNull);
      expect(d.color, isNotNull);
      expect(d.color!.computeLuminance(), greaterThan(0.6));
      expect(find.text('NN'), findsOneWidget);
    });

    testWidgets('outside chat too, avatars are the soft colours', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [avatarUrlsProvider.overrideWith((ref) async => const {})],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: AppAvatar(name: 'Nyasha Ncube')),
          ),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container).first);
      expect((box.decoration as BoxDecoration).gradient, isNull);
    });

    testWidgets('a group in chat is a pale green circle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.chat(Brightness.light),
          home: Scaffold(
            body: ChatGroupAvatar(chat: Conversation.fromJson(_chat())),
          ),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container).first);
      expect((box.decoration as BoxDecoration).gradient, isNull);
    });

    test('the chat theme follows light and dark', () {
      expect(AppTheme.chat(Brightness.dark).brightness, Brightness.dark);
      expect(
        AppTheme.chat(Brightness.light).scaffoldBackgroundColor,
        Colors.white,
      );
      expect(
        AppTheme.chat(Brightness.dark).scaffoldBackgroundColor,
        Colors.black,
      );
    });
  });

  group('location and polls', () {
    test('a shared location reads back as the same point', () {
      final text = locationMessage(-18.123456, 26.987654);
      expect(text.startsWith('📍 Location'), isTrue);
      expect(locationOf(text), (-18.123456, 26.987654));
    });
    test('ordinary text with a maps link is not a location card', () {
      expect(locationOf('see https://maps.google.com/maps?q=1,2'), isNull);
      expect(locationOf(null), isNull);
    });
    test('a poll counts each voter once', () {
      const p = Poll(
        id: 'p',
        question: 'Which days?',
        options: ['Mon', 'Tue'],
        multiple: true,
        votes: {
          0: ['a', 'b'],
          1: ['a'],
        },
      );
      expect(p.voters, 2);
    });
  });
}
