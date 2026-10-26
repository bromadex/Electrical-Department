import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      icon: Icons.forum_rounded,
      title: 'Team chat',
      phase: 'Phase 2 · weeks 4–5',
      description:
          'Department, site and project groups. Tag any record with # and '
          'turn a message into a job in one tap.',
      highlights: [
        (Icons.photo_outlined, 'Photos'),
        (Icons.mic_none_rounded, 'Voice notes'),
        (Icons.alternate_email_rounded, '@mentions'),
        (Icons.tag_rounded, '# record tags'),
      ],
    );
  }
}
