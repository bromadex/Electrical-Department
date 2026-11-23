import 'package:electrical_department/screens/first_password_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invitation and reset links ask for a password', () {
    expect(
      isEmailLink(Uri.parse('https://x.app/#access_token=a&type=invite')),
      isTrue,
    );
    expect(isEmailLink(Uri.parse('https://x.app/?type=recovery')), isTrue);
    expect(isEmailLink(Uri.parse('https://x.app/#/jobs')), isFalse);
    expect(isEmailLink(Uri.parse('https://x.app/#a=1&type=invited')), isFalse);
  });
}
