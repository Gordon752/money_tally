part of '../main.dart';

class AppTheme {
  static const ink = Color(0xFF17211F);
  static const muted = Color(0xFF61706C);
  static const page = Color(0xFFF5F7F3);
  static const panel = Color(0xFFFFFFFF);
  static const line = Color(0xFFD8E1DD);
  static const accent = Color(0xFF1F6F68);
  static const accentStrong = Color(0xFF15514C);
  static const gold = Color(0xFFD69D2F);
  static const rose = Color(0xFFC8585B);
  static const blue = Color(0xFF5378BD);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: panel,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      cardTheme: const CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: page,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: accent.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
