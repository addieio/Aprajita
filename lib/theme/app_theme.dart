import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Ultra-minimalist luxury dark palette
  static const Color bgDark = Color(0xFF0C0D12);
  static const Color surfaceDark = Color(0xFF13151D);
  static const Color cardDark = Color(0xFF171A24);
  static const Color cardElevated = Color(0xFF1E2230);
  static const Color borderSubtle = Color(0xFF262B3A);

  // Status & Minimalist Accents
  static const Color crimson = Color(0xFFE53935);
  static const Color crimsonGlow = Color(0xFFFF5252);
  static const Color crimsonDark = Color(0xFF881313);
  static const Color rose = Color(0xFFF43F5E);
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color indigo = Color(0xFF6366F1);

  // Typography Palette
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    final fontName = GoogleFonts.inter().fontFamily;

    final styledTextTheme = baseTextTheme.copyWith(
      headlineLarge: TextStyle(
        fontFamily: fontName,
        color: textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 26,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontName,
        color: textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontFamily: fontName,
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        letterSpacing: 0.2,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontName,
        color: textPrimary,
        fontSize: 14,
        letterSpacing: 0.1,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontName,
        color: textSecondary,
        fontSize: 12.5,
        letterSpacing: 0.1,
      ),
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: crimson,
      colorScheme: const ColorScheme.dark(
        primary: crimson,
        secondary: rose,
        surface: surfaceDark,
        error: crimson,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: styledTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontName,
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: crimson,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
