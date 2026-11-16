import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final text = isDark ? AppColors.darkText : AppColors.lightText;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final scheme = ColorScheme(
      brightness: b,
      primary: isDark ? AppColors.primary : AppColors.primaryDeep,
      onPrimary: Colors.white,
      secondary: AppColors.neon,
      onSecondary: AppColors.lightText,
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest:
          isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
      outline: border,
      onSurfaceVariant: muted,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = base.textTheme.apply(
      bodyColor: text,
      displayColor: text,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: text,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      dividerColor: border,
      tabBarTheme: TabBarThemeData(
        dividerColor: border,
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: muted,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
