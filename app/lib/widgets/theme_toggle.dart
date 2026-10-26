import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode.dart';
import '../ui/surfaces.dart';

/// Sun / moon button in the top bar: switches between light and dark.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key, this.glass = false});

  /// Desktop header style: square glass button.
  final bool glass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    void toggle() {
      HapticFeedback.selectionClick();
      ref
          .read(themeModeProvider.notifier)
          .set(dark ? ThemeMode.light : ThemeMode.dark);
    }

    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, a) => RotationTransition(
        turns: Tween(begin: 0.75, end: 1.0).animate(a),
        child: FadeTransition(opacity: a, child: child),
      ),
      child: Icon(
        dark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
        key: ValueKey(dark),
      ),
    );
    final tooltip = dark ? 'Light theme' : 'Dark theme';
    if (glass) {
      return GlassIconButton(tooltip: tooltip, onPressed: toggle, icon: icon);
    }
    return IconButton(tooltip: tooltip, onPressed: toggle, icon: icon);
  }
}
