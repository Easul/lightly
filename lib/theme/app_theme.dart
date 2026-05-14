import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF63B746);
  static const Color primaryLight = Color(0xFFDDEBD6);
  static const Color accent = Color(0xFFEAF4E4);
  static const Color scaffoldBackground = Color(0xFFF7F9F5);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color brandHeader = Color(0xFFF0F7EC);
  static const Color iconTint = Color(0xFF8DA483);
}

class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );

    final colorScheme = base.copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      tertiary: const Color(0xFF8EBF7A),
      surface: AppColors.scaffoldBackground,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: AppColors.cardBackground,
      surfaceContainerHigh: const Color(0xFFF3F7EE),
      surfaceContainerLow: const Color(0xFFF9FBF7),
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.textPrimary,
      secondaryContainer: AppColors.accent,
      onSecondaryContainer: AppColors.textPrimary,
      outlineVariant: AppColors.divider,
      outline: const Color(0xFFC9D4C5),
      shadow: Colors.black,
      error: const Color(0xFFC75A5A),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9E5E5),
      onErrorContainer: const Color(0xFF7A2F2F),
    );

    final baseText = Typography.material2021().black;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.scaffoldBackground,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: AppColors.textPrimary),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          height: 1.35,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          height: 1.35,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
        titleTextStyle: baseText.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBackground,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.iconTint,
        suffixIconColor: AppColors.iconTint,
        border: _inputBorder(AppColors.divider),
        enabledBorder: _inputBorder(AppColors.divider),
        focusedBorder: _inputBorder(AppColors.primary),
        errorBorder: _inputBorder(colorScheme.error),
        focusedErrorBorder: _inputBorder(colorScheme.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 54),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 54),
          backgroundColor: AppColors.cardBackground,
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: const StadiumBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, 56),
          backgroundColor: AppColors.cardBackground,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        iconColor: AppColors.iconTint,
        textColor: AppColors.textPrimary,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
      iconTheme: const IconThemeData(color: AppColors.iconTint, size: 22),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        dividerColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryLight;
          }
          return const Color(0xFFD7DDD3);
        }),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: color, width: 1.1),
    );
  }

  static List<BoxShadow> softShadow([double opacity = 0.03]) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
