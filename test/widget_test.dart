import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_department/screens/setup_required_screen.dart';

void main() {
  testWidgets('setup screen explains missing Supabase config', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetupRequiredScreen()));
    expect(find.text('Setup required'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
