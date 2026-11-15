import 'package:flutter/material.dart';

/// WhatsApp green with liquid glass (15 November 2026; before that the
/// burgundy of the Bravura logo). The names stay from then: maroon is the
/// main green, maroonDeep the darkest, coral the teal accent and blush the
/// light green that reads on dark glass.
class BrandColors {
  static const maroon = Color(0xFF008069);
  static const maroonDeep = Color(0xFF075E54);
  static const coral = Color(0xFF00A884);
  static const blush = Color(0xFF7AE2B8);

  /// Status colours used by pills and charts.
  static const success = Color(0xFF1F9D6B);
  static const warning = Color(0xFFE59A1A);
  static const info = Color(0xFF027EB5);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [maroonDeep, maroon, Color(0xFF25D366)],
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

/// Liquid glass radii (issue #26): 28 · 22 · 16 · 12, pills 999.
class Radii {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Durations and curves shared by every animation, so motion feels consistent.
class Motion {
  /// Hovers and presses.
  static const hover = Duration(milliseconds: 140);
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const stagger = Duration(milliseconds: 45);

  static const emphasized = Cubic(0.2, 0, 0, 1);

  /// The glass easing: quick out, soft landing.
  static const glass = Cubic(0.22, 0.8, 0.3, 1);
  static const decelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const spring = Curves.easeOutBack;

  /// True when the user asked the system to reduce motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// The palette by meaning (job cards and charts): WhatsApp greens and
/// blue as in [BrandColors] (the names are from the old burgundy palette),
/// one colour per status. Meaning is never shown by
/// colour alone (see v2/ui/status.dart).
class AppColors {
  /// Primary: buttons, selected items, record numbers (light theme).
  static const burgundy = Color(0xFF008069);
  static const burgundyDeep = Color(0xFF075E54);

  /// Primary on dark surfaces, light enough to read.
  static const burgundyLight = Color(0xFF7AE2B8);

  /// Accent: highlights, the selected menu marker, soft tints.
  static const rose = Color(0xFF00A884);
  static const roseSoft = Color(0xFFE7F8EE);

  /// Secondary: links and information.
  static const blue = Color(0xFF027EB5);
  static const blueLight = Color(0xFF53BDEB);

  /// Chrome: the side menu in both themes, tooltips, snack bars.
  static const black = Color(0xFF111B21);
  static const blackRaised = Color(0xFF202C33);

  /// The dark glass backdrop (issue #26): WhatsApp's deep night green, and
  /// the slightly lighter shade its gradient starts from.
  static const night = Color(0xFF0B141A);
  static const nightLift = Color(0xFF0F2A26);

  static const canvas = Color(0xFFF0F2F5);
  static const canvasDark = Color(0xFF0B141A);
  static const panelDark = Color(0xFF111B21);
  static const line = Color(0xFFE9EDEF);
  static const lineDark = Color(0xFF2A3942);

  // Statuses keep their usual meaning colours so a critical red never looks
  // like the green of an ordinary button.
  static const critical = Color(0xFFD92D20);
  static const warning = Color(0xFFE59A1A);
  static const success = Color(0xFF1F9D6B);
  static const info = blue;
  static const review = Color(0xFF6938EF);
  static const neutral = Color(0xFF667781);

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
