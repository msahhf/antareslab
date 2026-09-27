// SPDX-License-Identifier: Apache-2.0

/// Antares Studio - Sci-Fi Archaeology Dashboard Theme
/// Complete Material 3 Dark Theme with glassmorphism accents

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AntaresColors {
  // Deep Space Backgrounds
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceVariant = Color(0xFF1E293B);
  static const Color surfaceElevated = Color(0xFF1A2234);
  
  // Neon Accent Palette
  static const Color cyan = Color(0xFF00F0FF);
  static const Color cyanDim = Color(0xFF00B8C4);
  static const Color amber = Color(0xFFFFB800);
  static const Color amberDim = Color(0xFFCC9300);
  static const Color emerald = Color(0xFF00FF88);
  static const Color emeraldDim = Color(0xFF00CC6A);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color rose = Color(0xFFF43F5E);
  
  // Semantic Colors
  static const Color primary = cyan;
  static const Color secondary = amber;
  static const Color success = emerald;
  static const Color warning = amber;
  static const Color error = rose;
  static const Color info = violet;
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF64748B);
  static const Color textInverse = Color(0xFF0F172A);
  
  // Borders & Dividers
  static const Color border = Color(0xFF334155);
  static const Color borderHighlight = Color(0xFF475569);
  
  // Gradients
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x20FFFFFF),
      Color(0x10FFFFFF),
    ],
  );
  
  static const LinearGradient cyanGlow = LinearGradient(
    colors: [cyan, Color(0xFF00D4E0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient amberGlow = LinearGradient(
    colors: [amber, Color(0xFFE6A600)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AntaresTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AntaresColors.cyan,
        onPrimary: AntaresColors.textInverse,
        secondary: AntaresColors.amber,
        onSecondary: AntaresColors.textInverse,
        surface: AntaresColors.surface,
        onSurface: AntaresColors.textPrimary,
        surfaceContainerHighest: AntaresColors.surfaceVariant,
        onSurfaceVariant: AntaresColors.textSecondary,
        error: AntaresColors.rose,
        onError: Colors.white,
        outline: AntaresColors.border,
        shadow: Colors.black54,
      ),
      scaffoldBackgroundColor: AntaresColors.background,
      
      // Typography - Inter for reading, system for headers
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w300,
          color: AntaresColors.textPrimary,
          letterSpacing: -1,
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AntaresColors.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AntaresColors.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AntaresColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AntaresColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AntaresColors.textPrimary,
          letterSpacing: 0.5,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AntaresColors.textSecondary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AntaresColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AntaresColors.textPrimary,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AntaresColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
      
      // Card Theme
      cardTheme: const CardThemeData(
        color: AntaresColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AntaresColors.border, width: 1),
        ),
      ),
      
      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AntaresColors.cyan,
          foregroundColor: AntaresColors.textInverse,
          elevation: 0,
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
      
      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AntaresColors.cyan,
          side: const BorderSide(color: AntaresColors.cyan, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      // Icon Button
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AntaresColors.textSecondary,
          backgroundColor: Colors.transparent,
          hoverColor: AntaresColors.cyan.withOpacity(0.1),
          highlightColor: AntaresColors.cyan.withOpacity(0.2),
        ),
      ),
      
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: AntaresColors.cyan,
        inactiveTrackColor: AntaresColors.border,
        thumbColor: AntaresColors.cyan,
        overlayColor: AntaresColors.cyan.withOpacity(0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      
      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AntaresColors.cyan;
          }
          return AntaresColors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AntaresColors.cyan.withOpacity(0.3);
          }
          return AntaresColors.border;
        }),
      ),
      
      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AntaresColors.surface,
        selectedItemColor: AntaresColors.cyan,
        unselectedItemColor: AntaresColors.textDisabled,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      
      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AntaresColors.textPrimary,
        ),
      ),
    );
  }
  
  // Glassmorphism Decoration
  static BoxDecoration glassDecoration({double radius = 16}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: AntaresColors.surface.withOpacity(0.6),
      border: Border.all(
        color: AntaresColors.border.withOpacity(0.5),
        width: 1,
      ),
      gradient: AntaresColors.glassGradient,
    );
  }
  
  // Neon Glow Box Shadow
  static List<BoxShadow> neonGlow(Color color, {double intensity = 0.5}) {
    return [
      BoxShadow(
        color: color.withOpacity(intensity * 0.6),
        blurRadius: 20,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: color.withOpacity(intensity * 0.3),
        blurRadius: 40,
        spreadRadius: -8,
      ),
    ];
  }
  
  // Pulsing Animation
  static AnimationController createPulseController(TickerProvider vsync) {
    return AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }
}

// System UI Overlay
void setupSystemUI() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AntaresColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
}
