import 'package:electrical_department/theme/app_theme.dart';
import 'package:electrical_department/ui/bits.dart';
import 'package:electrical_department/ui/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    // Reduced motion keeps tests free of never-ending animations.
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('initials come from up to two name parts', () {
    expect(AppAvatar.initials('Test Technician'), 'TT');
    expect(AppAvatar.initials('clement.mpala@bravura.co.zw'), 'CM');
    expect(AppAvatar.initials('  '), '?');
  });

  testWidgets('empty state shows title, message and badge', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyState(
          icon: Icons.dashboard_rounded,
          title: 'Jobs board',
          message: 'Coming soon',
          badge: 'Phase 1',
        ),
      ),
    );
    expect(find.text('Jobs board'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Phase 1'), findsOneWidget);
  });

  testWidgets('pressable calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(Pressable(onTap: () => taps++, child: const Text('Tap me'))),
    );
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('animated count settles on the value', (tester) async {
    await tester.pumpWidget(_wrap(const AnimatedCount(value: 42)));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('both themes build', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                Pill(label: 'Open'),
                RecordCode('J-0042'),
                SectionHeader('Today'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('J-0042'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
    }
  });
}
