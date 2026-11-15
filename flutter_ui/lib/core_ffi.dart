import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _HandleStringNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _HandleStringDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _ApplyNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _ApplyDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _VoidHandleNative = Void Function(Pointer<Void>);
typedef _VoidHandleDart = void Function(Pointer<Void>);
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);
typedef _NoArgStringNative = Pointer<Utf8> Function();
typedef _NoArgStringDart = Pointer<Utf8> Function();

/// Thin wrapper around `macndowsfan_core.dll`.
///
/// The DLL must sit next to the Flutter executable.
class CoreApi {
  CoreApi._(this._dll);

  final DynamicLibrary _dll;

  static CoreApi open() {
    final dll = DynamicLibrary.open('macndowsfan_core.dll');
    return CoreApi._(dll);
  }

  late final _CreateDart _create =
      _dll.lookupFunction<_CreateNative, _CreateDart>('mf_create');
  late final _HandleStringDart _sample =
      _dll.lookupFunction<_HandleStringNative, _HandleStringDart>('mf_sample');
  late final _HandleStringDart _tick =
      _dll.lookupFunction<_HandleStringNative, _HandleStringDart>('mf_tick');
  late final _HandleStringDart _getSettings = _dll
      .lookupFunction<_HandleStringNative, _HandleStringDart>('mf_get_settings');
  late final _HandleStringDart _reconnect = _dll
      .lookupFunction<_HandleStringNative, _HandleStringDart>('mf_reconnect');
  late final _HandleStringDart _restoreAuto = _dll
      .lookupFunction<_HandleStringNative, _HandleStringDart>('mf_restore_auto');
  late final _HandleStringDart _suspend =
      _dll.lookupFunction<_HandleStringNative, _HandleStringDart>('mf_suspend');
  late final _ApplyDart _apply =
      _dll.lookupFunction<_ApplyNative, _ApplyDart>('mf_apply');
  late final _VoidHandleDart _destroy =
      _dll.lookupFunction<_VoidHandleNative, _VoidHandleDart>('mf_destroy');
  late final _FreeStringDart _freeString = _dll
      .lookupFunction<_FreeStringNative, _FreeStringDart>('mf_free_string');
  late final _NoArgStringDart _version =
      _dll.lookupFunction<_NoArgStringNative, _NoArgStringDart>('mf_version');

  Pointer<Void> create() => _create();

  void destroy(Pointer<Void> handle) => _destroy(handle);

  String version() => _take(_version())['version']?.toString() ?? '0.3.0';

  Map<String, dynamic> sample(Pointer<Void> handle) => _take(_sample(handle));

  /// Sample + apply the stored profile. Called once per second.
  Map<String, dynamic> tick(Pointer<Void> handle) => _take(_tick(handle));

  Map<String, dynamic> getSettings(Pointer<Void> handle) =>
      _take(_getSettings(handle));

  Map<String, dynamic> reconnect(Pointer<Void> handle) =>
      _take(_reconnect(handle));

  Map<String, dynamic> restoreAuto(Pointer<Void> handle) =>
      _take(_restoreAuto(handle));

  Map<String, dynamic> suspend(Pointer<Void> handle) => _take(_suspend(handle));

  Map<String, dynamic> apply(
      Pointer<Void> handle, Map<String, dynamic> settings) {
    final text = jsonEncode(settings).toNativeUtf8();
    try {
      return _take(_apply(handle, text));
    } finally {
      malloc.free(text);
    }
  }

  Map<String, dynamic> _take(Pointer<Utf8> pointer) {
    if (pointer == nullptr) {
      return const {'ok': false, 'error': 'null response from core'};
    }
    try {
      final text = pointer.toDartString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'ok': false, 'error': 'unexpected response: $text'};
    } catch (e) {
      return {'ok': false, 'error': 'FFI decode error: $e'};
    } finally {
      _freeString(pointer);
    }
  }
}
