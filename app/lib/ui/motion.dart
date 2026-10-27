import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/tokens.dart';

extension EntranceX on Widget {
  /// Fades and lifts the widget into place, delayed by [index] steps so
  /// lists cascade in. Skipped when the system asks to reduce motion.
  Widget entrance(BuildContext context, {int index = 0, double dy = 16}) {
    if (Motion.reduced(context)) return this;
    return animate(delay: Motion.stagger * index)
        .fadeIn(duration: Motion.slow, curve: Motion.emphasized)
        .moveY(
          begin: dy,
          end: 0,
          duration: Motion.slow,
          curve: Motion.decelerate,
        );
  }
}

/// Grows a little under the mouse pointer, shrinks slightly while pressed,
/// then springs back.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.hoverScale = 1.05,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Size under a mouse pointer; touch screens never hover.
  final double hoverScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  void _hovering(bool v) {
    if (widget.onTap == null || v == _hover) return;
    setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => _hovering(true),
      onExit: (_) => _hovering(false),
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down
              ? widget.scale
              : _hover
              ? widget.hoverScale
              : 1,
          duration: Motion.of(context, Motion.fast),
          curve: _down ? Curves.easeOut : Motion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Counts up to [value] whenever it changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: Motion.of(context, Motion.slow * 2),
      curve: Motion.decelerate,
      builder: (context, v, _) => Text(
        v.round().toString(),
        style: style?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Slowly floats its child up and down.
class Floating extends StatelessWidget {
  const Floating({super.key, required this.child, this.distance = 6});

  final Widget child;
  final double distance;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return child
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(
          begin: -distance / 2,
          end: distance / 2,
          duration: 2600.ms,
          curve: Curves.easeInOutSine,
        );
  }
}
