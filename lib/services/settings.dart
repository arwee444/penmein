import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/note_session.dart';
import '../core/phrases.dart';

/// Voice settings, stored through FlutterForegroundTask's key-value store so
/// the background service can read them too.
class VoiceSettings {
  const VoiceSettings({
    this.wakePhrases = defaultWakePhrases,
    this.stopPhrases = defaultStopPhrases,
    this.cancelPhrases = defaultCancelPhrases,
    this.pauseMs = 2500,
    this.maxSeconds = 120,
    this.vibrate = true,
  });

  final List<String> wakePhrases;
  final List<String> stopPhrases;
  final List<String> cancelPhrases;
  final int pauseMs;
  final int maxSeconds;
  final bool vibrate;

  static const _key = 'pm_settings';

  NoteSession newSession(DateTime start) => NoteSession(
    start: start,
    wakePhrases: wakePhrases,
    stopPhrases: stopPhrases,
    cancelPhrases: cancelPhrases,
    pause: Duration(milliseconds: pauseMs),
    maxLength: Duration(seconds: maxSeconds),
  );

  VoiceSettings copyWith({
    List<String>? wakePhrases,
    List<String>? stopPhrases,
    List<String>? cancelPhrases,
    int? pauseMs,
    int? maxSeconds,
    bool? vibrate,
  }) => VoiceSettings(
    wakePhrases: wakePhrases ?? this.wakePhrases,
    stopPhrases: stopPhrases ?? this.stopPhrases,
    cancelPhrases: cancelPhrases ?? this.cancelPhrases,
    pauseMs: pauseMs ?? this.pauseMs,
    maxSeconds: maxSeconds ?? this.maxSeconds,
    vibrate: vibrate ?? this.vibrate,
  );

  Map<String, Object?> toJson() => {
    'wake': wakePhrases,
    'stop': stopPhrases,
    'cancel': cancelPhrases,
    'pauseMs': pauseMs,
    'maxSeconds': maxSeconds,
    'vibrate': vibrate,
  };

  static List<String> _list(Object? v, List<String> fallback) {
    if (v is! List) return fallback;
    final l = v.whereType<String>().where((s) => normalizeSpeech(s).isNotEmpty).toList();
    return l;
  }

  static VoiceSettings fromJson(Map<String, dynamic> m) {
    final wake = _list(m['wake'], defaultWakePhrases);
    return VoiceSettings(
      wakePhrases: wake.isEmpty ? defaultWakePhrases : wake,
      stopPhrases: _list(m['stop'], defaultStopPhrases),
      cancelPhrases: _list(m['cancel'], defaultCancelPhrases),
      pauseMs: ((m['pauseMs'] as num?)?.toInt() ?? 2500).clamp(1000, 6000),
      maxSeconds: ((m['maxSeconds'] as num?)?.toInt() ?? 120).clamp(15, 600),
      vibrate: (m['vibrate'] as bool?) ?? true,
    );
  }

  static Future<VoiceSettings> load() async {
    final raw = await FlutterForegroundTask.getData<String>(key: _key);
    if (raw == null) return const VoiceSettings();
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VoiceSettings();
    }
  }

  Future<void> save() => FlutterForegroundTask.saveData(key: _key, value: jsonEncode(toJson()));
}
