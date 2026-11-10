import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class FanCurve extends StatelessWidget {
  const FanCurve({
    super.key,
    required this.start,
    required this.max,
    required this.minRpm,
    required this.maxRpm,
    required this.currentTemp,
    this.accent = AppColors.accent,
  });

  final double start;
  final double max;
  final double minRpm;
  final double maxRpm;
  final double? currentTemp;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      width: double.infinity,
      child: CustomPaint(
        painter: _CurvePainter(
          start: start,
          max: max,
          minRpm: minRpm,
          maxRpm: maxRpm,
          currentTemp: currentTemp,
          accent: accent,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.start,
    required this.max,
    required this.minRpm,
    required this.maxRpm,
    required this.currentTemp,
    required this.accent,
  });

  final double start;
  final double max;
  final double minRpm;
  final double maxRpm;
  final double? currentTemp;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final plot = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    final lo = start - 10;
    final hi = max + 10;
    final span = math.max(1.0, hi - lo);
    final rpmLo = minRpm <= 0 ? 800.0 : minRpm;
    final rpmHi = maxRpm > rpmLo ? maxRpm : rpmLo + 1;

    double xFor(double temp) => plot.left + ((temp - lo) / span).clamp(0.0, 1.0).toDouble() * plot.width;
    double yFor(double rpm) =>
        plot.bottom - ((rpm - rpmLo) / (rpmHi - rpmLo)).clamp(0.0, 1.0).toDouble() * plot.height;

    // Grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    final points = <Offset>[
      Offset(xFor(lo), yFor(rpmLo)),
      Offset(xFor(start), yFor(rpmLo)),
      Offset(xFor(max), yFor(rpmHi)),
      Offset(xFor(hi), yFor(rpmHi)),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }

    final fill = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(plot),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: 0.9),
    );

    final temp = currentTemp;
    if (temp != null && temp.isFinite) {
      final cx = xFor(temp);
      final clamped = temp.clamp(start, max).toDouble();
      final cy = yFor(rpmLo + (rpmHi - rpmLo) * ((clamped - start) / math.max(1.0, max - start)).clamp(0.0, 1.0).toDouble());

      final dash = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      var y = plot.top;
      while (y < plot.bottom) {
        canvas.drawLine(Offset(cx, y), Offset(cx, math.min(y + 4, plot.bottom)), dash);
        y += 8;
      }

      canvas.drawCircle(
        Offset(cx, cy),
        9,
        Paint()
          ..color = accent.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.start != start ||
      old.max != max ||
      old.minRpm != minRpm ||
      old.maxRpm != maxRpm ||
      old.currentTemp != currentTemp ||
      old.accent != accent;
}



