import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Colours for glass on the ambient backdrop, per brightness. In the dark
/// theme (the liquid glass of issue #26) every layer is white or black at
/// low opacity over the burgundy backdrop, in four levels, each more solid:
/// panel, tile, control, modal.
class Glass {
  const Glass._(this.dark);

  factory Glass.of(BuildContext context) =>
      Glass._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  static Color _w(double a) => Colors.white.withValues(alpha: a);

  /// Controls: buttons, icon buttons, chips (hover: [fillStrong]).
  Color get fill => dark ? _w(0.13) : _w(0.66);
  Color get fillStrong => dark ? _w(0.22) : _w(0.82);

  /// Inputs: a dark well.
  Color get fillInset => dark
      ? Colors.black.withValues(alpha: 0.30)
      : const Color(0xFF1B1D2A).withValues(alpha: 0.04);

  /// Behind a card's sheen; in the dark the sheen is the whole fill.
  Color get panelFill => dark ? Colors.transparent : _w(0.66);
  Color get border => dark ? _w(0.17) : _w(0.85);
  Color get hairline =>
      dark ? _w(0.07) : BrandColors.maroon.withValues(alpha: 0.08);

  /// Modals, sheets and menus: the most solid layer, a dark burgundy tint.
  Color get modal => dark
      ? BrandColors.maroonDeep.withValues(alpha: 0.76)
      : Colors.white.withValues(alpha: 0.94);
  Color get modalBorder => dark ? _w(0.32) : _w(0.9);

  /// Panels: white 15% → 4.5% → 8% at 150°.
  Gradient get sheen => dark
      ? LinearGradient(
          begin: const Alignment(-0.5, -1),
          end: const Alignment(0.5, 1),
          colors: [_w(0.15), _w(0.045), _w(0.08)],
          stops: const [0, 0.48, 1],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_w(0.55), _w(0), _w(0.18)],
          stops: const [0, 0.55, 1],
        );

  /// Tiles: stats and list items, white 11% → 3.5%.
  Gradient get tile => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: dark ? [_w(0.11), _w(0.035)] : [_w(0.7), _w(0.5)],
  );

  /// The rim: light catching the top edge (55%), a softer left edge, a
  /// faint bottom.
  Gradient get rim => dark
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_w(0.55), _w(0.17), _w(0.16), _w(0.07)],
          stops: const [0, 0.08, 0.5, 1],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, _w(0.45), _w(0.9)],
          stops: const [0, 0.5, 1],
        );

  List<BoxShadow> get shadow => [
    dark
        ? BoxShadow(
            color: AppColors.night.withValues(alpha: 0.38),
            blurRadius: 48,
            offset: const Offset(0, 18),
          )
        : BoxShadow(
            color: BrandColors.maroonDeep.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
  ];

  /// Blur with the glass "pop": more saturated and a touch brighter
  /// behind the pane.
  static ImageFilter frost(double sigma, {double saturate = 1.9}) {
    final s = saturate;
    const b = 1.06;
    final r = (1 - s) * 0.2126, g = (1 - s) * 0.7152, bl = (1 - s) * 0.0722;
    final matrix = <double>[
      (r + s) * b, g * b, bl * b, 0, 0, //
      r * b, (g + s) * b, bl * b, 0, 0,
      r * b, g * b, (bl + s) * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ImageFilter.compose(
      outer: ColorFilter.matrix(matrix),
      inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }
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
    this.saturate = 1.9,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final bool strong;

  /// Colour boost behind dark glass; large panes use less so the red
  /// glows do not turn pink.
  final double saturate;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (g.dark && radius == 0) {
      // A top bar: the backdrop colour fading out, softly blurred.
      return ClipRect(
        child: BackdropFilter(
          filter: Glass.frost(22, saturate: 1.6),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.night.withValues(alpha: 0.55),
                  AppColors.night.withValues(alpha: 0),
                ],
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: g.dark
            ? Glass.frost(blur > 28 ? blur : 30, saturate: saturate)
            : ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: g.dark
                ? (strong ? Colors.white.withValues(alpha: 0.06) : null)
                : Color.alphaBlend(
                    strong ? g.fillStrong : g.fill,
                    scheme.surface.withValues(alpha: 0.35),
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
        ..strokeWidth = 1.1
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
        color: gradient == null ? color ?? g.panelFill : null,
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

/// Glass card with an optional header row (icon, title, subtitle, actions):
/// the building block of dashboards and detail pages.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      radius: Radii.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.xs,
                0,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: Space.xs),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: theme.textTheme.titleSmall),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                  if (actions.isEmpty) const SizedBox(height: 40),
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Summary number that opens the matching filtered list.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.adapt(color, theme.brightness);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      radius: Radii.lg,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, color: c, size: 22),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: theme.textTheme.labelSmall?.copyWith(color: c),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
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
    with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  // The dark theme's two drifting blobs (34 s and 40 s, there and back).
  late final _blobA = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 34),
  );
  late final _blobB = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (Motion.reduced(context)) {
      _controller.stop();
      _blobA.stop();
      _blobB.stop();
    } else if (dark) {
      _controller.stop();
      if (!_blobA.isAnimating) _blobA.repeat(reverse: true);
      if (!_blobB.isAnimating) _blobB.repeat(reverse: true);
    } else {
      _blobA.stop();
      _blobB.stop();
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _blobA.dispose();
    _blobB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.nightLift, AppColors.night],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_blobA, _blobB]),
                  builder: (context, _) => CustomPaint(
                    painter: _NightPainter(
                      Curves.easeInOut.transform(_blobA.value),
                      Curves.easeInOut.transform(_blobB.value),
                    ),
                  ),
                ),
              ),
            ),
            ?widget.child,
          ],
        ),
      );
    }
    const base = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFFFFF), Color(0xFFF6F6FA), Color(0xFFF0F1F6)],
    );
    final glows = [
      BrandColors.blush.withValues(alpha: 0.45),
      BrandColors.info.withValues(alpha: 0.16),
      BrandColors.coral.withValues(alpha: 0.18),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: base),
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

