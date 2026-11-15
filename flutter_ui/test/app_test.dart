import 'dart:ffi' show Pointer, Void, nullptr;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macndowsfan/compact_monitor.dart';
import 'package:macndowsfan/controller.dart';
import 'package:macndowsfan/core_ffi.dart';
import 'package:macndowsfan/dashboard.dart';
import 'package:macndowsfan/models.dart';
import 'package:macndowsfan/theme.dart';

class FakeCore implements CoreApi {
  int applyCalls = 0;

  @override
  Map<String, dynamic> apply(Pointer<Void> handle, Map<String, dynamic> settings) {
    applyCalls++;
    return {'ok': true};
  }

  @override
  Map<String, dynamic> sample(Pointer<Void> handle) => {
        'ok': true,
        'fans': [],
        'temps': [],
      };

  @override
  void destroy(Pointer<Void> handle) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MonitorController makeController(FakeCore api, {double? gpuTemperature = 60}) {
  final controller = MonitorController(api, nullptr);
  controller.snapshot = Snapshot(
    ok: true,
    error: null,
    hint: null,
    modeStyle: 'FS!',
    keyCount: 632,
    updatedMs: 0,
    fans: const [
      FanReading(
        index: 0,
        name: 'Main',
        actual: 1250,
        target: 1200,
        minRpm: 1200,
        maxRpm: 2640,
        forced: false,
        controllable: true,
        valueType: 'fpe2',
        modeKey: 'FS!',
      ),
    ],
    temps: [
      const TempReading(key: 'TC0P', label: 'CPU area', value: 50),
      TempReading(key: 'TG0d', label: 'GPU core', value: gpuTemperature),
    ],
  );
  controller.settings = Settings(fans: [FanSetting()]);
  return controller;
}

void main() {
  testWidgets('dashboard displays readings and blocks unavailable presets', (tester) async {
    tester.view.physicalSize = const Size(1180, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCore();
    final controller = makeController(api, gpuTemperature: null);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Dashboard(controller: controller, version: '0.3.0', onCompact: () {})),
    ));
    expect(find.text('macndowsfan'), findsOneWidget);
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('Temperature sensors'), findsOneWidget);
    expect(find.text('Gaming (unavailable)'), findsOneWidget);
    expect(find.textContaining('required sensor TG0d has no valid reading'), findsWidgets);
    await tester.tap(find.text('Gaming (unavailable)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.settings.fans.single.mode, ControlMode.automatic);
    expect(api.applyCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('available preset applies the right sensor and curve', (tester) async {
    final api = FakeCore();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    controller.applyProfile(0, FanProfile.gaming);
    expect(controller.settings.fans.single.mode, ControlMode.sensor);
    expect(controller.settings.fans.single.sensor, 'TG0d');
    expect(controller.settings.fans.single.startTemp, 65);
    expect(controller.settings.fans.single.maxTemp, 85);
    await tester.pump(const Duration(milliseconds: 250));
    expect(api.applyCalls, 1);
  });

  testWidgets('dashboard fits the minimum supported window', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = makeController(FakeCore());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Dashboard(controller: controller, version: '0.3.0', onCompact: () {})),
    ));
    expect(tester.takeException(), isNull);
  });

  for (var index = 0; index < compactSizes.length; index++) {
    testWidgets('compact widget fits size ${compactSizes[index].label}', (tester) async {
      final size = compactSizes[index];
      tester.view.physicalSize = Size(size.width, size.height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = makeController(FakeCore());
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CompactMonitor(
          controller: controller,
          sensorKey: 'TC0P',
          onSensorChanged: (_) {},
          sizeIndex: index,
          onCycleSize: () {},
          onExpand: () {},
          onHide: () {},
          onStartDrag: () {},
        )),
      ));
      expect(find.text('1250'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
