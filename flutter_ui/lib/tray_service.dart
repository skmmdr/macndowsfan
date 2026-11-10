// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import 'controller.dart';
import 'models.dart';

/// Keeps the app alive in the notification area. The native runner hides the
/// window on WM_CLOSE; this service owns the tray icon/menu and performs the
/// real quit (restoring firmware fan control first).
class TrayService with TrayListener {
  TrayService(this.controller);

  static const MethodChannel _windowChannel =
      MethodChannel('macndowsfan/window');

  final MonitorController controller;

  bool _quitting = false;
  int _lastTooltip = 0;

  Future<void> init() async {
    _log('init start');
    await trayManager.setIcon('assets/macndowsfan.png');
    await trayManager.setToolTip('macndowsfan');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Open macndowsfan'),
      MenuItem.separator(),
      MenuItem(key: 'auto', label: 'Restore automatic'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit macndowsfan'),
    ]));

    trayManager.addListener(this);
    controller.addListener(_updateTooltip);
    _updateTooltip(force: true);
    _log('tray ready');
  }

  void _log(String message) {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return;
      final file = File('$appData\\MacndowsFan\\tray.log');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never break the tray.
    }
  }

  void _updateTooltip({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastTooltip < 2000) return;
    _lastTooltip = now;

    final fans = controller.snapshot.fans;
    if (fans.isEmpty) {
      trayManager.setToolTip('macndowsfan');
      return;
    }

    final fan = fans.first;
    final setting = controller.fanSetting(fan.index);
    final mode = setting?.mode.label ?? 'Automatic';
    final rpm = fan.actual.isFinite ? fan.actual.round().toString() : '--';
    trayManager.setToolTip('macndowsfan | $rpm RPM | $mode');
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      unawaited(showWindow());
    } else if (menuItem.key == 'auto') {
      controller.restoreAutomatic();
    } else if (menuItem.key == 'quit') {
      unawaited(quit());
    }
  }

  Future<void> showWindow() async {
    _log('show window');
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    _log('hide to tray');
    await windowManager.hide();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    _log('quit requested');

    controller.removeListener(_updateTooltip);
    controller.prepareExit();

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      await _windowChannel
          .invokeMethod<void>('quit')
          .timeout(const Duration(milliseconds: 700));
    } catch (error) {
      _log('quit channel failed: $error');
    }

    exit(0);
  }

  void dispose() {
    controller.removeListener(_updateTooltip);
    trayManager.removeListener(this);
  }
}
