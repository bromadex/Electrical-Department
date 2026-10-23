import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.forum_outlined,
      title: 'Group chat',
      phase: 'Phase 2 · weeks 4–5',
      description: 'Department, site and project groups with photos, voice notes, @mentions and # record tags.',
    );
  }
}
