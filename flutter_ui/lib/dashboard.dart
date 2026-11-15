import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/fan_curve.dart';
import 'widgets/fan_gauge.dart';
import 'widgets/glass_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/status_pill.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.controller,
    required this.version,
    this.onQuit,
    required this.onCompact,
  });

  final MonitorController controller;
  final String version;
  final VoidCallback? onQuit;
  final VoidCallback onCompact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snap = controller.snapshot;
        return Stack(
          children: [
            const _Background(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                child: Column(
                  children: [
                    _Header(controller: controller, onQuit: onQuit, onCompact: onCompact),
                    if (controller.actionError != null ||
                        (!snap.ok && snap.error != null && snap.fans.isNotEmpty)) ...[
                      const SizedBox(height: 10),
                      _ActionError(text: controller.actionError ?? snap.error!),
                    ],
                    const SizedBox(height: 14),
                    Expanded(
                      child: snap.fans.isEmpty
                          ? _ErrorView(controller: controller, version: version)
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 800;
                                if (wide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: _ScrollColumn(
                                          child: _FanColumn(
                                              controller: controller),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 6,
                                        child: _ScrollColumn(
                                          child: _SensorsPanel(
                                              controller: controller),
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _FanColumn(controller: controller),
                                      const SizedBox(height: 16),
                                      _SensorsPanel(controller: controller),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    _Footer(controller: controller, version: version),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScrollColumn extends StatefulWidget {
  const _ScrollColumn({required this.child});

  final Widget child;

  @override
  State<_ScrollColumn> createState() => _ScrollColumnState();
}

class _ScrollColumnState extends State<_ScrollColumn> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: false,
      child: SingleChildScrollView(
        controller: _controller,
        child: widget.child,
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: const [
          ColoredBox(color: AppColors.bg),
          Positioned(
            top: -240,
            right: -160,
            child: _Glow(size: 620, color: AppColors.accent, opacity: 0.05),
          ),
          Positioned(
            bottom: -280,
            left: -200,
            child: _Glow(size: 660, color: AppColors.accent2, opacity: 0.035),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onCompact, this.onQuit});

  final MonitorController controller;
  final VoidCallback onCompact;
  final VoidCallback? onQuit;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 252,
            child: Row(
              children: [
                _Logo(),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('macndowsfan', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4,
                      )),
                      SizedBox(height: 3),
                      Text('FAN CONTROL FOR WINDOWS', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                        fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppColors.muted,
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            ok: snap.ok,
            hasError: snap.error != null,
            label: snap.error != null && snap.fans.isNotEmpty ? 'Control error' : null,
          ),
          if (snap.updatedMs > 0) _Updated(updatedMs: snap.updatedMs),
          FilledButton.icon(
            onPressed: controller.restoreAutomatic,
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Restore automatic'),
          ),
          SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: onCompact,
                  icon: const Icon(Icons.picture_in_picture_alt_outlined, size: 17),
                  label: const Text('Widget'),
                ),
                IconButton(
                  tooltip: 'Reconnect SMC',
                  onPressed: controller.reconnect,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
                if (onQuit != null)
                  TextButton(onPressed: onQuit, child: const Text('Quit')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: const [
                Expanded(
                  child: _LogoTile(
                    color: AppColors.accent,
                    child: Icon(Icons.air_rounded, size: 13, color: Color(0xFF16210F)),
                  ),
                ),
                SizedBox(width: 3),
                Expanded(child: _LogoTile(color: AppColors.accent2)),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Row(
              children: const [
                Expanded(child: _LogoTile(color: AppColors.card2)),
                SizedBox(width: 3),
                Expanded(child: _LogoTile(color: AppColors.border)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.color, this.child});

  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _Updated extends StatelessWidget {
  const _Updated({required this.updatedMs});

  final int updatedMs;

  @override
  Widget build(BuildContext context) {
    final age =
        (DateTime.now().millisecondsSinceEpoch - updatedMs).clamp(0, 999999);
    final text = age < 1000
        ? 'updated just now'
        : 'updated ${(age / 1000).toStringAsFixed(1)}s ago';
    return Text(
      text,
      style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
    );
  }
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _FanColumn extends StatelessWidget {
  const _FanColumn({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final fans = controller.snapshot.fans;
    if (fans.isEmpty) {
      return const GlassCard(
        child: SizedBox(
          height: 160,
          child: Center(
            child: Text(
              'Waiting for fan data…',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      );
    }

    final index = controller.selectedFan.clamp(0, fans.length - 1).toInt();
    final fan = fans[index];
    final setting = controller.fanSetting(index) ?? FanSetting();
    final lo = fan.minRpm > 0 ? fan.minRpm : 800.0;
    final hi = fan.maxRpm > lo ? fan.maxRpm : lo + 1;

    double? peak;
    String peakLabel = 'no sensors';
    for (final t in controller.snapshot.temps) {
      final v = t.value;
      if (v == null || !v.isFinite) continue;
      if (peak == null || v > peak) {
        peak = v;
        peakLabel = t.label;
      }
    }

    return Column(
      children: [
        if (fans.length > 1) ...[
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < fans.length; i++)
                ChoiceChip(
                  label: Text(fans[i].name),
                  selected: i == index,
                  onSelected: (_) => controller.selectFan(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        GlassCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF344C3C), Color(0xFF222F28)],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fan.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${fan.minRpm.round()} – ${fan.maxRpm.round()} RPM · ${fan.valueType}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Tag(
                    text: fan.forced ? 'FORCED' : 'AUTO',
                    color: fan.forced ? AppColors.accent : AppColors.green,
                  ),
                  if (fan.target != null) ...[
                    const SizedBox(width: 8),
                    _Tag(
                      text: 'TARGET ${fan.target!.round()}',
                      color: AppColors.muted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: FanGauge(
                  rpm: fan.actual,
                  minRpm: fan.minRpm,
                  maxRpm: fan.maxRpm,
                  name: fan.name,
                  size: 218,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip('mode key ${fan.modeKey}'),
                  _Chip(fan.controllable ? 'controllable' : 'read-only'),
                  if (setting.mode == ControlMode.constant)
                    _Chip('profile ${setting.rpm.round()} RPM'),
                  if (setting.mode == ControlMode.sensor)
                    _Chip('sensor ${setting.sensor}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.speed_rounded,
                  label: 'TARGET',
                  value: fan.target == null ? '—' : fan.target!.round().toString(),
                  unit: 'RPM',
                  accent: AppColors.accent2,
                  caption: setting.mode.label,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.local_fire_department_rounded,
                  label: 'PEAK',
                  value: peak == null ? '—' : peak.toStringAsFixed(0),
                  unit: '°C',
                  accent: tempColor(peak),
                  caption: peakLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.air_rounded,
                  label: 'SPEED RANGE',
                  value: fan.actual.isFinite && fan.maxRpm > fan.minRpm
                      ? (fan.fraction * 100).round().toString()
                      : '—',
                  unit: '%',
                  accent: AppColors.accent,
                  caption: '${fan.minRpm.round()}–${fan.maxRpm.round()} RPM',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('PROFILES'),
              const SizedBox(height: 6),
              const Text(
                'Choose a preset, or adjust the controls below for a custom profile.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final profile in FanProfile.values)
                    _ProfileChip(
                      label: profile.label,
                      tooltip: controller.profileUnavailableReason(index, profile) ?? profile.hint,
                      selected: setting.profile == profile.id,
                      onTap: controller.profileUnavailableReason(index, profile) == null
                          ? () => controller.applyProfile(index, profile)
                          : null,
                    ),
                ],
              ),
              for (final profile in FanProfile.values)
                if (controller.profileUnavailableReason(index, profile) case final reason?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      reason,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('CONTROL MODE'),
              const SizedBox(height: 8),
              SegmentedButton<ControlMode>(
                segments: const [
                  ButtonSegment(
                    value: ControlMode.automatic,
                    icon: Icon(Icons.auto_mode_rounded, size: 16),
                    label: Text('Automatic'),
                  ),
                  ButtonSegment(
                    value: ControlMode.constant,
                    icon: Icon(Icons.speed_rounded, size: 16),
                    label: Text('Constant'),
                  ),
                  ButtonSegment(
                    value: ControlMode.sensor,
                    icon: Icon(Icons.thermostat_rounded, size: 16),
                    label: Text('Sensor'),
                  ),
                ],
                selected: {setting.mode},
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                onSelectionChanged: (selection) =>
                    controller.setMode(index, selection.first),
              ),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: switch (setting.mode) {
                    ControlMode.automatic => _AutomaticControls(
                        key: const ValueKey('auto'),
                        fan: fan,
                      ),
                    ControlMode.constant => _ConstantControls(
                        key: const ValueKey('constant'),
                        controller: controller,
                        index: index,
                        setting: setting,
                        minRpm: lo,
                        maxRpm: hi,
                      ),
                    ControlMode.sensor => _SensorControls(
                        key: const ValueKey('sensor'),
                        controller: controller,
                        index: index,
                        setting: setting,
                        fan: fan,
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutomaticControls extends StatelessWidget {
  const _AutomaticControls({super.key, required this.fan});

  final FanReading fan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The Mac firmware decides the speed for ${fan.name}. '
              'Thermal policy stays untouched.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConstantControls extends StatelessWidget {
  const _ConstantControls({
    super.key,
    required this.controller,
    required this.index,
    required this.setting,
    required this.minRpm,
    required this.maxRpm,
  });

  final MonitorController controller;
  final int index;
  final FanSetting setting;
  final double minRpm;
  final double maxRpm;

  @override
  Widget build(BuildContext context) {
    final divisions = math.max(1, ((maxRpm - minRpm) / 50).round());
    final mid = (minRpm + maxRpm) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Target speed',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Spacer(),
            _ValueChip(
              '${setting.rpm.round()} RPM',
              AppColors.accent,
            ),
          ],
        ),
        Slider(
          value: setting.rpm.clamp(minRpm, maxRpm).toDouble(),
          min: minRpm,
          max: maxRpm,
          divisions: divisions,
          label: '${setting.rpm.round()} RPM',
          onChanged: (v) => controller.setRpm(index, v),
        ),
        Row(
          children: [
            _PresetChip(
              label: 'Min',
              onTap: () => controller.setRpm(index, minRpm),
            ),
            const SizedBox(width: 8),
            _PresetChip(
              label: 'Mid',
              onTap: () => controller.setRpm(index, mid),
            ),
            const SizedBox(width: 8),
            _PresetChip(
              label: 'Max',
              onTap: () => controller.setRpm(index, maxRpm),
            ),
            const Spacer(),
            Text(
              '${minRpm.round()} – ${maxRpm.round()} RPM',
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _SensorControls extends StatelessWidget {
  const _SensorControls({
    super.key,
    required this.controller,
    required this.index,
    required this.setting,
    required this.fan,
  });

  final MonitorController controller;
  final int index;
  final FanSetting setting;
  final FanReading fan;

  @override
  Widget build(BuildContext context) {
    final temps = controller.snapshot.temps;
    final hasSensor = temps.any((t) => t.key == setting.sensor);
    final current = controller.tempValue(setting.sensor);
    final lo = fan.minRpm > 0 ? fan.minRpm : 800.0;
    final hi = fan.maxRpm > lo ? fan.maxRpm : lo + 1;
    final target = sensorTarget(current, setting.startTemp, setting.maxTemp, lo, hi);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Follow sensor',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: hasSensor ? setting.sensor : null,
              hint: const Text(
                'Select a sensor',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              isExpanded: true,
              dropdownColor: AppColors.card2,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
              items: [
                for (final t in temps)
                  DropdownMenuItem(
                    value: t.key,
                    child: Text(
                      '${t.label} · ${t.key}${t.value == null ? '' : '  ${t.value!.toStringAsFixed(1)} °C'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setSensor(index, value);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Start at',
          value: setting.startTemp,
          min: 30,
          max: math.max(31, setting.maxTemp - 1),
          suffix: ' °C',
          onChanged: (v) => controller.setTemperatures(index, start: v),
        ),
        _SliderRow(
          label: 'Full speed at',
          value: setting.maxTemp,
          min: setting.startTemp + 1,
          max: 105,
          suffix: ' °C',
          onChanged: (v) => controller.setTemperatures(index, max: v),
        ),
        const SizedBox(height: 2),
        const Text(
          'The fan runs at minimum speed below the start temperature and reaches maximum speed at the full-speed temperature.',
          style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 8),
        FanCurve(
          start: setting.startTemp,
          max: setting.maxTemp,
          minRpm: lo,
          maxRpm: hi,
          currentTemp: current,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                current == null
                    ? '${setting.sensor} unavailable · maximum speed requested'
                    : '${setting.sensor} now ${current.toStringAsFixed(1)} °C',
                style: TextStyle(
                  fontSize: 11,
                  color: current == null ? AppColors.amber : AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Estimated curve target; the actual target may differ while readings are smoothed.',
              child: _ValueChip('~${target.round()} RPM', AppColors.accent),
            ),
          ],
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final hi = max > min ? max : min + 1;
    final v = value.clamp(min, hi).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
            const Spacer(),
            Text(
              '${v.round()}$suffix',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 34,
          child: Slider(
            value: v,
            min: min,
            max: hi,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SensorsPanel extends StatelessWidget {
  const _SensorsPanel({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final temps = controller.snapshot.temps;
    final setting = controller.fanSetting(controller.selectedFan);

    TempReading? hottest;
    for (final t in temps) {
      final v = t.value;
      if (v == null || !v.isFinite) continue;
      if (hottest == null || v > hottest.value!) hottest = t;
    }
    final hero = hottest;
    final rest = temps.where((t) => t.key != hero?.key).toList();

    void follow(TempReading t) {
      controller.setSensor(controller.selectedFan, t.key);
      controller.setMode(controller.selectedFan, ControlMode.sensor);
    }

    bool following(TempReading t) =>
        setting?.mode == ControlMode.sensor && setting?.sensor == t.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.thermostat_rounded,
                size: 17, color: AppColors.muted),
            const Text(
              'Temperature sensors',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            _Chip('${temps.length}'),
            const Text(
              'click a card to follow it',
              style: TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (temps.isEmpty)
          const GlassCard(
            child: SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No temperature sensors available.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          )
        else ...[
          if (hero != null) Tooltip(
            message: '${sensorHint(hero.key)}\n\nClick to follow ${hero.label}',
            child: SensorCard(
              reading: hero,
              history: controller.history[hero.key] ?? const [],
              hero: true,
              badge: 'HOTTEST',
              selected: following(hero),
              onTap: () => follow(hero),
            ),
          ),
          if (rest.isNotEmpty) ...[
            if (hero != null) const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 780
                    ? 3
                    : constraints.maxWidth > 420
                        ? 2
                        : 1;
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in rest)
                      SizedBox(
                        width: width,
                        child: Tooltip(
                          message:
                              '${sensorHint(t.key)}\n\nClick to follow ${t.label}',
                          child: SensorCard(
                            reading: t,
                            history: controller.history[t.key] ?? const [],
                            selected: following(t),
                            onTap: () => follow(t),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color accent;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.version});

  final MonitorController controller;
  final String version;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot;
    final savedAt = controller.savedAt;
    return Row(
      children: [
        _Chip(snap.modeStyle ?? 'SMC'),
        if (snap.keyCount != null) ...[
          const SizedBox(width: 6),
          _Chip('${snap.keyCount} keys'),
        ],
        const Spacer(),
        if (controller.applying)
          const Row(
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
              SizedBox(width: 8),
              Text(
                'Applying…',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          )
        else if (savedAt != null)
          Text(
            'Saved ${_clock(savedAt)}',
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        const SizedBox(width: 12),
        Text(
          'v$version',
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
        ),
      ],
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.controller, required this.version});

  final MonitorController controller;
  final String version;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot;
    final error = snap.error ?? 'The SMC device could not be opened.';
    final hint = snap.hint;

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: GlassCard(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Icon(Icons.cloud_off_rounded,
                          color: AppColors.red, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cannot talk to the SMC',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'The fan and temperature hardware is not reachable.',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      ok: false,
                      hasError: true,
                      label: 'offline',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _InfoLine(icon: Icons.error_outline_rounded, text: error),
                if (hint != null && hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoLine(
                    icon: Icons.lightbulb_outline_rounded,
                    text: hint,
                    color: AppColors.amber,
                  ),
                ],
                const SizedBox(height: 16),
                const _Bullet(
                  'Quit Macs Fan Control from its tray icon — it opens '
                  '\\\\.\\APPLESMC exclusively.',
                ),
                const _Bullet(
                  'If the AppleSMC driver service is stopped, restart this '
                  'app as administrator.',
                ),
                const _Bullet(
                  'The signed applesmc.sys driver is installed by Macs Fan '
                  'Control and remains after it is closed.',
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: controller.reconnect,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry connection'),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _openLogFolder,
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Open log folder'),
                    ),
                    const Spacer(),
                    Text(
                      'v$version',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openLogFolder() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final dir = Directory('$appData\\MacndowsFan');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    Process.run('explorer.exe', [dir.path]);
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    this.color = AppColors.red,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color == AppColors.red ? AppColors.text : color,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: CircleAvatar(radius: 2, backgroundColor: AppColors.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 1.8,
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.muted),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final available = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.55)
                    : AppColors.border,
              ),
            ),
            child: Text(
              available ? label : '$label (unavailable)',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}




