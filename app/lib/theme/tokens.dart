import 'package:flutter/material.dart';

/// Industrial palette: navy chrome, a light workspace and one colour per
/// meaning. Meaning is never shown by colour alone (see ui/status.dart).
class AppColors {
  static const navy950 = Color(0xFF071327);
  static const navy900 = Color(0xFF0B1D39);
  static const navy800 = Color(0xFF12294D);
  static const navy700 = Color(0xFF1B3A69);
  static const navy600 = Color(0xFF2A5291);
  static const navy100 = Color(0xFFE4EAF4);

  static const canvas = Color(0xFFF2F4F8);
  static const canvasDark = Color(0xFF0C1320);
  static const panelDark = Color(0xFF141E30);
  static const line = Color(0xFFE2E7EF);
  static const lineDark = Color(0xFF26334A);

  static const critical = Color(0xFFD92D20);
  static const warning = Color(0xFFDC6803);
  static const success = Color(0xFF079455);
  static const info = Color(0xFF1570EF);
  static const review = Color(0xFF6938EF);
  static const neutral = Color(0xFF667085);

  /// Bravura maroon: the brand mark only, never a status.
  static const brand = Color(0xFF982329);
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
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const pill = 999.0;
}

/// Screen widths where the layout changes.
class Breakpoints {
  /// Below this: phone layout (bottom bar, cards instead of tables).
  static const phone = 720.0;

  /// From this: desktop layout (full sidebar).
  static const desktop = 1100.0;
}

/// Short, plain transitions; nothing moves when the system asks for less motion.
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 220);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
