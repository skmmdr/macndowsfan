import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';

import 'core_ffi.dart';
import 'models.dart';

class MonitorController extends ChangeNotifier {
  MonitorController(this.api, this.handle);

  final CoreApi api;
  final Pointer<Void> handle;

  Snapshot snapshot = Snapshot.empty;
  Settings settings = Settings.empty();
  final Map<String, List<double>> history = {};

  bool applying = false;
  String? actionError;
  DateTime? savedAt;
  int selectedFan = 0;

  Timer? _timer;
  Timer? _debounce;
  int _ticks = 0;

  void start() {
    final raw = api.getSettings(handle);
    settings = Settings.fromJson(raw);
    _tick();
    // Reapply the saved profile so reopening the app behaves like the
    // original Macs Fan Control.
    _apply();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    _ticks++;
    // Retry the SMC every 5 s while it is unavailable, so the app recovers by
    // itself once the AppleSMC driver is installed or Macs Fan Control quits.
    if (!snapshot.ok && _ticks % 5 == 0) {
      snapshot = Snapshot.fromJson(api.reconnect(handle));
    }
    // mf_tick samples and reapplies the stored profile, so sensor curves keep
    // tracking the temperature every second.
    final j = api.tick(handle);
    snapshot = Snapshot.fromJson(j);
    _ensureSettings();
    _recordHistory();
    notifyListeners();
  }

  void _recordHistory() {
    for (final t in snapshot.temps) {
      final v = t.value;
      if (v == null || !v.isFinite) continue;
      final list = history.putIfAbsent(t.key, () => <double>[]);
      list.add(v);
      if (list.length > 72) list.removeAt(0);
    }
  }

  void _ensureSettings() {
    if (snapshot.fans.isEmpty) return;
    selectedFan = selectedFan.clamp(0, snapshot.fans.length - 1);
    for (final f in snapshot.fans) {
      while (settings.fans.length <= f.index) {
        settings.fans.add(FanSetting());
      }
      final s = settings.fans[f.index];
      if (f.controllable) s.rpm = _clamp(s.rpm, f);
      if (s.maxTemp <= s.startTemp) s.maxTemp = s.startTemp + 1;
    }
  }

  double _clamp(double rpm, FanReading f) {
    final lo = f.minRpm > 0 ? f.minRpm : 800.0;
    final hi = f.maxRpm > lo ? f.maxRpm : lo;
    return rpm.clamp(lo, hi).toDouble();
  }

  FanSetting? fanSetting(int index) {
    if (index < 0 || index >= snapshot.fans.length) return null;
    final hardwareIndex = snapshot.fans[index].index;
    if (hardwareIndex >= settings.fans.length) return null;
    return settings.fans[hardwareIndex];
  }

  FanReading? fanReading(int index) {
    if (index < 0 || index >= snapshot.fans.length) return null;
    return snapshot.fans[index];
  }

  double? tempValue(String key) {
    for (final t in snapshot.temps) {
      if (t.key == key) return t.value;
    }
    return null;
  }

  void selectFan(int index) {
    selectedFan = index;
    notifyListeners();
  }

  void updateFan(int index, void Function(FanSetting setting) mutate) {
    final setting = fanSetting(index);
    if (setting == null) return;
    mutate(setting);
    setting.profile = FanProfile.custom.id;
    final reading = fanReading(index);
    if (reading != null && reading.controllable) {
      setting.rpm = _clamp(setting.rpm, reading);
    }
    _scheduleApply();
    notifyListeners();
  }

  String? profileUnavailableReason(int index, FanProfile profile) {
    if (profile != FanProfile.automatic &&
        profile != FanProfile.custom &&
        fanReading(index)?.controllable != true) {
      return '${profile.label} is unavailable: the fan or its SMC speed limits could not be verified.';
    }
    final sensor = profile.requiredSensor;
    if (sensor != null) {
      final value = tempValue(sensor);
      if (value == null || !value.isFinite || value < 0 || value > 110) {
        return '${profile.label} is unavailable: required sensor $sensor has no valid reading. Try again when the sensor is available.';
      }
    }
    return null;
  }

