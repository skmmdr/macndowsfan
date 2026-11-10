import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'theme.dart';

/// Window presets for the compact panel, smallest first.
///
/// The panel is frameless, so these are the full window sizes. A button in the
/// panel cycles through them; the layout scales its type with [scale].
class CompactSize {
  const CompactSize(this.width, this.height, this.scale, this.label);

  final double width;
  final double height;
  final double scale;
  final String label;
}

const compactSizes = <CompactSize>[
  CompactSize(280, 118, 1.0, 'S'),
  CompactSize(330, 136, 1.15, 'M'),
  CompactSize(390, 160, 1.35, 'L'),
];

/// Always-on-top mini panel: one fan speed and one temperature at a glance.
///
/// Kept inside the main window so the widget shares the single SMC session
/// instead of opening the device a second time (the driver is exclusive).
///
/// Deliberately cheap to run: no charts, no animations, no timers of its own.
/// It rebuilds once per snapshot (1 Hz) and paints a flat gradient, so an
/// always-on-top widget costs far less than the dashboard it replaces.
class CompactMonitor extends StatelessWidget {
  const CompactMonitor({
    super.key,
    required this.controller,
    required this.sensorKey,
    required this.onSensorChanged,
    required this.sizeIndex,
    required this.onCycleSize,
    required this.onExpand,
    required this.onHide,
    required this.onStartDrag,
  });

  final MonitorController controller;
  final String? sensorKey;
  final ValueChanged<String> onSensorChanged;
  final int sizeIndex;
  final VoidCallback onCycleSize;
  final VoidCallback onExpand;
  final VoidCallback onHide;
  final VoidCallback onStartDrag;

