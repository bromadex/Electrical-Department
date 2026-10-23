import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Frosted glass panel: blurs whatever is behind it.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Radii.xl,
    this.blur = 24,
    this.padding,
    this.opacity,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest.withValues(
              alpha: opacity ?? (dark ? 0.62 : 0.72),
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: (dark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Rounded card with a hairline border and optional tap.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.onTap,
    this.color,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radii.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color ?? scheme.surfaceContainerLowest : null,
        gradient: gradient,
        borderRadius: radius,
        border: gradient == null
            ? Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: scheme.brightness == Brightness.dark ? 0.35 : 0.6,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Soft brand-coloured blobs drifting slowly behind content.
class MeshBackground extends StatefulWidget {
  const MeshBackground({super.key, this.child, this.intensity = 1});

  final Widget? child;
  final double intensity;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = (dark ? 0.32 : 0.42) * widget.intensity;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surface),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _BlobPainter(_controller.value * 2 * math.pi, [
              BrandColors.coral.withValues(alpha: a),
              BrandColors.maroon.withValues(alpha: a * 0.9),
              BrandColors.blush.withValues(alpha: a),
            ]),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: const SizedBox.expand(),
        ),
        ?widget.child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final blobs = [
      (Offset(0.2 + 0.08 * math.sin(t), 0.18 + 0.06 * math.cos(t)), 0.55),
      (Offset(0.85 + 0.06 * math.cos(t * 1.3), 0.3 + 0.08 * math.sin(t)), 0.5),
      (Offset(0.5 + 0.1 * math.sin(t * 0.7), 0.95 + 0.05 * math.cos(t)), 0.65),
    ];
    for (var i = 0; i < blobs.length; i++) {
      final (pos, r) = blobs[i];
      final center = Offset(pos.dx * size.width, pos.dy * size.height);
      canvas.drawCircle(
        center,
        r * s,
        Paint()
          ..shader = RadialGradient(
            colors: [colors[i], colors[i].withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r * s)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t;
}
