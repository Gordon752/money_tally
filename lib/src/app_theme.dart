part of '../main.dart';

class AppTheme {
  static const ink = Color(0xFF17211F);
  static const muted = Color(0xFF61706C);
  static const page = Color(0xFFF0F4EF);
  static const panel = Color(0xFFFFFFFF);
  static const line = Color(0xFFD8E1DD);
  static const accent = Color(0xFF1F6F68);
  static const accentStrong = Color(0xFF15514C);
  static const gold = Color(0xFFD69D2F);
  static const rose = Color(0xFFC8585B);
  static const blue = Color(0xFF5378BD);

  static ThemeData light() {
    return _theme(Brightness.light);
  }

  static ThemeData dark() {
    return _theme(Brightness.dark);
  }

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: isDark ? AppColors.panelDark : panel,
    );

    return AppThemeBuilder.theme(brightness).copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.pageDark : page,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.panelDark : panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: isDark ? AppColors.lineDark : line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.panelDark : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? AppColors.lineDark : line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? AppColors.pageDark : page,
        selectedIconTheme: const IconThemeData(color: accent),
        selectedLabelTextStyle: const TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.panelDark : Colors.white,
        indicatorColor: accent.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: isDark ? 0.46 : 0.38)
              : null,
        ),
      ),
    );
  }
}

ThemeMode themeModeFor(AppearanceMode mode) {
  return switch (mode) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };
}
