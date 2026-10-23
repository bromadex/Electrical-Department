import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.today_outlined,
      title: 'Today',
      phase: 'Phase 2 · weeks 4–5',
      description: "Your daily checklists, today's jobs and the daily report.",
    );
  }
}
