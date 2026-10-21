import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds Cairn's [ThemeData] from the Oracle DESIGN.md tokens.
///
/// Binding rules honoured here (DESIGN.md / docs/design.md):
/// - every primary action is the warm charcoal [CairnColors.primary];
/// - brand red appears in the wordmark widget only, never in the theme;
/// - no shadows/elevation — depth is tonal (ladder) + hairlines;
/// - buttons radius xs (4), inputs radius sm (6) with field-border,
///   cards/modals radius md (8) with hairline borders;
/// - type: headings jump to weight 800, body 16/400, labels 14/500.
/// Typeface: Arad (Persian primary) with Inter as Latin fallback.
ThemeData buildCairnTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final canvas = dark ? CairnColors.darkCanvas : CairnColors.canvas;
  final surfaceSoft =
      dark ? CairnColors.darkCanvasSoft : CairnColors.canvasSoft;
  final surfaceTint =
      dark ? CairnColors.darkCanvasTint : CairnColors.canvasTint;
  final hairline = dark ? CairnColors.darkHairline : CairnColors.hairline;
  final fieldBorder =
      dark ? CairnColors.darkFieldBorder : CairnColors.fieldBorder;
  final ink = dark ? CairnColors.darkInk : CairnColors.ink;
  final inkMuted = dark ? CairnColors.darkInkMuted : CairnColors.primaryPressed;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: CairnColors.primary,
    onPrimary: CairnColors.onPrimary,
    secondary: CairnColors.link,
    onSecondary: CairnColors.onPrimary,
    error: CairnColors.error,
    onError: CairnColors.onPrimary,
    surface: canvas,
    onSurface: ink,
    surfaceContainerHighest: surfaceTint,
    onSurfaceVariant: inkMuted,
    outline: hairline,
    outlineVariant: fieldBorder,
  );

  final textTheme = TextTheme(
    // DESIGN.md heading scale: weight 800, tight line heights.
    headlineLarge: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w800, height: 33.6 / 28, color: ink),
    headlineMedium: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w800, height: 28.8 / 24, color: ink),
    headlineSmall: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w800, height: 24 / 20, color: ink),
    titleMedium: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800, height: 21.6 / 18, color: ink),
    // Body 16/400 (line height 22.4).
    bodyLarge: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w400, height: 22.4 / 16, color: ink),
    bodyMedium: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w400, height: 22.4 / 16, color: ink),
    // Label 14/500, caption 12/400.
    labelLarge: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w500, height: 16.8 / 14, color: ink),
    bodySmall: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w400, height: 20 / 12, color: inkMuted),
  ).apply(fontFamily: CairnFonts.persian, fontFamilyFallback: CairnFonts.fallback);

  final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CairnRadii.xs));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    textTheme: textTheme,
    fontFamily: CairnFonts.persian,
    fontFamilyFallback: CairnFonts.fallback,
    dividerColor: hairline,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CairnRadii.md),
        side: BorderSide(color: hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CairnColors.primary,
        foregroundColor: CairnColors.onPrimary,
        disabledBackgroundColor: surfaceSoft,
        disabledForegroundColor: CairnColors.disabledInk,
        shape: buttonShape,
        // DESIGN.md padding 10x16; min height 48 honours the Android touch
        // target adaptation (docs/design.md #2).
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: const Size(0, 48),
        textStyle: textTheme.labelLarge?.copyWith(color: CairnColors.onPrimary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink),
        shape: buttonShape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        shape: buttonShape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: const Size(0, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CairnRadii.sm),
        borderSide: BorderSide(color: fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CairnRadii.sm),
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CairnRadii.sm),
        borderSide: const BorderSide(color: CairnColors.focus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CairnRadii.sm),
        borderSide: const BorderSide(color: CairnColors.error),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CairnRadii.md),
        side: BorderSide(color: hairline),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surfaceSoft,
      selectedIconTheme: const IconThemeData(color: CairnColors.onPrimary),
      unselectedIconTheme: IconThemeData(color: inkMuted),
      indicatorColor: CairnColors.primary,
      selectedLabelTextStyle:
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: textTheme.labelLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceSoft,
      indicatorColor: CairnColors.primary,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? CairnColors.onPrimary
              : inkMuted)),
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
    ),
  );
}

/// The Cairn wordmark — the ONLY place Oracle red (brand-mark) may appear.
class CairnWordmark extends StatelessWidget {
  const CairnWordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'CAIRN',
      style: TextStyle(
        fontFamily: CairnFonts.latin,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: CairnColors.brandMark,
      ),
    );
  }
}