/// The dark glass backdrop: three soft brand-colour glows (top-left,
/// top-right, bottom-centre) and two big blurred blobs that drift.
class _NightPainter extends CustomPainter {
  _NightPainter(this.a, this.b);

  /// 0..1, eased: where each blob is on its path.
  final double a;
  final double b;

  @override
  void paint(Canvas canvas, Size size) {
    final vmax = size.longestSide;
    void glow(Offset at, double radius, Color color) {
      final rect = Rect.fromCircle(center: at, radius: radius);
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 0.6],
          ).createShader(rect),
      );
    }

    glow(
      Offset(size.width * 0.05, size.height * 0.02),
      vmax * 0.75,
      BrandColors.maroon.withValues(alpha: 0.55),
    );
    glow(
      Offset(size.width * 0.98, size.height * 0.08),
      vmax * 0.65,
      BrandColors.coral.withValues(alpha: 0.38),
    );
    glow(
      Offset(size.width * 0.5, size.height * 1.05),
      vmax * 0.7,
      BrandColors.maroon.withValues(alpha: 0.30),
    );

    // Blobs: 50vmax circles, blurred, drifting slowly.
    final blur = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46);
    canvas.drawCircle(
      Offset(size.width * (0.18 + 0.22 * a), size.height * (0.30 + 0.18 * a)),
      vmax * 0.25,
      blur..color = BrandColors.coral.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      Offset(size.width * (0.82 - 0.25 * b), size.height * (0.72 - 0.2 * b)),
      vmax * 0.25,
      blur..color = BrandColors.maroon.withValues(alpha: 0.30),
    );
  }

  @override
  bool shouldRepaint(_NightPainter old) => old.a != a || old.b != b;
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
