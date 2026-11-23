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
  test('a used or expired link says so', () {
    expect(
      emailLinkError(
        Uri.parse(
          'https://x.app/#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid',
        ),
      ),
      contains('expired'),
    );
    expect(emailLinkError(Uri.parse('https://x.app/#/login')), isNull);
  });
}
