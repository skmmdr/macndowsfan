import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFF080B11);
  static const bg2 = Color(0xFF0D131D);
  static const card = Color(0xFF131A25);
  static const card2 = Color(0xFF18202D);
  static const border = Color(0xFF222C3C);
  static const text = Color(0xFFE9EEF7);
  static const muted = Color(0xFF8B97A9);
  static const accent = Color(0xFF5BC8FF);
  static const accent2 = Color(0xFF8B7CFF);
  static const green = Color(0xFF4ADE80);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
}

Color tempColor(double? value) {
  if (value == null) return AppColors.muted;
  if (value >= 78) return AppColors.red;
  if (value >= 62) return AppColors.amber;
  return AppColors.green;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF04121A),
    secondary: AppColors.accent2,
    onSecondary: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.text,
    error: AppColors.red,
    onError: Colors.white,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: AppColors.card2,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Segoe UI',
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerColor: AppColors.border,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2836),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 6,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: const Color(0xFF223041),
      thumbColor: Colors.white,
      overlayColor: AppColors.accent.withValues(alpha: 0.15),
      valueIndicatorColor: const Color(0xFF1E2836),
      valueIndicatorTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      showValueIndicator: ShowValueIndicator.onlyForDiscrete,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.muted,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.border,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent.withValues(alpha: 0.14),
        foregroundColor: AppColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        AppColors.muted.withValues(alpha: 0.35),
      ),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}

TextStyle monoStyle({
  double size = 12,
  Color color = AppColors.muted,
  FontWeight weight = FontWeight.w500,
}) =>
    TextStyle(
      fontFamily: 'Consolas',
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: 0.2,
    );
