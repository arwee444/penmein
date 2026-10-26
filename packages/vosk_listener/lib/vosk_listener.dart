import 'dart:convert';

import 'package:flutter/services.dart';

/// What the recogniser heard. [isFinal] results end an utterance.
class VoskEvent {
  const VoskEvent(this.text, {this.isFinal = false, this.error});

  final String text;
  final bool isFinal;
  final String? error;

  static VoskEvent _fromNative(dynamic m) {
    final map = Map<String, Object?>.from(m as Map);
    final type = map['type'] as String?;
    final data = (map['data'] as String?) ?? '';
    if (type == 'error') return VoskEvent('', error: data);
    try {
      final j = jsonDecode(data) as Map<String, dynamic>;
      return VoskEvent((j[type == 'partial' ? 'partial' : 'text'] as String?) ?? '', isFinal: type == 'result');
    } catch (_) {
      return const VoskEvent('');
    }
  }
}

/// Offline speech recognition with Vosk (Android only). Works in the app and
/// in a foreground-service isolate; only one listener runs at a time.
class VoskListener {
  static const _m = MethodChannel('pinnocate/vosk');
  static const _e = EventChannel('pinnocate/vosk/events');
  static Stream<VoskEvent>? _events;

  /// Subscribe before calling [start].
  static Stream<VoskEvent> get events => _events ??= _e.receiveBroadcastStream().map(VoskEvent._fromNative);

  static Future<bool> hasPermission() async => (await _m.invokeMethod<bool>('hasPermission')) ?? false;

  /// Asks for the microphone. Needs a visible activity (the app UI).
  static Future<bool> requestPermission() async => (await _m.invokeMethod<bool>('requestPermission')) ?? false;

  /// Loads the model at [modelPath] and starts listening. With [grammar],
  /// recognition is limited to those phrases (plus unknown speech).
  static Future<void> start({required String modelPath, List<String>? grammar}) => _m.invokeMethod('start', {
    'modelPath': modelPath,
    'grammar': grammar == null ? null : jsonEncode([...grammar, '[unk]']),
  });

  static Future<void> stop() => _m.invokeMethod('stop');

  static Future<void> unzip(String zip, String dest) => _m.invokeMethod('unzip', {'zip': zip, 'dest': dest});

  static Future<void> vibrate() => _m.invokeMethod('vibrate');

  /// [kind]: 'start', 'end' or 'fail'. Distinct short tones.
  static Future<void> beep(String kind) => _m.invokeMethod('beep', {'kind': kind});
}
