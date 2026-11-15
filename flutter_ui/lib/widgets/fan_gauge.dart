import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class FanGauge extends StatelessWidget {
  const FanGauge({
    super.key,
    required this.rpm,
    required this.minRpm,
    required this.maxRpm,
    required this.name,
    this.accent = AppColors.accent,
    this.size = 300,
  });

  final double rpm;
  final double minRpm;
  final double maxRpm;
  final String name;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fraction = _fraction(rpm);
    final color = fraction > 0.92
        ? AppColors.amber
        : fraction > 0.75
            ? Color.lerp(accent, AppColors.amber, 0.45)!
            : accent;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          value: rpm,
          minRpm: minRpm,
          maxRpm: maxRpm,
          accent: color,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.4,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                rpm.isFinite ? rpm.round().toString() : '—',
                style: TextStyle(
                  fontSize: 54,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'RPM',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.8),
                  ),
                ),
                child: Text(
                  '${(fraction * 100).round()}%  ·  ${minRpm.round()}–${maxRpm.round()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  double _fraction(double value) {
    final span = maxRpm - minRpm;
    if (!value.isFinite || !span.isFinite || span <= 0) return 0;
    return ((value - minRpm) / span).clamp(0.0, 1.0).toDouble();
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.minRpm,
    required this.maxRpm,
    required this.accent,
  });

  final double value;
  final double minRpm;
  final double maxRpm;
  final Color accent;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 22;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final fraction = _fraction();

    // Track.
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.055),
    );

    // Ticks.
    final tickPaint = Paint()..strokeWidth = 2;
    const tickCount = 36;
    for (var i = 0; i < tickCount; i++) {
      final t = i / (tickCount - 1);
      final angle = _start + _sweep * t;
      final active = t <= fraction;
      tickPaint.color = active
          ? accent.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.10);
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 28);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 16);
      canvas.drawLine(inner, outer, tickPaint);
    }

    if (fraction > 0.001) {
      // Value arc.
      canvas.drawArc(
        rect,
        _start,
        _sweep * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: _start,
            endAngle: _start + _sweep,
            colors: [
              accent.withValues(alpha: 0.55),
              accent,
              Color.lerp(accent, AppColors.accent2, 0.45)!,
            ],
          ).createShader(rect),
      );

      // End dot.
      final angle = _start + _sweep * fraction;
      final dot = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(dot, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        dot,
        3.2,
        Paint()..color = accent,
      );
    }
  }

  double _fraction() {
    final span = maxRpm - minRpm;
    if (!value.isFinite || !span.isFinite || span <= 0) return 0;
    return ((value - minRpm) / span).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.minRpm != minRpm ||
      old.maxRpm != maxRpm ||
      old.accent != accent;
}

