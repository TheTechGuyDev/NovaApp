import 'package:flutter/material.dart';

/// NOVA brand palette. Green accents stay the same in both modes;
/// surfaces and text flip between dark and light.
class AppColors {
  AppColors._();

  // Brand greens
  static const Color primary = Color(0xFF2ECC71);
  static const Color primaryDeep = Color(0xFF16A34A);
  static const Color neon = Color(0xFF4ADE80);
  static const Color forest = Color(0xFF0E3B1F);
  static const Color moss = Color(0xFF1F6B3A);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // Dark mode
  static const Color darkBg = Color(0xFF070908);
  static const Color darkSurface = Color(0xFF111513);
  static const Color darkSurfaceHigh = Color(0xFF181D1A);
  static const Color darkBorder = Color(0xFF242B27);
  static const Color darkText = Color(0xFFF5F7F6);
  static const Color darkTextMuted = Color(0xFF8E9993);

  // Light mode
  static const Color lightBg = Color(0xFFF3F6F4);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFEAF0EC);
  static const Color lightBorder = Color(0xFFDCE4DF);
  static const Color lightText = Color(0xFF0B1410);
  static const Color lightTextMuted = Color(0xFF5F6B65);

  static const LinearGradient balanceCardDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C7A41), Color(0xFF0D2A18), Color(0xFF0A0F0C)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient balanceCardLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF15803D), Color(0xFF0E3B1F)],
    stops: [0.0, 0.6, 1.0],
  );

  static const LinearGradient headerGlowDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B6B3A), Color(0xFF070908)],
  );

  static const LinearGradient headerGlowLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFBBF7D0), Color(0xFFF3F6F4)],
  );
}
