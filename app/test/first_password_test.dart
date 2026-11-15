import 'package:electrical_department/screens/first_password_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User user(Map<String, dynamic> meta) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: meta,
  aud: 'authenticated',
  createdAt: '2026-11-15T00:00:00Z',
);

void main() {
  test(
    'a temporary password is flagged by the admin, cleared by the person',
    () {
      expect(mustChangePassword(user({'must_change_password': true})), isTrue);
      expect(
        mustChangePassword(user({'must_change_password': false})),
        isFalse,
      );
      expect(mustChangePassword(user({})), isFalse);
      expect(mustChangePassword(null), isFalse);
    },
  );

  test('password rules', () {
    String? p(String a, [String? b]) =>
        FirstPasswordScreenRules.problem(a, b ?? a, 'gerizulu@gmail.com');
    expect(p('short1'), 'Use at least 8 characters');
    expect(p('onlyletters'), 'Use letters and at least one number');
    expect(p('gerizulu2026'), 'Do not use your email name in the password');
    expect(
      p('Kamativi2026', 'Kamativi2025'),
      'The two passwords are different',
    );
    expect(p('Kamativi2026'), isNull);
  });
}
