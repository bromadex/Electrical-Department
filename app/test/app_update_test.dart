import 'package:electrical_department/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('compares versions by number, not as text', () {
    expect(isNewer('0.1.10', '0.1.9'), isTrue);
    expect(isNewer('v0.2.0', '0.1.9'), isTrue);
    expect(isNewer('0.1.9', '0.1.9'), isFalse);
    expect(isNewer('0.1.8', '0.1.9'), isFalse);
    expect(isNewer('1.0', '0.9.9'), isTrue);
    expect(isNewer('0.1.9', 'dev'), isFalse);
    expect(parseVersion('dev'), isNull);
  });

  test('reads latest.json and the GitHub API', () {
    final a = AppRelease.fromLatestJson({
      'version': '0.1.10',
      'apk': 'https://github.com/x/y/releases/download/v0.1.10/a.apk',
      'notes': '• Faster calls',
    })!;
    expect(a.version, '0.1.10');
    expect(a.notes, '• Faster calls');
    expect(
      AppRelease.fromLatestJson({'version': '0.1.10', 'apk': 'http://x'}),
      isNull,
    );

    final g = AppRelease.fromGitHub({
      'tag_name': 'v0.1.8',
      'body': 'v0.1.8',
      'assets': [
        {'browser_download_url': 'https://x/a.aab'},
        {'browser_download_url': 'https://x/a.apk'},
      ],
    })!;
    expect(g.version, '0.1.8');
    expect(g.apk, 'https://x/a.apk');
    expect(g.notes, isNull);
  });

  test('"Later" puts off that version for a day only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    expect(updateSnoozed(prefs, '0.1.10', now), isFalse);
    await snoozeUpdate(prefs, '0.1.10');
    expect(updateSnoozed(prefs, '0.1.10', now), isTrue);
    expect(updateSnoozed(prefs, '0.1.11', now), isFalse);
    expect(
      updateSnoozed(prefs, '0.1.10', now.add(const Duration(days: 2))),
      isFalse,
    );
  });
}
