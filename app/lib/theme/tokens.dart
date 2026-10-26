import 'package:flutter/material.dart';

/// Colours sampled from the Bravura rhino logo.
class BrandColors {
  static const maroon = Color(0xFF7A1F2B);
  static const maroonDeep = Color(0xFF4E1019);
  static const coral = Color(0xFFB5566E);
  static const blush = Color(0xFFE7A1B3);

  /// Status colours used by pills and charts.
  static const success = Color(0xFF1F9D6B);
  static const warning = Color(0xFFE59A1A);
  static const info = Color(0xFF2F6FDB);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [maroonDeep, maroon, Color(0xFF2F6FDB)],
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

/// The palette by meaning (job cards and charts): burgundy, dark rose and
/// blue as in [BrandColors], one colour per status. Meaning is never shown by
/// colour alone (see v2/ui/status.dart).
class AppColors {
  /// Primary: buttons, selected items, record numbers (light theme).
  static const burgundy = Color(0xFF7A1F2B);
  static const burgundyDeep = Color(0xFF4E1019);

  /// Primary on dark surfaces, light enough to read.
  static const burgundyLight = Color(0xFFE7A1B3);

  /// Accent: highlights, the selected menu marker, soft tints.
  static const rose = Color(0xFFB5566E);
  static const roseSoft = Color(0xFFF6E8EB);

  /// Secondary: links and information.
  static const blue = Color(0xFF2F6FDB);
  static const blueLight = Color(0xFF8AB4FF);

  /// Chrome: the side menu in both themes, tooltips, snack bars.
  static const black = Color(0xFF161113);
  static const blackRaised = Color(0xFF241B1F);

  static const canvas = Color(0xFFFAF7F8);
  static const canvasDark = Color(0xFF0F0B0D);
  static const panelDark = Color(0xFF1B1517);
  static const line = Color(0xFFEBE1E4);
  static const lineDark = Color(0xFF362B30);

  // Statuses keep their usual meaning colours so a critical red never looks
  // like the burgundy of an ordinary button.
  static const critical = Color(0xFFD92D20);
  static const warning = Color(0xFFE59A1A);
  static const success = Color(0xFF1F9D6B);
  static const info = blue;
  static const review = Color(0xFF6938EF);
  static const neutral = Color(0xFF6B6266);

  /// Bravura logo colour.
  static const brand = Color(0xFF982329);

  /// The readable version of a palette colour on dark surfaces.
  static Color adapt(Color c, Brightness brightness) {
    if (brightness != Brightness.dark) return c;
    if (c == burgundy || c == burgundyDeep) return burgundyLight;
    if (c == blue) return blueLight;
    return c;
  }
}

/// Screen widths where the layout changes.
class Breakpoints {
  /// Below this: phone layout (bottom bar, cards instead of tables).
  static const phone = 720.0;

  /// From this: desktop layout (full sidebar).
  static const desktop = 1100.0;
}
