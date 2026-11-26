import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CinePulse India Design Tokens derived from Stitch Design System
/// (`assets/10933976885137237375`) and `DESIGN.md`.
class CinePulseColors {
  const CinePulseColors._();

  // Dark Cinema Palette (Default)
  static const Color darkBackground = Color(0xFF0B0D12);
  static const Color darkSurfaceLowest = Color(0xFF080A0E);
  static const Color darkSurfaceLow = Color(0xFF12151E);
  static const Color darkSurfaceCard = Color(0xFF171B26);
  static const Color darkSurfaceHigh = Color(0xFF1F2433);
  static const Color darkBorder = Color(0xFF262C3D);
  static const Color darkTextPrimary = Color(0xFFF1F3F8);
  static const Color darkTextSecondary = Color(0xFF8B95A8);

  // Light Mode Palette
  static const Color lightBackground = Color(0xFFF6F5F0);
  static const Color lightSurfaceCard = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFEFEDE6);
  static const Color lightBorder = Color(0xFFE0DDD3);
  static const Color lightTextPrimary = Color(0xFF14171F);
  static const Color lightTextSecondary = Color(0xFF5D6677);

  // Single Primary Accent (Burnished Marquee Gold)
  static const Color goldDark = Color(0xFFD4A853);
  static const Color goldLight = Color(0xFFA67C2E);
  static const Color goldContainerDark = Color(0xFF2D2412);
  static const Color goldOnContainerDark = Color(0xFFF2D28B);

  // Semantic Data Integrity & Publishing Status Colors
  static const Color emerald = Color(0xFF2EC27E);
  static const Color amber = Color(0xFFE5A00D);
  static const Color crimson = Color(0xFFE05252);
  static const Color slate = Color(0xFF8B95A8);
}

class CinePulseTheme {
  const CinePulseTheme._();

  static TextStyle monoStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: CinePulseColors.darkTextPrimary,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: CinePulseColors.darkTextPrimary,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: CinePulseColors.darkTextPrimary,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: CinePulseColors.darkTextPrimary,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14,
        color: CinePulseColors.darkTextPrimary,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 12,
        color: CinePulseColors.darkTextSecondary,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: CinePulseColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: CinePulseColors.goldDark,
        onPrimary: Color(0xFF1C1404),
        primaryContainer: CinePulseColors.goldContainerDark,
        onPrimaryContainer: CinePulseColors.goldOnContainerDark,
        secondary: CinePulseColors.slate,
        surface: CinePulseColors.darkSurfaceCard,
        onSurface: CinePulseColors.darkTextPrimary,
        error: CinePulseColors.crimson,
        outline: CinePulseColors.darkBorder,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: CinePulseColors.darkBackground,
        foregroundColor: CinePulseColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardTheme(
        color: CinePulseColors.darkSurfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: CinePulseColors.darkBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CinePulseColors.darkSurfaceLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: CinePulseColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: CinePulseColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: CinePulseColors.goldDark, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CinePulseColors.goldDark,
          foregroundColor: const Color(0xFF1C1404),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 46),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CinePulseColors.darkTextPrimary,
          side: const BorderSide(color: CinePulseColors.darkBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 44),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CinePulseColors.darkSurfaceLow,
        indicatorColor: CinePulseColors.goldContainerDark,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active
                ? CinePulseColors.goldDark
                : CinePulseColors.darkTextSecondary,
          );
        }),
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: CinePulseColors.lightTextPrimary,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: CinePulseColors.lightTextPrimary,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: CinePulseColors.lightTextPrimary,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: CinePulseColors.lightTextPrimary,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14,
        color: CinePulseColors.lightTextPrimary,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 12,
        color: CinePulseColors.lightTextSecondary,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: CinePulseColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: CinePulseColors.goldLight,
        onPrimary: Colors.white,
        secondary: CinePulseColors.lightTextSecondary,
        surface: CinePulseColors.lightSurfaceCard,
        onSurface: CinePulseColors.lightTextPrimary,
        error: CinePulseColors.crimson,
        outline: CinePulseColors.lightBorder,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: CinePulseColors.lightBackground,
        foregroundColor: CinePulseColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardTheme(
        color: CinePulseColors.lightSurfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: CinePulseColors.lightBorder, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CinePulseColors.goldLight,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 46),
        ),
      ),
    );
  }
}
