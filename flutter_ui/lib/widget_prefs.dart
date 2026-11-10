import 'dart:convert';
import 'dart:io';

/// The compact widget's own preferences: size preset, chosen sensor and
/// screen position. These are UI-only state (the Rust core owns the fan
/// settings in `settings.json`), so they live in a small sibling file:
/// `%APPDATA%\MacndowsFan\widget_prefs.json`.
///
/// All IO is best-effort: a missing or corrupt file just means defaults.
class WidgetPrefs {
  WidgetPrefs({
    this.sizeIndex = 0,
    this.sensorKey,
    this.x,
    this.y,
  });

  final int sizeIndex;
  final String? sensorKey;
  final double? x;
  final double? y;

  static File? _file() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return File('$appData\\MacndowsFan\\widget_prefs.json');
  }

  factory WidgetPrefs.load() {
    try {
      final file = _file();
      if (file == null || !file.existsSync()) return WidgetPrefs();
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return WidgetPrefs();
      double? toDouble(dynamic v) =>
          v is num && v.isFinite ? v.toDouble() : null;
      return WidgetPrefs(
        sizeIndex: (decoded['sizeIndex'] as num?)?.toInt() ?? 0,
        sensorKey: decoded['sensorKey']?.toString(),
        x: toDouble(decoded['x']),
        y: toDouble(decoded['y']),
      );
    } catch (_) {
      return WidgetPrefs();
    }
  }

  void save() {
    try {
      final file = _file();
      if (file == null) return;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'sizeIndex': sizeIndex,
          'sensorKey': sensorKey,
          'x': x,
          'y': y,
        }),
        flush: true,
      );
    } catch (_) {
      // Prefs must never break the app.
    }
  }
}
