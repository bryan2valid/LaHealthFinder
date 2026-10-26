import 'package:flutter/material.dart';

/// Design tokens for the LA Clinic Finder "clinical-futuristic" theme.
/// Dark, minimal, high-contrast — legible at a glance for someone
/// stressed or in a hurry, with color used purely as information
/// (not decoration).
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF131922);
  static const Color surfaceRaised = Color(0xFF1A2230);
  static const Color border = Color(0xFF232B38);

  // Primary interactive / "live data" accent.
  static const Color accent = Color(0xFF29F1C3);
  static const Color accentDim = Color(0xFF1B7C6B);

  // Semantic tag colors — used consistently across chips, tags, and
  // map markers so color always means the same thing.
  static const Color critical = Color(0xFFFF5470); // ER / trauma
  static const Color coverage = Color(0xFF7C8CFF); // Medicaid / insurance / VA
  static const Color wellness = Color(0xFF29F1C3); // mental health / telehealth

  static const Color textPrimary = Color(0xFFEAF0F6);
  static const Color textSecondary = Color(0xFF8C97A8);
  static const Color textFaint = Color(0xFF5B6472);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.coverage,
        error: AppColors.critical,
        surface: AppColors.surface,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            titleLarge: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
            titleMedium: const TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              color: AppColors.textPrimary,
              height: 1.35,
            ),
            bodySmall: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.3,
            ),
            labelSmall: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
      splashColor: AppColors.accent.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
    );
  }
}

/// A small colored "tag" pill — the visual language for facility
/// attributes (ER, Medicaid, Mental Health, etc). Same shape everywhere,
/// color is the only thing that changes meaning.
class TagPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const TagPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
