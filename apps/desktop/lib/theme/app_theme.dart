// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Uygulama Teması
///
/// Dark Mode, Modern, Industrial tasarım dili.
/// Renk paleti: Koyu siyah zeminler, cyan/teal aksanlar,
/// turuncu uyarı tonları, metalik gri ara yüzeyler.

import 'package:flutter/material.dart';

// ============================================================
// Renk Paleti
// ============================================================

class AntaresColors {
  AntaresColors._();

  // Ana zemin renkleri
  static const Color background       = Color(0xFF0A0E14);
  static const Color surface          = Color(0xFF111820);
  static const Color surfaceLight     = Color(0xFF1A2230);
  static const Color surfaceElevated  = Color(0xFF212D3B);

  // Aksan renkleri
  static const Color primary          = Color(0xFF00E5CC);  // Cyan-teal
  static const Color primaryDim       = Color(0xFF007A6D);
  static const Color secondary        = Color(0xFFFF6B35);  // Turuncu
  static const Color secondaryDim     = Color(0xFF993F1F);

  // Durum renkleri
  static const Color success          = Color(0xFF00C853);
  static const Color warning          = Color(0xFFFFAB00);
  static const Color error            = Color(0xFFFF1744);
  static const Color info             = Color(0xFF448AFF);

  // Metin renkleri
  static const Color textPrimary      = Color(0xFFF0F4F8);
  static const Color textSecondary    = Color(0xFF8B9DC3);
  static const Color textDisabled     = Color(0xFF4A5568);

  // Kenarlık ve ayracı
  static const Color border           = Color(0xFF2A3545);
  static const Color divider          = Color(0xFF1E2A38);

  // Gradient'ler
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5CC), Color(0xFF00B4D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF111820), Color(0xFF0A0E14)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A2230), Color(0xFF151C28)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ============================================================
// Tema Yapılandırması
// ============================================================

class AntaresTheme {
  AntaresTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Renk şeması
      colorScheme: const ColorScheme.dark(
        primary: AntaresColors.primary,
        secondary: AntaresColors.secondary,
        surface: AntaresColors.surface,
        error: AntaresColors.error,
        onPrimary: AntaresColors.background,
        onSecondary: Colors.white,
        onSurface: AntaresColors.textPrimary,
        onError: Colors.white,
      ),

      // Zemin
      scaffoldBackgroundColor: AntaresColors.background,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: AntaresColors.textSecondary),
      ),

      // Kart
      cardTheme: CardThemeData(
        color: AntaresColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AntaresColors.border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Alt navigasyon
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AntaresColors.surface,
        selectedItemColor: AntaresColors.primary,
        unselectedItemColor: AntaresColors.textDisabled,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      // İlerleme göstergesi
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AntaresColors.primary,
        linearTrackColor: AntaresColors.surfaceLight,
      ),

      // Butonlar
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AntaresColors.primary,
          foregroundColor: AntaresColors.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AntaresColors.primary,
          side: const BorderSide(color: AntaresColors.primaryDim, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AntaresColors.divider,
        thickness: 1,
        space: 1,
      ),

      // İcon
      iconTheme: const IconThemeData(
        color: AntaresColors.textSecondary,
        size: 22,
      ),

      // Metin teması
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AntaresColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: AntaresColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: AntaresColors.textDisabled,
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: AntaresColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
        labelSmall: TextStyle(
          color: AntaresColors.textDisabled,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
