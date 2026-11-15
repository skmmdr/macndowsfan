import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'glass_card.dart';

String sensorHint(String key) => switch (key) {
      'TA0P' => 'Air entering the bottom/rear intake',
      'TC0P' => 'Board thermistor near the CPU heatsink',
      'TC0c' => 'Inside CPU core 1',
      'TC1c' => 'Inside CPU core 2',
      'TC2c' => 'Inside CPU core 3',
      'TC3c' => 'Inside CPU core 4',
      'TCXc' => 'Overall CPU package temperature',
      'TCGc' => 'Integrated Intel graphics',
      'TCSc' => 'CPU uncore: memory controller and I/O',
      'TG0P' => 'Board thermistor near the GPU heatsink',
      'TG0d' => 'NVIDIA GPU core (matches nvidia-smi)',
      'TG0D' => 'Extra GPU board sensor',
      'TG0E' => 'Extra GPU board sensor',
      'TG0F' => 'Extra GPU board sensor',
      'TM0P' => 'RAM slot 1',
      'TM1P' => 'RAM slot 2',
      'TM2P' => 'RAM slot 3',
      'TM3P' => 'RAM slot 4',
      'Tp2H' => 'Power supply',
      'TH1A' => 'Drive bay sensor 1',
      'TH1B' => 'Drive bay sensor 2',
      'TL0P' => 'LCD panel',
      'Tb0P' => 'Thunderbolt controller',
      _ => 'SMC temperature sensor $key',
    };

class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.reading,
    required this.history,
    this.selected = false,
    this.onTap,
    this.accent = AppColors.accent,
    this.hero = false,
    this.badge,
  });

  final TempReading reading;
  final List<double> history;
  final bool selected;
  final VoidCallback? onTap;
  final Color accent;
  final bool hero;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = tempColor(reading.value);
    final value = reading.value;
    final content = GlassCard(
      hoverable: onTap != null,
      highlight: selected,
      padding: EdgeInsets.fromLTRB(hero ? 20 : 16, hero ? 18 : 16, hero ? 20 : 16, hero ? 16 : 14),
      radius: hero ? 22 : 18,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(AppColors.card2, color, hero ? 0.26 : 0.13)!,
          AppColors.card,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: hero ? 42 : 34,
                height: hero ? 42 : 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(hero ? 13 : 10),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Icon(_iconFor(reading.key), size: hero ? 21 : 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            reading.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: hero ? 14.5 : 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800, color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reading.key,
                      style: monoStyle(size: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value == null ? '—' : value.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: hero ? 32 : 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: hero ? -0.8 : -0.3,
                        color: value == null ? AppColors.muted : color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const TextSpan(
                      text: ' °C',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: hero ? 12 : 10),
          SizedBox(
            height: hero ? 54 : 34,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(history: history, color: color),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      selected: selected,
      label: '${reading.label}, ${value == null ? 'no reading' : '${value.toStringAsFixed(1)} degrees Celsius'}',
      hint: 'Follow this sensor',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(hero ? 22 : 18),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }

  IconData _iconFor(String key) {
    if (key.startsWith('TC')) return Icons.memory_rounded;
    if (key.startsWith('TG')) return Icons.videogame_asset_rounded;
    if (key.startsWith('TA')) return Icons.wb_sunny_rounded;
    if (key.startsWith('TH') || key.startsWith('TS')) {
      return Icons.storage_rounded;
    }
    if (key.startsWith('TM') || key.startsWith('Tm')) {
      return Icons.developer_board_rounded;
    }
    if (key.startsWith('Tp')) return Icons.bolt_rounded;
    if (key.startsWith('TL')) return Icons.monitor_rounded;
    if (key.startsWith('Tb')) return Icons.bolt_rounded;
    return Icons.thermostat_rounded;
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.history, required this.color});

  final List<double> history;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    var lo = history.reduce(math.min);
    var hi = history.reduce(math.max);
    if (hi - lo < 1.0) {
      lo -= 0.5;
      hi += 0.5;
    }
    const pad = 4.0;
    final h = math.max(1.0, size.height - pad * 2);
    final w = math.max(1.0, size.width - pad * 2);

    double yFor(double v) => pad + (1 - ((v - lo) / (hi - lo))) * h;
    double xFor(int i) => history.length == 1
        ? pad + w
        : pad + i / (history.length - 1) * w;

    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = pad + h * i / 2;
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), guide);
    }

    final points = [
      for (var i = 0; i < history.length; i++) Offset(xFor(i), yFor(history[i])),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    // Midpoint quadratic segments soften the trace without overshooting samples.
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midpoint = Offset((previous.dx + current.dx) / 2, (previous.dy + current.dy) / 2);
      path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
    }
    if (points.length > 1) path.lineTo(points.last.dx, points.last.dy);

    final fill = Path.from(path)
      ..lineTo(points.last.dx, pad + h)
      ..lineTo(points.first.dx, pad + h)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.92),
    );

    final last = points.last;
    canvas.drawCircle(last, 3.5, Paint()..color = color.withValues(alpha: 0.24));
    canvas.drawCircle(last, 1.8, Paint()..color = color);
  }

  @override
  // The controller mutates the history list in place, so comparing the list
  // objects would never report a change and the sparkline would stay blank.
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
