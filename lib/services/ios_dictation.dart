import 'dart:async';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/note_session.dart';
import '../core/phrases.dart';
import 'settings.dart';

/// In-app dictation on iPhone with Apple's speech recogniser (Vosk is
/// Android-only). Same note rules as [Dictation]: pause, stop/cancel phrases
/// and the length limit, via [NoteSession], and the same start/end beeps.
class IosDictation {
  IosDictation(this.settings, {this.onLive});

  final VoiceSettings settings;
  final void Function(String text)? onLive;

  static final _stt = SpeechToText();
  static const _beeps = MethodChannel('penmein/beep');

  /// Asks for microphone + speech recognition permission (first time only).
  static Future<bool> requestPermission() => _stt.initialize();

  static Future<bool> get hasPermission => _stt.hasPermission;

  NoteSession? _session;
  final _done = Completer<NoteResult>();
  Timer? _timer;

  Future<NoteResult> run() async {
    final ok = await _stt.initialize();
    if (!ok) return const NoteResult('', NoteEnd.error);
    // Beep before the mic opens so the tone isn't transcribed.
    if (settings.beep) {
      await _beep('start');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _session = settings.newSession(DateTime.now());
    await _listen();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _maybeFinish(_session?.tick(DateTime.now())));
    final r = await _done.future;
    _timer?.cancel();
    await _stt.stop();
    if (settings.beep) await _beep(r.hasNote ? 'end' : 'fail');
    return r;
  }

  static Future<void> _beep(String kind) => _beeps.invokeMethod<void>('beep', kind).catchError((_) {});

  // No pauseFor: the pause that ends a note is timed by NoteSession, as on
  // Android, not by the plugin or Apple.
  Future<void> _listen() async {
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          listenFor: Duration(seconds: settings.maxSeconds),
        ),
      );
    } catch (_) {
      _maybeFinish(_session?.fail());
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    final s = _session;
    if (s == null || _done.isCompleted) return;
    final now = DateTime.now();
    final words = r.recognizedWords;
    // Apple returns the whole text of the current listen each time. A stop or
    // cancel phrase at the end ends the note straight away.
    final phrase = stripTrailing(words, [...settings.stopPhrases, ...settings.cancelPhrases]) != null;
    NoteResult? res;
    if (phrase) {
      res = s.onFinal(words, now) ?? s.finishNow();
    } else if (r.finalResult) {
      // Apple ended its recognition on its own: keep what was said and listen
      // again, so only the pause rule, "done" or the Done button end the note.
      res = s.onFinal(words, now);
      if (res == null) unawaited(_listen());
    } else {
      s.onPartial(words, now);
    }
    onLive?.call(s.text);
    _maybeFinish(res);
  }

  void _maybeFinish(NoteResult? r) {
    if (r != null && !_done.isCompleted) _done.complete(r);
  }

  void finishNow() => _maybeFinish(_session?.finishNow() ?? const NoteResult('', NoteEnd.cancelled));

  void cancel() => _maybeFinish(_session?.cancel() ?? const NoteResult('', NoteEnd.cancelled));
}
