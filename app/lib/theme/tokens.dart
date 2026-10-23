import 'package:flutter/material.dart';

/// Colours sampled from the Bravura rhino logo.
class BrandColors {
  static const maroon = Color(0xFF982329);
  static const maroonDeep = Color(0xFF6E141A);
  static const coral = Color(0xFFFF7176);
  static const blush = Color(0xFFF9ACB9);

  /// Status colours used by pills and charts.
  static const success = Color(0xFF1F9D6B);
  static const warning = Color(0xFFE59A1A);
  static const info = Color(0xFF3B7DD8);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [maroonDeep, maroon, coral],
    stops: [0, 0.55, 1],
  );
}

/// 4-point spacing scale.
class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class Radii {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Durations and curves shared by every animation, so motion feels consistent.
class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const stagger = Duration(milliseconds: 45);

  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const decelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const spring = Curves.easeOutBack;

  /// True when the user asked the system to reduce motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
