import 'package:flutter/material.dart';

/// Claude Remote color palette.
abstract class AppColors {
  // Brand
  static const primary = Color(0xFFD97706); // warm amber
  static const primaryDark = Color(0xFFB45309);

  // Status
  static const active = Color(0xFF22C55E); // green
  static const waiting = Color(0xFFEAB308); // yellow
  static const completed = Color(0xFF94A3B8); // slate
  static const error = Color(0xFFEF4444); // red

  // Connection
  static const connected = Color(0xFF22C55E);
  static const reconnecting = Color(0xFFEAB308);
  static const disconnected = Color(0xFFEF4444);

  // Surface
  static const darkBg = Color(0xFF0F172A); // slate-900
  static const darkSurface = Color(0xFF1E293B); // slate-800
  static const darkCard = Color(0xFF334155); // slate-700
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: AppColors.primary,
    scaffoldBackgroundColor: AppColors.darkBg,
    cardTheme: const CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBg,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
  );
}

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: AppColors.primary,
    cardTheme: const CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
  );
}
