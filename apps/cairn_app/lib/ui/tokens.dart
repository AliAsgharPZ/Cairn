import 'package:flutter/material.dart';

/// Cairn design tokens — a 1:1 mapping of the Oracle `DESIGN.md` installed at
/// the repo root (see docs/design.md for the mapping table and the declared
/// Cairn adaptations). UI code must use these tokens; raw hex values outside
/// this file are a lint failure (tools/token_lint).
abstract final class CairnColors {
  // Action charcoal — the fill of every primary action.
  static const Color primary = Color(0xFF312D2A);
  static const Color primaryPressed = Color(0xFF47423E);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Oracle red — the wordmark, and ONLY the wordmark.
  static const Color brandMark = Color(0xFFC74634);

  static const Color ink = Color(0xFF161513);
  static const Color inkDeep = Color(0xFF211E1C);

  // The warm neutral ladder (light surfaces).
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color canvasSoft = Color(0xFFFBF9F8);
  static const Color canvasTint = Color(0xFFF5F4F2);
  static const Color canvasWarm = Color(0xFFF1EFED);
  static const Color hairline = Color(0xFFE4E1DD);
  static const Color divider = Color(0xFFE9E7E4);
  static const Color fieldBorder = Color(0xFFD4CFCA);

  static const Color link = Color(0xFF006B8F);
  static const Color accentGold = Color(0xFFF0CC71);
  static const Color accentGoldSoft = Color(0xFFF7E0A1);
  static const Color bandTeal = Color(0xFFD6E5E5);
  static const Color bandForest = Color(0xFF33553C);
  static const Color focus = Color(0xFF227E9E);
  static const Color error = Color(0xFFD63B25);
  static const Color disabledInk = Color(0xFFAEA8A2);

  // Dark theme (Cairn extension built from the dark end of the same ladder —
  // DESIGN.md describes a light system; see docs/design.md adaptation 3).
  static const Color darkCanvas = Color(0xFF161513); // ink
  static const Color darkCanvasSoft = Color(0xFF211E1C); // ink-deep
  static const Color darkCanvasTint = Color(0xFF2A2724);
  static const Color darkCanvasWarm = Color(0xFF35312D);
  static const Color darkHairline = Color(0xFF403C37);
  static const Color darkFieldBorder = Color(0xFF57524C);
  static const Color darkInk = Color(0xFFF5F4F2); // canvas-tint as text
  static const Color darkInkMuted = Color(0xFFCFC9C2);
}

/// Corner radii from DESIGN.md (`rounded` scale).
abstract final class CairnRadii {
  static const double none = 0;
  static const double xs = 4; // buttons
  static const double sm = 6; // inputs
  static const double md = 8; // cards, modals, toasts
  static const double lg = 12; // nav tiles
  static const double xl = 15; // content cards
}

/// Spacing ladder from DESIGN.md (`spacing` scale).
abstract final class CairnSpacing {
  static const double xs = 10;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double section = 48;
}

/// Font families (docs/fonts.md): Arad is primary for Persian (and the app
/// default), Inter is the Latin companion/fallback.
abstract final class CairnFonts {
  static const String persian = 'Arad';
  static const String persianVariable = 'AradVF';
  static const String persianDigits = 'AradFD';
  static const String latin = 'Inter';
  static const List<String> fallback = [latin];
}