  @override
  Widget build(BuildContext context) {
    final size = compactSizes[sizeIndex.clamp(0, compactSizes.length - 1)];
    final scale = size.scale;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snap = controller.snapshot;
        final fans = snap.fans;
        final index = fans.isEmpty
            ? 0
            : controller.selectedFan.clamp(0, fans.length - 1).toInt();
        final fan = fans.isEmpty ? null : fans[index];
        final setting = controller.fanSetting(index);

        final temps = snap.temps;
        final key = sensorKey ??
            (setting != null && temps.any((t) => t.key == setting.sensor)
                ? setting.sensor
                : (temps.isNotEmpty ? temps.first.key : null));

        TempReading? sensor;
        if (key != null) {
          for (final t in temps) {
            if (t.key == key) {
              sensor = t;
              break;
            }
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onStartDrag(),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.bg2, AppColors.bg, Color(0xFF070A10)],
              ),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.9),
              ),
            ),
            padding: EdgeInsets.all(8 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(snap.ok, size, scale),
                const SizedBox(height: 2),
                Expanded(
                  child: _readings(
                    fan,
                    sensor?.value,
                    sensor?.label,
                    scale,
                  ),
                ),
                SizedBox(height: 4 * scale),
                _speedBar(fan, scale),
                SizedBox(height: 4 * scale),
                _bottomRow(temps, key, fans, setting, snap.ok, scale),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(bool ok, CompactSize size, double scale) {
    final next = compactSizes[(sizeIndex + 1) % compactSizes.length];
    return SizedBox(
      height: 20 * scale,
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? AppColors.green : AppColors.red,
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            Icons.air_rounded,
            size: 12 * scale,
            color: ok ? AppColors.accent : AppColors.red,
          ),
          const SizedBox(width: 3),
          Text(
            'FAN',
            style: TextStyle(
              fontSize: 7.5 * scale,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const Spacer(),
          _MiniButton(
            tooltip: 'Size ${size.label} — click for ${next.label}',
            onTap: onCycleSize,
            label: size.label,
            scale: scale,
          ),
          _MiniButton(
            tooltip: 'Back to dashboard',
            onTap: onExpand,
            icon: Icons.open_in_full_rounded,
            scale: scale,
          ),
          _MiniButton(
            tooltip: 'Hide to tray',
            onTap: onHide,
            icon: Icons.close_rounded,
            scale: scale,
          ),
        ],
      ),
    );
  }

  Widget _readings(FanReading? fan, double? temp, String? sensorLabel,
      double scale) {
    final rpm = fan == null ? '—' : fan.actual.round().toString();
    final detail = fan == null
        ? 'no fan'
        : (fan.target == null
            ? fan.name
            : '${fan.name} → ${fan.target!.round()}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      rpm,
                      style: TextStyle(
                        fontSize: 34 * scale,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.4,
                        color: fan == null ? AppColors.muted : AppColors.text,
                      ),
                    ),
                    SizedBox(width: 3 * scale),
                    Text(
                      'RPM',
                      style: TextStyle(
                        fontSize: 9 * scale,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 2 * scale),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8 * scale, color: AppColors.muted),
              ),
            ],
          ),
        ),
        SizedBox(width: 6 * scale),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      temp == null ? '—' : temp.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 30 * scale,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                        color: tempColor(temp),
                      ),
                    ),
                    SizedBox(width: 1),
                    Text(
                      '°C',
                      style: TextStyle(
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.w500,
                        color: tempColor(temp).withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 2 * scale),
              Text(
                sensorLabel ?? (sensorKey ?? 'no sensor'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 8 * scale, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _speedBar(FanReading? fan, double scale) {
    final fraction = (fan?.fraction ?? 0.0).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3 * scale,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x14FFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.accent2, AppColors.accent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomRow(
    List<TempReading> temps,
    String? key,
    List<FanReading> fans,
    FanSetting? setting,
    bool ok,
    double scale,
  ) {
    final hasKey = key != null && temps.any((t) => t.key == key);
    final mode = switch (setting?.mode) {
      ControlMode.automatic => 'AUTO',
      ControlMode.constant => 'FIX ${setting!.rpm.round()}',
      ControlMode.sensor => 'SENSOR',
      null => '—',
    };
    return SizedBox(
      height: 22 * scale,
      child: Row(
        children: [
          if (fans.length > 1) ...[
            _FanPicker(
              fans: fans,
              selected: controller.selectedFan,
              onSelected: controller.selectFan,
              scale: scale,
            ),
            SizedBox(width: 4 * scale),
          ],
          Expanded(
            child: Container(
              height: 22 * scale,
              padding: EdgeInsets.symmetric(horizontal: 6 * scale),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: hasKey ? key : null,
                  hint: Text(
                    'Choose sensor',
                    style: TextStyle(
                      fontSize: 9.5 * scale,
                      color: AppColors.muted,
                    ),
                  ),
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: AppColors.card2,
                  borderRadius: BorderRadius.circular(8),
                  icon: Icon(
                    Icons.expand_more_rounded,
                    size: 13 * scale,
                    color: AppColors.muted,
                  ),
                  style: TextStyle(
                    fontSize: 9.5 * scale,
                    color: AppColors.text,
                  ),
                  items: [
                    for (final t in temps)
                      DropdownMenuItem(
                        value: t.key,
                        child: Text(
                          t.value == null
                              ? t.label
                              : '${t.label}  ${t.value!.toStringAsFixed(0)}°',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSensorChanged(value);
                  },
                ),
              ),
            ),
          ),
          SizedBox(width: 6 * scale),
          Text(
            ok ? mode : 'OFFLINE',
            style: TextStyle(
              fontSize: 7.5 * scale,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: ok ? AppColors.muted : AppColors.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.tooltip,
    required this.onTap,
    required this.scale,
    this.icon,
    this.label,
  });

  final String tooltip;
  final VoidCallback onTap;
  final double scale;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: InkResponse(
        onTap: onTap,
        radius: 11 * scale,
        child: SizedBox(
          width: 20 * scale,
          height: 20 * scale,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 12 * scale, color: AppColors.muted)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 8.5 * scale,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FanPicker extends StatelessWidget {
  const _FanPicker({
    required this.fans,
    required this.selected,
    required this.onSelected,
    required this.scale,
  });

  final List<FanReading> fans;
  final int selected;
  final ValueChanged<int> onSelected;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Choose fan',
      initialValue: selected,
      color: AppColors.card2,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final f in fans)
          PopupMenuItem(
            value: f.index,
            height: 34,
            child: Text(f.name, style: const TextStyle(fontSize: 11.5)),
          ),
      ],
      child: Container(
        height: 22 * scale,
        padding: EdgeInsets.symmetric(horizontal: 6 * scale),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(
              fans[selected.clamp(0, fans.length - 1)].name,
              style: TextStyle(fontSize: 9.5 * scale, color: AppColors.text),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 13 * scale,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
