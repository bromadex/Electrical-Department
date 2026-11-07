import 'package:electrical_department/store/store_count_screen.dart';
import 'package:electrical_department/store/store_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StoreItem item({
  String id = 'i1',
  double onHand = 10,
  double minLevel = 0,
  String? bin = 'A1',
}) => StoreItem.fromJson({
  'id': id,
  'site_id': 's1',
  'code': 'I-0001',
  'name': '20mm brass gland',
  'unit': 'pcs',
  'category': 'glands',
  'bin': bin,
  'min_level': minLevel,
  'on_hand': onHand,
});

StockMove move(String kind, double qty) => StockMove.fromJson({
  'id': 'm1',
  'kind': kind,
  'qty': qty,
  'balance_after': 10,
  'created_at': '2026-11-07T08:00:00Z',
});

void main() {
  test('quantities drop needless decimals', () {
    expect(qtyText(12), '12');
    expect(qtyText(12.5), '12.5');
    expect(qtyText(0.25), '0.25');
    expect(qtyText(0), '0');
  });

  test('low and empty stock', () {
    expect(item(onHand: 4, minLevel: 5).low, isTrue);
    expect(item(onHand: 5, minLevel: 5).low, isFalse);
    expect(item(onHand: 0).low, isFalse, reason: 'no minimum set');
    expect(item(onHand: 0).empty, isTrue);
  });

  test('movements read as what happened', () {
    expect(moveTitle(move('receive', 120), 'm', null), '+120 m received');
    expect(moveTitle(move('issue', -20), 'm', 'J-0012'), '−20 m to J-0012');
    expect(moveTitle(move('issue', -1), 'pcs', null), '−1 pcs to someone');
    expect(
      moveTitle(move('return', 6), 'm', 'Tinashe'),
      '+6 m back from Tinashe',
    );
    expect(moveTitle(move('adjust', -2), 'pcs', null), '−2 pcs adjusted');
    expect(moveTitle(move('count', -5), 'pcs', null), '−5 pcs on count');
  });

  test('a count only reports the items that differ', () {
    final items = [item(id: 'a', onHand: 10), item(id: 'b', onHand: 3)];
    expect(countDifferences(items, {'a': 10, 'b': 1}), {'b': -2.0});
    expect(countDifferences(items, {'a': 12}), {'a': 2.0});
    expect(countDifferences(items, {}), isEmpty);
  });

  test('the saved stock list comes back as it was saved', () {
    final at = DateTime(2026, 11, 7, 10, 30);
    final saved = decodeStock(
      encodeStock([item(onHand: 7.5, minLevel: 10)], at),
    )!;
    expect(saved.offline, isTrue);
    expect(saved.savedAt, at);
    expect(saved.items.single.onHand, 7.5);
    expect(saved.items.single.low, isTrue);
    expect(saved.items.single.bin, 'A1');
    expect(decodeStock('not json'), isNull);
    expect(decodeStock(null), isNull);
  });

  testWidgets('a count line shows the difference as it is typed', (
    tester,
  ) async {
    double? counted;
    Widget line() => MaterialApp(
      home: Scaffold(
        body: CountLine(
          item: item(onHand: 10),
          counted: counted,
          onChanged: (v) => counted = v,
        ),
      ),
    );
    await tester.pumpWidget(line());
    expect(find.textContaining('system 10 pcs'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '7');
    expect(counted, 7);
    await tester.pumpWidget(line());
    expect(find.text('−3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '10');
    await tester.pumpWidget(line());
    expect(find.text('−3'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    expect(counted, isNull, reason: 'an empty box is not counted');
  });
}
