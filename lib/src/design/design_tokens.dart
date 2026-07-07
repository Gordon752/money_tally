import 'package:flutter/material.dart';

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadii {
  static const double card = 8;
  static const double control = 8;
  static const double pill = 999;
}

class AppColors {
  static const Color ink = Color(0xFF17211F);
  static const Color muted = Color(0xFF61706C);
  static const Color pageLight = Color(0xFFF5F7F3);
  static const Color pageDark = Color(0xFF101614);
  static const Color panelLight = Color(0xFFFFFFFF);
  static const Color panelDark = Color(0xFF18211E);
  static const Color lineLight = Color(0xFFD8E1DD);
  static const Color lineDark = Color(0xFF2F3A36);
  static const Color accent = Color(0xFF1F6F68);
  static const Color accentStrong = Color(0xFF15514C);
  static const Color warning = Color(0xFFD69D2F);
  static const Color danger = Color(0xFFC8585B);
  static const Color info = Color(0xFF5378BD);
}

class AppTextStyles {
  static const FontFeature tabularFigures = FontFeature.tabularFigures();

  static TextStyle money(
    BuildContext context, {
    double? fontSize,
    FontWeight fontWeight = FontWeight.w800,
    Color? color,
  }) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFeatures: const [tabularFigures],
      letterSpacing: 0,
    );
  }
}

class AppThemeBuilder {
  static ThemeData theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
      surface: isDark ? AppColors.panelDark : AppColors.panelLight,
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark
          ? AppColors.pageDark
          : AppColors.pageLight,
      useMaterial3: true,
      fontFamily: null,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.panelDark : AppColors.panelLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: isDark ? AppColors.lineDark : AppColors.lineLight,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.panelDark : AppColors.panelLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: isDark ? AppColors.lineDark : AppColors.lineLight,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
    );
  }
}
