// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _StrNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _StrDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _ApplyNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _ApplyDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

void main() {
  final lib = DynamicLibrary.open(
      r'C:\Users\Tamo.Levan\Desktop\macndowsfan\target\release\macndowsfan_core.dll');
  final create = lib.lookupFunction<_CreateNative, _CreateDart>('mf_create');
  final destroy =
      lib.lookupFunction<_DestroyNative, _DestroyDart>('mf_destroy');
  final sample = lib.lookupFunction<_StrNative, _StrDart>('mf_sample');
  final getSettings =
      lib.lookupFunction<_StrNative, _StrDart>('mf_get_settings');
  final apply = lib.lookupFunction<_ApplyNative, _ApplyDart>('mf_apply');
  final restore =
      lib.lookupFunction<_StrNative, _StrDart>('mf_restore_auto');
  final free = lib.lookupFunction<_FreeNative, _FreeDart>('mf_free_string');

  String take(Pointer<Utf8> p) {
    if (p == nullptr) return 'null';
    try {
      return p.toDartString();
    } finally {
      free(p);
    }
  }

  final handle = create();
  try {
    final first = jsonDecode(take(sample(handle)));
    print('sample.ok=${first['ok']} fans=${(first['fans'] as List).length} '
        'temps=${(first['temps'] as List).length} error=${first['error']}');
    for (final fan in first['fans'] as List) {
      print('  fan ${fan['name']}: ${fan['actual']} rpm '
          '(${fan['minRpm']}-${fan['maxRpm']})');
    }
    print('settings=${take(getSettings(handle))}');

    final payload = jsonEncode({
      'fans': [
        {
          'mode': 'constant',
          'rpm': 1500.0,
          'sensor': 'TC0P',
          'start_temp': 55.0,
          'max_temp': 85.0,
        }
      ]
    }).toNativeUtf8();
    try {
      print('apply=${take(apply(handle, payload))}');
    } finally {
      malloc.free(payload);
    }

    for (var i = 0; i < 4; i++) {
      sleep(const Duration(seconds: 1));
      final s = jsonDecode(take(sample(handle)));
      final fan = (s['fans'] as List).first;
      print('forced t+${i + 1}s: ${fan['actual']} rpm '
          'target=${fan['target']} forced=${fan['forced']}');
    }

    print('restore=${take(restore(handle))}');
    sleep(const Duration(seconds: 3));
    final s = jsonDecode(take(sample(handle)));
    final fan = (s['fans'] as List).first;
    print('auto: ${fan['actual']} rpm forced=${fan['forced']}');
  } finally {
    destroy(handle);
  }
}

