import 'package:flutter/material.dart';

/// "Midnight Ink" palette.
abstract final class Pal {
  static const background = Color(0xFF0E1116);
  static const surface = Color(0xFF171C24);
  static const raised = Color(0xFF222935);
  static const teal = Color(0xFF2EC4B6);
  static const coral = Color(0xFFFF6B6B);
  static const lavender = Color(0xFFA78BFA);
  static const sky = Color(0xFF60A5FA);
  static const paper = Color(0xFFE8ECF2);
  static const fog = Color(0xFF8A94A6);
  static const smoke = Color(0xFF2A3140);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Pal.teal,
    onPrimary: Pal.background,
    secondary: Pal.coral,
    onSecondary: Pal.background,
    surface: Pal.surface,
    onSurface: Pal.paper,
    surfaceContainerHighest: Pal.raised,
    onSurfaceVariant: Pal.fog,
    outline: Pal.smoke,
    outlineVariant: Pal.smoke,
    error: Pal.coral,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: Pal.background,
    appBarTheme: const AppBarTheme(backgroundColor: Pal.background, foregroundColor: Pal.paper, elevation: 0),
    cardTheme: const CardThemeData(color: Pal.surface, margin: EdgeInsets.zero),
    dividerTheme: const DividerThemeData(color: Pal.smoke, space: 1),
    dialogTheme: const DialogThemeData(backgroundColor: Pal.raised),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Pal.raised),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Pal.raised,
      contentTextStyle: TextStyle(color: Pal.paper),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Pal.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}
