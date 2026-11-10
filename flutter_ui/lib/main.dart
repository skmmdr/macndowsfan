// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/legacy.dart';

import 'controller.dart';
import 'core_ffi.dart';
import 'dashboard.dart';
import 'compact_monitor.dart';
import 'theme.dart';
import 'widget_prefs.dart';
import 'tray_service.dart';
import 'widgets/glass_card.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final startHidden = args.contains('--startup');

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1180, 880),
    minimumSize: Size(900, 620),
    center: true,
    backgroundColor: Color(0xFF080B11),
    title: 'macndowsfan',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (startHidden) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(const MacsFanApp());
}

class MacsFanApp extends StatefulWidget {
  const MacsFanApp({super.key});

  @override
  State<MacsFanApp> createState() => _MacsFanAppState();
}

class _MacsFanAppState extends State<MacsFanApp> {
  CoreApi? _api;
  MonitorController? _controller;
  TrayService? _tray;
  String? _error;
  bool _compact = false;
  bool _switchingWindow = false;
  bool _wasMaximized = false;
  Rect? _dashboardBounds;
  String? _widgetSensor;
  int _widgetSize = 0;
  Offset? _widgetPos;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Restore the widget's size, sensor and position from the last session.
    final prefs = WidgetPrefs.load();
    _widgetSize = prefs.sizeIndex.clamp(0, compactSizes.length - 1);
    _widgetSensor = prefs.sensorKey;
    // Ignore an off-screen sentinel (e.g. the minimized-window rect).
    if (prefs.x != null && prefs.y != null && prefs.x! > -10000 && prefs.y! > -10000) {
      _widgetPos = Offset(prefs.x!, prefs.y!);
    }
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _init();
  }

  /// Persist the compact widget's prefs. Captures the widget's current
  /// top-left first, so dragging then expanding/hiding keeps the position.
  Future<void> _saveWidgetPrefs() async {
    Offset? pos = _widgetPos;
    if (_compact) {
      final bounds = await windowManager.getBounds();
      pos = bounds.topLeft;
      if (mounted) _widgetPos = pos;
    }
    WidgetPrefs(
      sizeIndex: _widgetSize,
      sensorKey: _widgetSensor,
      x: pos?.dx,
      y: pos?.dy,
    ).save();
  }

  Future<AppExitResponse> _onExitRequested() async {
    _controller?.prepareExit();
    return AppExitResponse.exit;
  }

  void _init() {
    try {
      final api = CoreApi.open();
      final handle = api.create();
      final controller = MonitorController(api, handle);
      controller.start();

      final tray = TrayService(controller);
      _tray = tray;
      unawaited(tray.init().catchError((Object error, StackTrace stack) {
        debugPrint('tray init failed: $error');
      }));

      if (!mounted) return;
      setState(() {
        _api = api;
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _setCompact(bool compact) async {
    if (_switchingWindow || _compact == compact) return;
    _switchingWindow = true;
    try {
      if (compact) {
        // Never capture bounds from a minimized window: Windows reports the
        // iconic off-screen rect and the widget would end up invisible.
        if (await windowManager.isMinimized()) await windowManager.restore();
        _wasMaximized = await windowManager.isMaximized();
        if (_wasMaximized) await windowManager.unmaximize();
        _dashboardBounds = await windowManager.getBounds();
        if (!mounted) return;
        setState(() => _compact = true);
        final size = compactSizes[_widgetSize];
        await windowManager.setMinimumSize(
          Size(compactSizes.first.width, compactSizes.first.height),
        );
        await windowManager.setAsFrameless();
        await windowManager.setResizable(false);
        await windowManager.setSize(Size(size.width, size.height));
        final pos = _widgetPos;
        if (pos != null) await windowManager.setPosition(pos);
        await windowManager.setAlwaysOnTop(true);
      } else {
        // Remember where the widget was before restoring the dashboard.
        await _saveWidgetPrefs();
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.setMinimumSize(const Size(900, 620));
        if (_dashboardBounds != null) {
          await windowManager.setBounds(_dashboardBounds);
        }
        if (_wasMaximized) await windowManager.maximize();
        if (!mounted) return;
        setState(() => _compact = false);
      }
    } finally {
      _switchingWindow = false;
    }
  }

  Future<void> _cycleWidgetSize() async {
    if (!_compact || _switchingWindow) return;
    final next = (_widgetSize + 1) % compactSizes.length;
    setState(() => _widgetSize = next);
    final size = compactSizes[next];
    await windowManager.setSize(Size(size.width, size.height));
    await _saveWidgetPrefs();
  }

  @override
  void dispose() {
    _tray?.dispose();
    _lifecycle.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'macndowsfan',
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
              _tray?.quit();
            },
            const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
              _tray?.hideToTray();
            },
          },
          child: Focus(autofocus: true, child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _MissingCore(
        error: _error!,
        onRetry: () {
          setState(() => _error = null);
          _init();
        },
      );
    }
    final controller = _controller;
    final api = _api;
    if (controller == null || api == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_compact) {
      return CompactMonitor(
        controller: controller,
        sensorKey: _widgetSensor,
        onSensorChanged: (key) {
          setState(() => _widgetSensor = key);
          unawaited(_saveWidgetPrefs());
        },
        sizeIndex: _widgetSize,
        onCycleSize: () => unawaited(_cycleWidgetSize()),
        onExpand: () => unawaited(_setCompact(false)),
        onHide: () async {
          await _saveWidgetPrefs();
          await _tray?.hideToTray();
        },
        onStartDrag: () => unawaited(windowManager.startDragging()),
      );
    }
    return Dashboard(
      controller: controller,
      version: api.version(),
      onCompact: () => unawaited(_setCompact(true)),
      onQuit: () {
        _tray?.quit();
      },
    );
  }
}

class _MissingCore extends StatelessWidget {
  const _MissingCore({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bg, AppColors.bg2],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: AppColors.amber.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Icon(Icons.extension_off_rounded,
                          color: AppColors.amber, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'macndowsfan_core.dll is missing',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'The Flutter UI could not load the Rust SMC core. Keep '
                  'macndowsfan_core.dll next to macndowsfan.exe, then retry.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  error,
                  style: monoStyle(size: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const SelectableText(
                    'Build everything with:  .\\scripts\\build_flutter.ps1\n'
                    'Output:                 dist\\macndowsfan.exe',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: AppColors.muted,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
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
}

