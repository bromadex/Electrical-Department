import 'package:electrical_department/theme/app_theme.dart';
import 'package:electrical_department/v2/ui/bits.dart';
import 'package:electrical_department/v2/ui/data_table.dart';
import 'package:electrical_department/v2/ui/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Size size = const Size(1280, 900)}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test('initials come from up to two name parts', () {
    expect(AppAvatar.initials('Tatenda Ncube'), 'TN');
    expect(AppAvatar.initials('farai.chikwanha@bravura.test'), 'FC');
    expect(AppAvatar.initials('  '), '?');
  });

  testWidgets('empty state shows title, message and action', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmptyState(
          icon: Icons.assignment_outlined,
          title: 'No job cards',
          message: 'Nothing matches these filters.',
          action: TextButton(
            onPressed: () {},
            child: const Text('Clear filters'),
          ),
        ),
      ),
    );
    expect(find.text('No job cards'), findsOneWidget);
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('status and priority always show text and an icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            StatusPill(JobStatus.awaitingReview),
            PriorityBadge(Priority.p1, showName: true),
            SlaChip(SlaState.overdue),
            CriticalFlag(),
          ],
        ),
      ),
    );
    expect(find.text('Awaiting engineering review'), findsOneWidget);
    expect(find.byIcon(JobStatus.awaitingReview.icon), findsOneWidget);
    expect(find.text('P1 · Emergency'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
  });

  Widget table(Size size, {void Function(String)? onTap}) => _wrap(
    PagedTable<String>(
      rows: const ['EL-JC-2026-0001', 'EL-JC-2026-0002'],
      total: 30,
      page: 0,
      pageSize: 25,
      onPage: (_) {},
      onTap: onTap,
      columns: [TableCol('Job card', (r) => Text(r))],
      cardBuilder: (r) => Card(child: Text('card $r')),
    ),
    size: size,
  );

  testWidgets('table shows rows, paging and opens a row on desktop', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      table(const Size(1280, 900), onTap: (r) => opened = r),
    );
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('1–25 of 30'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('EL-JC-2026-0002'));
    expect(opened, 'EL-JC-2026-0002');
  });

  testWidgets('table becomes cards on a phone', (tester) async {
    await tester.pumpWidget(table(const Size(390, 844)));
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('card EL-JC-2026-0001'), findsOneWidget);
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
                RecordCode('EL-JC-2026-0042'),
                SectionHeader('Today'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('EL-JC-2026-0042'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
    }
  });
}
