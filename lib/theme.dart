import 'package:flutter/material.dart';

/// Palette: gold / brown
class AppColors {
  static const brown900 = Color(0xFF5A4A0D);
  static const brown700 = Color(0xFF7A5E12);
  static const gold700 = Color(0xFFA67917);
  static const gold500 = Color(0xFFCC961F);
  static const gold400 = Color(0xFFE8B84A);
  static const gold200 = Color(0xFFF3D789);
  static const cream = Color(0xFFFFF3D8);
}

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.cream,
    colorScheme: const ColorScheme.light(
      primary: AppColors.gold700,
      onPrimary: AppColors.cream,
      secondary: AppColors.brown700,
      onSecondary: AppColors.cream,
      surface: AppColors.cream,
      onSurface: AppColors.brown900,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.brown900,
      foregroundColor: AppColors.cream,
      elevation: 0,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.brown900,
      contentTextStyle: TextStyle(color: AppColors.cream),
      behavior: SnackBarBehavior.floating,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.gold700),
    ),
  );
}