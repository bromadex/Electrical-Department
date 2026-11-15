import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart' show BrandColors, ChatColors;

class AppTheme {
  /// Chat screens only (docs/plan-whatsapp-theme.md, Phase B): WhatsApp
  /// for iPhone's look, light or dark as the phone is set (like WhatsApp),
  /// whatever the rest of the app uses. White or true-black lists, green
  /// buttons and selection, iOS blue links, WhatsApp's type sizes and
  /// outline icons.
  static ThemeData chat(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = _build(brightness);
    final green = dark ? ChatColors.greenLight : ChatColors.green;
    final fg = dark ? ChatColors.textDark : ChatColors.text;
    final sub = dark ? ChatColors.subtextDark : ChatColors.subtext;
    final bg = dark ? ChatColors.listDark : ChatColors.list;
    final grouped = dark ? ChatColors.groupedDark : ChatColors.grouped;
    final divider = dark ? ChatColors.dividerDark : ChatColors.divider;
    final c = base.colorScheme.copyWith(
      primary: green,
      onPrimary: dark ? Colors.black : Colors.white,
      primaryContainer: dark ? ChatColors.chipDark : ChatColors.chip,
      onPrimaryContainer: dark ? ChatColors.chipTextDark : ChatColors.chipText,
      secondary: dark ? ChatColors.blueLight : ChatColors.blue,
      onSecondary: Colors.white,
      tertiary: ChatColors.greenBright,
      surface: bg,
      onSurface: fg,
      onSurfaceVariant: sub,
      surfaceContainerLowest: bg,
      surfaceContainerLow: grouped,
      surfaceContainer: grouped,
      surfaceContainerHigh: dark ? ChatColors.selectedDark : ChatColors.field,
      surfaceContainerHighest: dark
          ? ChatColors.selectedDark
          : ChatColors.selected,
      outline: sub,
      outlineVariant: divider,
      inverseSurface: fg,
      onInverseSurface: bg,
    );
    final t = base.textTheme;
    final text = t.copyWith(
      // The large "Chats" title.
      headlineLarge: t.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: fg,
      ),
      // Screen titles in the bar.
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: fg,
      ),
      // Names in the chat list.
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: fg,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
      // Message text.
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.3, color: fg),
      // Previews and message text in bubbles.
      bodyMedium: t.bodyMedium?.copyWith(
        fontSize: 15.5,
        height: 1.3,
        color: fg,
      ),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, color: sub),
      // Times, ticks, small labels.
      labelSmall: t.labelSmall?.copyWith(fontSize: 11.5, color: sub),
      labelMedium: t.labelMedium?.copyWith(fontSize: 13, color: sub),
    );
    return base.copyWith(
      colorScheme: c,
      textTheme: text,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 0.6, space: 1),
      iconTheme: IconThemeData(color: green, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: green),
        actionsIconTheme: IconThemeData(color: green),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: green,
        textColor: fg,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: sub),
        selectedTileColor: dark ? ChatColors.selectedDark : ChatColors.selected,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: grouped,
        selectedColor: dark ? ChatColors.chipDark : ChatColors.chip,
        labelStyle: text.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: sub,
        ),
        secondaryLabelStyle: text.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: dark ? ChatColors.chipTextDark : ChatColors.chipText,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: dark ? ChatColors.fieldDark : ChatColors.field,
        hintStyle: text.bodyMedium?.copyWith(color: sub),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: green, width: 1.2),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: green,
        textColor: dark ? Colors.black : Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: dark ? Colors.black : Colors.white,
        shape: const CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: dark ? Colors.black : Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: green),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? green : null,
        ),
        shape: const CircleBorder(),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? green : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: green),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: dark ? ChatColors.groupedDark : Colors.white,
        modalBackgroundColor: dark ? ChatColors.groupedDark : Colors.white,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: dark ? ChatColors.groupedDark : Colors.white,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: dark ? ChatColors.groupedDark : Colors.white,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: green,
        selectionHandleColor: green,
        selectionColor: green.withValues(alpha: 0.3),
      ),
    );
  }

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
