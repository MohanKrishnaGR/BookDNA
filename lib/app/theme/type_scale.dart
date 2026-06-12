import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Figtree type scale matching the prototype's `theme.js` exactly
/// (sizes, weights, letter spacing, line heights).
TextTheme buildTypeScale(ColorScheme scheme) {
  TextStyle s(double size, FontWeight w, double height, [double spacing = 0]) {
    return GoogleFonts.figtree(
      fontSize: size,
      fontWeight: w,
      height: height / size,
      letterSpacing: spacing,
      color: scheme.onSurface,
    );
  }

  return TextTheme(
    displayLarge: s(57, FontWeight.w400, 64, -0.25),
    displayMedium: s(45, FontWeight.w400, 52),
    displaySmall: s(36, FontWeight.w400, 44),
    headlineLarge: s(32, FontWeight.w500, 40),
    headlineMedium: s(28, FontWeight.w500, 36),
    headlineSmall: s(24, FontWeight.w500, 32),
    titleLarge: s(22, FontWeight.w500, 28),
    titleMedium: s(16, FontWeight.w600, 24, 0.1),
    titleSmall: s(14, FontWeight.w600, 20, 0.1),
    bodyLarge: s(16, FontWeight.w400, 24, 0.3),
    bodyMedium: s(14, FontWeight.w400, 20, 0.2),
    bodySmall: s(12, FontWeight.w400, 16, 0.3),
    labelLarge: s(14, FontWeight.w600, 20, 0.1),
    labelMedium: s(12, FontWeight.w600, 16, 0.4),
    labelSmall: s(11, FontWeight.w600, 16, 0.4),
  );
}
