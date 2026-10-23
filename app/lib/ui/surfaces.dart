import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Colours for glass panels on the ambient backdrop, per brightness.
class Glass {
  const Glass._(this.dark);

  factory Glass.of(BuildContext context) =>
      Glass._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get fill => dark
      ? Colors.white.withValues(alpha: 0.065)
      : Colors.white.withValues(alpha: 0.58);
  Color get fillStrong => dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.78);
  Color get fillInset => dark
      ? Colors.black.withValues(alpha: 0.22)
      : BrandColors.maroon.withValues(alpha: 0.05);
  Color get border => dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.85);
  Color get hairline => dark
      ? Colors.white.withValues(alpha: 0.07)
      : BrandColors.maroon.withValues(alpha: 0.08);

  /// Light catching the top-left edge of a pane.
  Gradient get sheen => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: dark ? 0.07 : 0.35),
      Colors.white.withValues(alpha: 0),
    ],
    stops: const [0, 0.6],
  );

  List<BoxShadow> get shadow => [
    BoxShadow(
      color: (dark ? Colors.black : BrandColors.maroonDeep).withValues(
        alpha: dark ? 0.28 : 0.08,
      ),
      blurRadius: 30,
      offset: const Offset(0, 14),
    ),
  ];
}

/// Frosted glass panel that blurs whatever is behind it. Use for bars and
/// floating chrome; cards use [SurfaceCard], which skips the costly blur.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Radii.xl,
    this.blur = 28,
    this.padding,
    this.strong = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              strong ? g.fillStrong : g.fill,
              scheme.surface.withValues(alpha: g.dark ? 0.55 : 0.35),
            ),
            gradient: g.sheen,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: g.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glass card: translucent fill, hairline border, sheen and soft shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.onTap,
    this.color,
    this.gradient,
    this.radius = Radii.xl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color ?? g.fill : null,
        gradient: gradient,
        borderRadius: r,
        border: Border.all(
          color: gradient == null
              ? g.border
              : Colors.white.withValues(alpha: 0.18),
        ),
        boxShadow: g.shadow,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: g.sheen, borderRadius: r),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Card with an icon + title header, like the panels of a dashboard.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(Space.lg - 4),
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

/// Square glass button for icons, like the bell in the top bar.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final button = Material(
      color: g.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: g.border),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: icon),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The app's ambient backdrop: deep wine with slow, soft glows of the
/// Bravura colours. Light mode uses blush and cream.
class MeshBackground extends StatefulWidget {
  const MeshBackground({super.key, this.child});

  final Widget? child;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
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
    final base = dark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A0B11), Color(0xFF1A070B), Color(0xFF12050A)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFDF3F2), Color(0xFFF7E4E6), Color(0xFFF3DDE0)],
          );
    final glows = dark
        ? [
            BrandColors.maroon.withValues(alpha: 0.75),
            BrandColors.coral.withValues(alpha: 0.28),
            const Color(0xFF6E141A).withValues(alpha: 0.8),
          ]
        : [
            BrandColors.blush.withValues(alpha: 0.7),
            BrandColors.coral.withValues(alpha: 0.25),
            BrandColors.blush.withValues(alpha: 0.55),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(gradient: base),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _GlowPainter(_controller.value * 2 * math.pi, glows),
              ),
            ),
          ),
          ?widget.child,
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.longestSide;
    final glows = [
      (Offset(0.12 + 0.06 * math.sin(t), 0.1 + 0.05 * math.cos(t)), 0.55),
      (Offset(0.9 + 0.05 * math.cos(t * 1.3), 0.35 + 0.08 * math.sin(t)), 0.4),
      (Offset(0.45 + 0.1 * math.sin(t * 0.7), 1.0 + 0.05 * math.cos(t)), 0.6),
    ];
    for (var i = 0; i < glows.length; i++) {
      final (pos, r) = glows[i];
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
  bool shouldRepaint(_GlowPainter old) => old.t != t;
}
