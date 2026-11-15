import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFF0B100E);
  static const bg2 = Color(0xFF121815);
  static const card = Color(0xFF1A2320);
  static const card2 = Color(0xFF232E29);
  static const border = Color(0xFF2F3D36);
  static const text = Color(0xFFF1F5EC);
  static const muted = Color(0xFF9BAE9F);
  static const accent = Color(0xFFB7E88A);
  static const accent2 = Color(0xFF84C7BB);
  static const green = Color(0xFFA6DE9C);
  static const amber = Color(0xFFF0C77A);
  static const red = Color(0xFFFF9A8D);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF26332C), Color(0xFF161E1B)],
  );

  static const tileGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF202A25), Color(0xFF171F1C)],
  );
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
    onPrimary: Color(0xFF16210F),
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
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 6,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.border,
      thumbColor: Colors.white,
      overlayColor: AppColors.accent.withValues(alpha: 0.15),
      valueIndicatorColor: AppColors.card2,
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
