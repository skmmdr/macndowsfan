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
  });

  final TempReading reading;
  final List<double> history;
  final bool selected;
  final VoidCallback? onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = tempColor(reading.value);
    final value = reading.value;
    final content = GlassCard(
      hoverable: onTap != null,
      highlight: selected,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
                child: Icon(_iconFor(reading.key), size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reading.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                        fontSize: 21,
                        fontWeight: FontWeight.w300,
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
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(history: history, color: color),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
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
    const pad = 3.0;
    final h = size.height - pad * 2;
    final w = size.width;

    double yFor(double v) => pad + (1 - ((v - lo) / (hi - lo))) * h;
    double xFor(int i) =>
        history.length == 1 ? 0 : i / (history.length - 1) * w;

    final path = Path();
    for (var i = 0; i < history.length; i++) {
      final x = xFor(i);
      final y = yFor(history[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(w, pad + h)
      ..lineTo(0, pad + h)
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
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.85),
    );

    final last = Offset(xFor(history.length - 1), yFor(history.last));
    canvas.drawCircle(last, 3.5, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(last, 2, Paint()..color = color);
  }

  @override
  // The controller mutates the history list in place, so comparing the list
  // objects would never report a change and the sparkline would stay blank.
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
