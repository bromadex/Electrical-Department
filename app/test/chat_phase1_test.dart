import 'dart:typed_data';

import 'package:electrical_department/chat/chat_media.dart';
import 'package:electrical_department/chat/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

ChatMessage _msg(String id) => ChatMessage(
  id: id,
  conversationId: 'c',
  authorId: 'a',
  kind: 'text',
  createdAt: DateTime(2026, 11, 15),
  body: id,
);

void main() {
  group('ticks', () {
    test('waiting to send shows the clock', () {
      expect(
        tickState(pending: true, ticks: (recipients: 2, delivered: 2, read: 2)),
        TickState.pending,
      );
    });

    test('on the server but not on every phone is one tick', () {
      expect(tickState(pending: false), TickState.sent);
      expect(
        tickState(
          pending: false,
          ticks: (recipients: 3, delivered: 2, read: 1),
        ),
        TickState.sent,
      );
    });

    test('on every phone is two grey ticks, read by all is blue', () {
      expect(
        tickState(
          pending: false,
          ticks: (recipients: 3, delivered: 3, read: 2),
        ),
        TickState.delivered,
      );
      expect(
        tickState(
          pending: false,
          ticks: (recipients: 3, delivered: 3, read: 3),
        ),
        TickState.read,
      );
    });

    test('a chat with nobody else stays at one tick', () {
      expect(
        tickState(
          pending: false,
          ticks: (recipients: 0, delivered: 0, read: 0),
        ),
        TickState.sent,
      );
    });
  });

  test('delete for me hides only the chosen messages', () {
    final thread = ChatThread(
      messages: [_msg('1'), _msg('2'), _msg('3')],
      hidden: const {'2'},
    );
    expect([for (final m in thread.visible) m.id], ['1', '3']);
    expect(thread.messages, hasLength(3));
  });

  group('photo compression', () {
    test('a large photo is made smaller, longest side 1600', () async {
      final big = img.Image(width: 3200, height: 2400);
      img.fill(big, color: img.ColorRgb8(120, 30, 50));
      for (var x = 0; x < 3200; x += 7) {
        img.drawLine(
          big,
          x1: x,
          y1: 0,
          x2: 3200 - x,
          y2: 2399,
          color: img.ColorRgb8(x % 255, 200, 90),
        );
      }
      final original = Uint8List.fromList(img.encodePng(big));
      final out = await compressPhoto(original);
      expect(out.length, lessThan(original.length));
      final back = img.decodeImage(out)!;
      expect(back.width, sendMaxSide);
      expect(back.height, 1200);
    });

    test('a portrait photo keeps its shape', () async {
      final tall = img.Image(width: 1000, height: 4000);
      img.fill(tall, color: img.ColorRgb8(10, 20, 200));
      final out = await compressPhoto(Uint8List.fromList(img.encodePng(tall)));
      final back = img.decodeImage(out)!;
      expect(back.height, sendMaxSide);
      expect(back.width, 400);
    });

    test('something that is not a picture is sent as it is', () async {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(await compressPhoto(junk), junk);
    });
  });
}
