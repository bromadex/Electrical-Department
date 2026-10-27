import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart' show BrandColors;

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: BrandColors.maroon,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: dark ? BrandColors.blush : BrandColors.maroon,
          onPrimary: dark ? BrandColors.maroonDeep : Colors.white,
          secondary: dark ? AppColors.blueLight : BrandColors.info,
          tertiary: BrandColors.coral,
          // Dark glass (issue #26): near-white text with two muted levels
          // (onSurfaceVariant, outline), all white over the burgundy night.
          onSurface: dark ? const Color(0xFFFBF4F6) : null,
          onSurfaceVariant: dark
              ? const Color(0xFFD9C9CE)
              : const Color(0xFF3E3944),
          outline: dark ? const Color(0xFFA9969B) : null,
          outlineVariant: dark
              ? const Color(0xFF55383F)
              : const Color(0xFFD9D6DF),
          surface: dark ? AppColors.night : const Color(0xFFFAFAFC),
          surfaceContainerLowest: dark ? const Color(0xFF16070A) : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xFF2A1318)
              : const Color(0xFFF6F6F9),
          surfaceContainer: dark
              ? const Color(0xFF33191F)
              : const Color(0xFFF1F1F5),
          surfaceContainerHigh: dark
              ? const Color(0xFF3D2228)
              : const Color(0xFFEAEAF0),
          surfaceContainerHighest: dark ? const Color(0xFF482A31) : null,
          inverseSurface: dark ? const Color(0xFFFBF4F6) : null,
          onInverseSurface: dark ? AppColors.night : null,
        );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      brightness: brightness,
    );
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final outline = dark
        ? Colors.white.withValues(alpha: 0.17)
        : scheme.outlineVariant.withValues(alpha: 0.6);
    // Modals, sheets and menus: the most solid glass, a burgundy tint.
    final modal = dark
        ? BrandColors.maroonDeep.withValues(alpha: 0.94)
        : scheme.surfaceContainerLowest;
    final modalSide = dark
        ? BorderSide(color: Colors.white.withValues(alpha: 0.32))
        : BorderSide.none;

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      // Visible focus rings for keyboard users.
      focusColor: dark
          ? Colors.white.withValues(alpha: 0.22)
          : BrandColors.maroon.withValues(alpha: 0.12),
      hoverColor: dark ? Colors.white.withValues(alpha: 0.08) : null,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // iPhone-style: pages slide in from the right, swipe back to go back.
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.black.withValues(alpha: 0.30)
            : scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
        backgroundColor: dark
            ? Colors.white.withValues(alpha: 0.13)
            : scheme.surfaceContainerLow,
        selectedColor: dark ? Colors.white.withValues(alpha: 0.24) : null,
        labelStyle: text.labelMedium,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md),
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF4A1A23) : scheme.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: dark ? scheme.onSurface : scheme.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: modal,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: dark ? Colors.white.withValues(alpha: 0.45) : null,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.xl),
          ),
          side: modalSide,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: modal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: modalSide,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: modal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: dark ? modalSide : BorderSide(color: outline),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          side: BorderSide(color: outline),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        textStyle: text.labelSmall?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}
