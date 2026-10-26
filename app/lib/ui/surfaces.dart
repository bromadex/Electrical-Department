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
      ? Colors.white.withValues(alpha: 0.075)
      : Colors.white.withValues(alpha: 0.66);
  Color get fillStrong => dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.82);
  Color get fillInset => dark
      ? Colors.black.withValues(alpha: 0.22)
      : const Color(0xFF1B1D2A).withValues(alpha: 0.04);
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
      Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
      Colors.white.withValues(alpha: 0),
      Colors.white.withValues(alpha: dark ? 0.03 : 0.18),
    ],
    stops: const [0, 0.55, 1],
  );

  /// The bright rim of liquid glass: strongest top-left, fading, then a
  /// softer glint bottom-right.
  Gradient get rim => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: dark
        ? [
            Colors.white.withValues(alpha: 0.32),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.16),
          ]
        : [
            Colors.white,
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0.9),
          ],
    stops: const [0, 0.5, 1],
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
          ),
          foregroundDecoration: RimDecoration(radius: radius, gradient: g.rim),
          child: child,
        ),
      ),
    );
  }
}

/// A 1.2 px gradient outline: the specular edge of liquid glass.
class RimDecoration extends Decoration {
  const RimDecoration({required this.radius, required this.gradient});

  final double radius;
  final Gradient gradient;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _RimPainter(radius, gradient);
}

class _RimPainter extends BoxPainter {
  _RimPainter(this.radius, this.gradient);

  final double radius;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final size = config.size;
    if (size == null) return;
    final rect = (offset & size).deflate(0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = gradient.createShader(rect),
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
        boxShadow: g.shadow,
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: RimDecoration(
          radius: radius,
          gradient: gradient == null
              ? g.rim
              : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.5),
                    Colors.white.withValues(alpha: 0.1),
                  ],
                ),
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
            colors: [Color(0xFF15131A), Color(0xFF0E0E12), Color(0xFF0B0B0F)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFF6F6FA), Color(0xFFF0F1F6)],
          );
    final glows = dark
        ? [
            BrandColors.maroon.withValues(alpha: 0.55),
            BrandColors.info.withValues(alpha: 0.22),
            BrandColors.coral.withValues(alpha: 0.30),
          ]
        : [
            BrandColors.blush.withValues(alpha: 0.45),
            BrandColors.info.withValues(alpha: 0.16),
            BrandColors.coral.withValues(alpha: 0.18),
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