  void applyProfile(int index, FanProfile profile) {
    final setting = fanSetting(index);
    if (setting == null) return;
    final reason = profileUnavailableReason(index, profile);
    if (reason != null) {
      actionError = reason;
      notifyListeners();
      return;
    }
    final reading = fanReading(index);

    switch (profile) {
      case FanProfile.automatic:
        setting.mode = ControlMode.automatic;
      case FanProfile.quiet:
        setting.mode = ControlMode.sensor;
        setting.sensor = profile.requiredSensor!;
        setting.startTemp = 65;
        setting.maxTemp = 90;
      case FanProfile.balanced:
        setting.mode = ControlMode.sensor;
        setting.sensor = profile.requiredSensor!;
        setting.startTemp = 55;
        setting.maxTemp = 85;
      case FanProfile.gaming:
        setting.mode = ControlMode.sensor;
        setting.sensor = profile.requiredSensor!;
        setting.startTemp = 65;
        setting.maxTemp = 85;
      case FanProfile.max:
        setting.mode = ControlMode.constant;
        if (reading != null) setting.rpm = reading.maxRpm;
      case FanProfile.custom:
        break;
    }

    setting.profile = profile.id;
    if (reading != null && reading.controllable) {
      setting.rpm = _clamp(setting.rpm, reading);
    }
    _scheduleApply();
    notifyListeners();
  }

  void setRpm(int index, double rpm) {
    updateFan(index, (s) => s.rpm = rpm);
  }

  void setMode(int index, ControlMode mode) {
    if (mode != ControlMode.automatic && fanReading(index)?.controllable != true) {
      actionError = 'Manual control is unavailable: the fan or its SMC speed limits could not be verified.';
      notifyListeners();
      return;
    }
    updateFan(index, (s) => s.mode = mode);
  }

  void setSensor(int index, String key) {
    updateFan(index, (s) => s.sensor = key);
  }

  void setTemperatures(int index, {double? start, double? max}) {
    updateFan(index, (s) {
      if (start != null) s.startTemp = start;
      if (max != null) s.maxTemp = max;
      if (s.maxTemp <= s.startTemp) s.maxTemp = s.startTemp + 1;
    });
  }

  void _scheduleApply() {
    applying = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _apply);
  }

  Future<void> _apply() async {
    final result = api.apply(handle, settings.toJson());
    applying = false;
    if (result['ok'] == true) {
      actionError = null;
      savedAt = DateTime.now();
    } else {
      actionError = result['error']?.toString() ?? 'failed to apply settings';
    }
    if (result['ok'] == true) {
      snapshot = Snapshot.fromJson(api.sample(handle));
    }
    notifyListeners();
  }

  void restoreAutomatic() {
    for (final f in settings.fans) {
      f.mode = ControlMode.automatic;
      f.profile = FanProfile.automatic.id;
    }
    final result = api.restoreAuto(handle);
    actionError = result['ok'] == true
        ? null
        : result['error']?.toString() ?? 'Failed to restore automatic fan control';
    _scheduleApply();
    notifyListeners();
  }

  void reconnect() {
    snapshot = Snapshot.fromJson(api.reconnect(handle));
    _ensureSettings();
    notifyListeners();
  }

  bool prepareExit() {
    // Keep the saved profile, but do not quit until restoration is confirmed.
    try {
      final result = api.suspend(handle);
      if (result['ok'] != true) {
        actionError = result['error']?.toString() ??
            'Failed to restore automatic fan control';
        notifyListeners();
        return false;
      }
    } catch (e) {
      actionError = 'Failed to restore automatic fan control: $e';
      notifyListeners();
      return false;
    }
    _timer?.cancel();
    _debounce?.cancel();
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    try {
      api.destroy(handle);
    } catch (_) {}
    super.dispose();
  }
}
