import 'package:electrical_department/config/firebase_config.dart';
import 'package:electrical_department/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push stays off until the Firebase identifiers are filled in', () {
    if (FirebaseConfig.projectId.isEmpty) {
      expect(FirebaseConfig.options, isNull);
    }
  });

  test('the web push key is a public P-256 key', () {
    // 65 bytes, base64url without padding, uncompressed point (starts 0x04).
    expect(FirebaseConfig.vapidKey, hasLength(87));
    expect(FirebaseConfig.vapidKey, startsWith('B'));
    expect(
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(FirebaseConfig.vapidKey),
      isTrue,
    );
  });

  test('without Firebase the app reports push as unavailable', () {
    expect(PushSupport.ready, isFalse);
  });

  test('notification links open the right screen', () {
    expect(notificationPath('job:abc'), '/jobs/abc');
    expect(notificationPath('chat:xyz'), '/chat/xyz');
    expect(notificationPath('tool:t1'), '/tools/t1');
    expect(notificationPath('jobcard:abc'), isNull);
    expect(notificationPath('job:'), isNull);
    expect(notificationPath(null), isNull);
  });
}
