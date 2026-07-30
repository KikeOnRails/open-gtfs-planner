import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colours
  static const Color primary = Color(0xFF00AF8C);
  static const Color primaryDark = Color(0xFF007E65);
  static const Color secondary = Color(0xFF39B29D);
  static const Color accent = Color(0xFF78C89A);
  static const Color surface = Color(0xFF1E2128);
  static const Color surfaceVariant = Color(0xFF252830);
  static const Color background = Color(0xFF14161A);
  static const Color onSurface = Color(0xFFE8EAED);
  static const Color onSurfaceVariant = Color(0xFFAABBC4);
  static const Color mapOverlay = Color(0xFF1A1D22);

  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: surface,
        background: background,
        primary: primary,
        secondary: secondary,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        bodySmall: GoogleFonts.inter(color: onSurfaceVariant),
        bodyMedium: GoogleFonts.inter(color: onSurface),
        bodyLarge: GoogleFonts.inter(color: onSurface),
        titleSmall: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.bold),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2E3340), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252830),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3E4450)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3E4450)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: const TextStyle(color: Color(0xFF5A6370)),
        labelStyle: const TextStyle(color: onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2E3340),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: onSurfaceVariant,
        textColor: onSurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        dense: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF252830),
        selectedColor: primary.withOpacity(0.3),
        labelStyle: const TextStyle(color: onSurface, fontSize: 12),
        side: const BorderSide(color: Color(0xFF3E4450)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF3E4450),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: onSurface, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFF3E4450)),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),
    );
  }
}

// Utility to convert hex color string to Color
Color hexToColor(String? hex, {Color fallback = AppTheme.primary}) {
  if (hex == null || hex.isEmpty) return fallback;
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    return Color(int.parse('FF$cleaned', radix: 16));
  }
  return fallback;
}
