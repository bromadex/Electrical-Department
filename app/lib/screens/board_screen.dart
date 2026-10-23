import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.view_kanban_outlined,
      title: 'Jobs board',
      phase: 'Phase 1 · weeks 2–3',
      description: 'Post, take, assign and close jobs with photos, location and comments.',
    );
  }
}
