import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Back arrow that always works: it goes back when there is somewhere to go
/// back to, and to Home when the screen was opened from a link or a push
/// notification.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback = '/home', this.arrow = false});

  final String fallback;

  /// Android's ← arrow instead of the iOS chevron (chat screens).
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: Icon(arrow ? Icons.arrow_back : CupertinoIcons.back),
      onPressed: () => context.canPop() ? context.pop() : context.go(fallback),
    );
  }
}
