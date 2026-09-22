import 'package:flutter/material.dart';

abstract final class PrimeVestDesignSystem {
  static const backgroundDark = Color(0xFF1C1C1C);
  static const surfaceDark = Color(0xFF292522);
  static const primaryGold = Color(0xFFF8B425);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFA8A29E);
  static const positive = Color(0xFF4ADE80);
  static const negative = Color(0xFFFB7185);

  static const spacing8 = 8.0;
  static const spacing16 = 16.0;
  static const spacing24 = 24.0;
  static const radius = 16.0;
  static const buttonHeight = 54.0;

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: primaryGold,
          secondary: primaryGold,
          surface: surfaceDark,
        ),
        fontFamily: 'sans-serif',
        cardTheme: const CardThemeData(color: surfaceDark, elevation: 0),
        appBarTheme: const AppBarTheme(
            backgroundColor: backgroundDark, elevation: 0, centerTitle: false),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF211F1D),
          indicatorColor: primaryGold.withValues(alpha: .16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? primaryGold
                    : textMuted,
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? primaryGold
                    : textMuted,
              )),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceDark,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF34302C))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: primaryGold)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceDark,
          selectedColor: primaryGold.withValues(alpha: .20),
          disabledColor: surfaceDark,
          labelStyle: const TextStyle(color: textPrimary),
          secondaryLabelStyle:
              const TextStyle(color: primaryGold, fontWeight: FontWeight.w700),
          side: const BorderSide(color: Color(0xFF3A3531)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? primaryGold.withValues(alpha: .20)
                    : surfaceDark),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? primaryGold
                    : textMuted),
            side: const WidgetStatePropertyAll(
                BorderSide(color: Color(0xFF453A29))),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            foregroundColor: const Color(0xFF1A160E),
            minimumSize: const Size.fromHeight(buttonHeight),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
}
