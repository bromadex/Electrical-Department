import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.inventory_2_rounded,
      title: 'Electrical store',
      phase: 'Phase 4 · weeks 8–10',
      description:
          'Stock on hand per site, issues to jobs and projects, receipts, '
          'counts and low-stock alerts.',
      highlights: [
        (Icons.qr_code_scanner_rounded, 'Issue & receive'),
        (Icons.trending_down_rounded, 'Low stock'),
        (Icons.receipt_long_outlined, 'Material requests'),
        (Icons.table_chart_outlined, 'BOQ'),
      ],
    );
  }
}
