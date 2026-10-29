import 'package:flutter/material.dart';

/// "Midnight Gold" palette, shared with Save This Spot (Arwee's navy, gold
/// and ivory). Gold marks primary actions; blue marks voice; coral means the
/// microphone is live.
abstract final class Pal {
  static const background = Color(0xFF0B1426);
  static const surface = Color(0xFF13203A);
  static const raised = Color(0xFF1A2A4A);
  static const gold = Color(0xFFD4AF5F);
  static const voice = Color(0xFF2FA8E8);
  static const coral = Color(0xFFFF6B6B);
  static const paper = Color(0xFFF5EFE3);
  static const fog = Color(0xFF9AA7BF);
  static const muted = Color(0xFF6B7894);
  static const smoke = Color(0xFF25365A);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Pal.gold,
    onPrimary: Pal.background,
    secondary: Pal.voice,
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
    appBarTheme: const AppBarTheme(
      // Title style set below so it keeps the theme's font.
      backgroundColor: Pal.background,
      foregroundColor: Pal.paper,
      elevation: 0,
      scrolledUnderElevation: 0,
    ).copyWith(
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: Pal.paper,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: const CardThemeData(color: Pal.surface, margin: EdgeInsets.zero),
    dividerTheme: const DividerThemeData(color: Pal.smoke, space: 1),
    dialogTheme: const DialogThemeData(backgroundColor: Pal.raised),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Pal.raised),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Pal.gold,
      foregroundColor: Pal.background,
    ),
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
