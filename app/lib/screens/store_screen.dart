import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.inventory_2_outlined,
      title: 'Electrical store',
      phase: 'Phase 4 · weeks 8–10',
      description:
          'Stock on hand, issues, receipts, material requests and purchases.',
    );
  }
}
