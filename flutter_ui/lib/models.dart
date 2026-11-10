import 'dart:convert';

enum ControlMode { automatic, constant, sensor }

enum FanProfile { automatic, quiet, balanced, gaming, max, custom }

extension FanProfileX on FanProfile {
  String get id => switch (this) {
        FanProfile.automatic => 'automatic',
        FanProfile.quiet => 'quiet',
        FanProfile.balanced => 'balanced',
        FanProfile.gaming => 'gaming',
        FanProfile.max => 'max',
        FanProfile.custom => 'custom',
      };

  String get label => switch (this) {
        FanProfile.automatic => 'Auto',
        FanProfile.quiet => 'Quiet',
        FanProfile.balanced => 'Balanced',
        FanProfile.gaming => 'Gaming',
        FanProfile.max => 'Max',
        FanProfile.custom => 'Custom',
      };

  String get hint => switch (this) {
        FanProfile.automatic => 'Firmware fan control',
        FanProfile.quiet => 'CPU proximity curve 65-90 C',
        FanProfile.balanced => 'CPU proximity curve 55-85 C',
        FanProfile.gaming => 'GPU die curve 65-85 C',
        FanProfile.max => 'Constant maximum RPM',
        FanProfile.custom => 'Your own settings',
      };

  static FanProfile fromId(String? id) => switch (id) {
        'automatic' => FanProfile.automatic,
        'quiet' => FanProfile.quiet,
        'balanced' => FanProfile.balanced,
        'gaming' => FanProfile.gaming,
        'max' => FanProfile.max,
        _ => FanProfile.custom,
      };
}

extension ControlModeX on ControlMode {
  String get wire => switch (this) {
        ControlMode.automatic => 'automatic',
        ControlMode.constant => 'constant',
        ControlMode.sensor => 'sensor',
      };

  String get label => switch (this) {
        ControlMode.automatic => 'Automatic',
        ControlMode.constant => 'Constant speed',
        ControlMode.sensor => 'Sensor-based',
      };

  static ControlMode fromWire(Object? value) => switch (value) {
        'constant' => ControlMode.constant,
        'sensor' => ControlMode.sensor,
        _ => ControlMode.automatic,
      };
}

class FanReading {
  const FanReading({
    required this.index,
    required this.name,
    required this.actual,
    required this.target,
    required this.minRpm,
    required this.maxRpm,
    required this.forced,
    required this.controllable,
    required this.valueType,
    required this.modeKey,
  });

  final int index;
  final String name;
  final double actual;
  final double? target;
  final double minRpm;
  final double maxRpm;
  final bool forced;
  final bool controllable;
  final String valueType;
  final String modeKey;

  double get fraction {
    final span = maxRpm - minRpm;
    if (span <= 0) return 0;
    return ((actual - minRpm) / span).clamp(0.0, 1.0).toDouble();
  }

  factory FanReading.fromJson(Map<String, dynamic> j) => FanReading(
        index: (j['index'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? 'Fan',
        actual: (j['actual'] as num?)?.toDouble() ?? 0,
        target: (j['target'] as num?)?.toDouble(),
        minRpm: (j['minRpm'] as num?)?.toDouble() ?? 0,
        maxRpm: (j['maxRpm'] as num?)?.toDouble() ?? 0,
        forced: j['forced'] == true,
        controllable: j['controllable'] == true,
        valueType: j['valueType']?.toString() ?? '',
        modeKey: j['modeKey']?.toString() ?? '',
      );
}

class TempReading {
  const TempReading({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final double? value;

  factory TempReading.fromJson(Map<String, dynamic> j) => TempReading(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        value: (j['value'] as num?)?.toDouble(),
      );
}

class Snapshot {
  const Snapshot({
    required this.ok,
    required this.error,
    required this.hint,
    required this.modeStyle,
    required this.keyCount,
    required this.updatedMs,
    required this.fans,
    required this.temps,
  });

  final bool ok;
  final String? error;
  final String? hint;
  final String? modeStyle;
  final int? keyCount;
  final int updatedMs;
  final List<FanReading> fans;
  final List<TempReading> temps;

  static const empty = Snapshot(
    ok: false,
    error: null,
    hint: null,
    modeStyle: null,
    keyCount: null,
    updatedMs: 0,
    fans: [],
    temps: [],
  );

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        ok: j['ok'] == true,
        error: j['error']?.toString(),
        hint: j['hint']?.toString(),
        modeStyle: j['modeStyle']?.toString(),
        keyCount: (j['keyCount'] as num?)?.toInt(),
        updatedMs: (j['updatedMs'] as num?)?.toInt() ?? 0,
        fans: (j['fans'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FanReading.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        temps: (j['temps'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => TempReading.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Snapshot copyWith({
    bool? ok,
    String? error,
    String? hint,
    List<FanReading>? fans,
    List<TempReading>? temps,
  }) =>
      Snapshot(
        ok: ok ?? this.ok,
        error: error ?? this.error,
        hint: hint ?? this.hint,
        modeStyle: modeStyle,
        keyCount: keyCount,
        updatedMs: updatedMs,
        fans: fans ?? this.fans,
        temps: temps ?? this.temps,
      );
}

class FanSetting {
  FanSetting({
    this.profile = 'custom',
    this.mode = ControlMode.automatic,
    this.rpm = 1500,
    this.sensor = 'TC0P',
    this.startTemp = 55,
    this.maxTemp = 85,
  });

  String profile;
  ControlMode mode;
  double rpm;
  String sensor;
  double startTemp;
  double maxTemp;

  factory FanSetting.fromJson(Map<String, dynamic> j) => FanSetting(
        profile: j['profile']?.toString() ?? 'custom',
        mode: ControlModeX.fromWire(j['mode']),
        rpm: (j['rpm'] as num?)?.toDouble() ?? 1500,
        sensor: j['sensor']?.toString() ?? 'TC0P',
        startTemp: (j['start_temp'] as num?)?.toDouble() ?? 55,
        maxTemp: (j['max_temp'] as num?)?.toDouble() ?? 85,
      );

  Map<String, dynamic> toJson() => {
        'profile': profile,
        'mode': mode.wire,
        'rpm': rpm,
        'sensor': sensor,
        'start_temp': startTemp,
        'max_temp': maxTemp,
      };

  FanSetting clone() => FanSetting(
        profile: profile,
        mode: mode,
        rpm: rpm,
        sensor: sensor,
        startTemp: startTemp,
        maxTemp: maxTemp,
      );

  String toJsonString() => jsonEncode(toJson());
}

class Settings {
  Settings({required this.fans});

  final List<FanSetting> fans;

  factory Settings.empty() => Settings(fans: []);

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        fans: (j['fans'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FanSetting.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'fans': fans.map((f) => f.toJson()).toList(),
      };

  Settings clone() => Settings(fans: fans.map((f) => f.clone()).toList());
}

/// Linear interpolation used for the sensor-based curve preview.
double sensorTarget(
  double? temp,
  double start,
  double max,
  double minRpm,
  double maxRpm,
) {
  final lo = minRpm <= 0 ? 800.0 : minRpm;
  final hi = maxRpm > lo ? maxRpm : lo;
  if (temp == null || !temp.isFinite || temp <= start) return lo;
  if (temp >= max || max - start <= 0.1) return hi;
  final t = ((temp - start) / (max - start)).clamp(0.0, 1.0).toDouble();
  return lo + (hi - lo) * t;
}

