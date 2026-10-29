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
    this.beep = true,
    this.modelId = 'en-us',
    this.whisperId = '',
    this.speakLang = 'en',
  });

  final List<String> wakePhrases;
  final List<String> stopPhrases;
  final List<String> cancelPhrases;
  final int pauseMs;
  final int maxSeconds;
  final bool vibrate;
  final bool beep;

  /// Speech model that writes notes (see speechModels).
  final String modelId;

  /// Whisper model that rewrites each note accurately ('' = off).
  final String whisperId;

  /// Language the user speaks ('en', 'hi', 'ta', 'kn' or 'auto'). Whisper
  /// always writes English: other languages are translated.
  final String speakLang;

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
    bool? beep,
    String? modelId,
    String? whisperId,
    String? speakLang,
  }) => VoiceSettings(
    wakePhrases: wakePhrases ?? this.wakePhrases,
    stopPhrases: stopPhrases ?? this.stopPhrases,
    cancelPhrases: cancelPhrases ?? this.cancelPhrases,
    pauseMs: pauseMs ?? this.pauseMs,
    maxSeconds: maxSeconds ?? this.maxSeconds,
    vibrate: vibrate ?? this.vibrate,
    beep: beep ?? this.beep,
    modelId: modelId ?? this.modelId,
    whisperId: whisperId ?? this.whisperId,
    speakLang: speakLang ?? this.speakLang,
  );

  Map<String, Object?> toJson() => {
    'wake': wakePhrases,
    'stop': stopPhrases,
    'cancel': cancelPhrases,
    'pauseMs': pauseMs,
    'maxSeconds': maxSeconds,
    'vibrate': vibrate,
    'beep': beep,
    'model': modelId,
    'whisper': whisperId,
    'lang': speakLang,
  };

  static List<String> _list(Object? v, List<String> fallback) {
    if (v is! List) return fallback;
    return v.whereType<String>().where((s) => normalizeSpeech(s).isNotEmpty).toList();
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
      beep: (m['beep'] as bool?) ?? true,
      modelId: (m['model'] as String?) ?? 'en-us',
      whisperId: (m['whisper'] as String?) ?? '',
      speakLang: (m['lang'] as String?) ?? 'en',
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
