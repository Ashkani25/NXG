import 'package:flutter/material.dart';

/// NEXORA design tokens (P10/P11).
class NxColors {
  NxColors._();
  static const navy = Color(0xFF0A0F2C);
  static const navyDeep = Color(0xFF050818);
  static const navySoft = Color(0xFF141B45);
  static const electricBlue = Color(0xFF00C2FF);
  static const violet = Color(0xFF7B3FF2);
  static const iceWhite = Color(0xFFEAF6FF);
  static const turquoise = Color(0xFF2EE6D6);
  static const gold = Color(0xFFFFC857);
  static const pink = Color(0xFFFF4FA3);
  static const danger = Color(0xFFFF5A6E);
  static const success = Color(0xFF3DDC97);
  static const glass = Color(0x22FFFFFF);
  static const glassBorder = Color(0x44FFFFFF);
  static const textDim = Color(0xB3EAF6FF);
}

/// Per-world palette: each world has its own identity under one design language.
class WorldPalette {
  const WorldPalette(this.primary, this.secondary, this.background, {this.light = false});
  final Color primary;
  final Color secondary;
  final List<Color> background;
  final bool light;

  static const hub = WorldPalette(NxColors.electricBlue, NxColors.violet,
      [Color(0xFF050818), Color(0xFF0E1640), Color(0xFF1B0F3F)]);
  static const nova = WorldPalette(Color(0xFFFF6FB5), Color(0xFFFFC857),
      [Color(0xFF1A0B2E), Color(0xFF3B1450), Color(0xFF5A1E4F)]);
  static const orbit = WorldPalette(NxColors.turquoise, NxColors.electricBlue,
      [Color(0xFF031A26), Color(0xFF06324A), Color(0xFF0A2A3F)]);
  static const arcade = WorldPalette(Color(0xFFFFB020), Color(0xFFFF4F6E),
      [Color(0xFF12051F), Color(0xFF2A0B3A), Color(0xFF3A0F2A)]);
  static const oracle = WorldPalette(Color(0xFF9D7BFF), NxColors.turquoise,
      [Color(0xFF0B0820), Color(0xFF1A1250), Color(0xFF0E2850)]);
  static const personal = WorldPalette(Color(0xFF7CF5D0), Color(0xFFB79CFF),
      [Color(0xFFEFF6FF), Color(0xFFDDE9FF), Color(0xFFEDE3FF)], light: true);
  static const social = WorldPalette(Color(0xFF4FD1FF), Color(0xFF7CFF8A),
      [Color(0xFF04141F), Color(0xFF0B2B33), Color(0xFF0E1F3A)]);
  static const exchange = WorldPalette(NxColors.gold, Color(0xFFFFE6A8),
      [Color(0xFF0D0B05), Color(0xFF2A2210), Color(0xFF1A1530)]);
}

class NxSpace {
  NxSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class NxRadius {
  NxRadius._();
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
}

class NxMotion {
  NxMotion._();
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;
}

ThemeData buildNxTheme() {
  const scheme = ColorScheme.dark(
    primary: NxColors.electricBlue,
    secondary: NxColors.violet,
    tertiary: NxColors.turquoise,
    surface: NxColors.navySoft,
    error: NxColors.danger,
    onPrimary: NxColors.navyDeep,
    onSurface: NxColors.iceWhite,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: NxColors.navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: NxColors.iceWhite,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NxColors.iceWhite),
    ),
    textTheme: base.textTheme.apply(bodyColor: NxColors.iceWhite, displayColor: NxColors.iceWhite),
    cardTheme: CardTheme(
      color: NxColors.glass,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        side: const BorderSide(color: NxColors.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: const BorderSide(color: NxColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: const BorderSide(color: NxColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: const BorderSide(color: NxColors.electricBlue, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NxColors.electricBlue,
        foregroundColor: NxColors.navyDeep,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.md)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: NxColors.navySoft,
      contentTextStyle: TextStyle(color: NxColors.iceWhite),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: NxColors.navySoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.lg)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NxColors.navySoft,
      showDragHandle: true,
    ),
  );
}
