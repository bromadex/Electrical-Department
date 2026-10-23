import 'package:flutter/material.dart';

/// Colours sampled from the Bravura rhino logo.
class BrandColors {
  static const maroon = Color(0xFF982329);
  static const coral = Color(0xFFFF7176);
  static const blush = Color(0xFFF9ACB9);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: BrandColors.maroon,
          brightness: brightness,
        ).copyWith(
          primary: brightness == Brightness.light
              ? BrandColors.maroon
              : BrandColors.blush,
          secondary: BrandColors.coral,
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
