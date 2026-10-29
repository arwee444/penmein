import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/note_session.dart';
import '../core/phrases.dart';
import 'settings.dart';

/// In-app dictation on iPhone with Apple's speech recogniser (Vosk is
/// Android-only). Same note rules as [Dictation]: pause, stop/cancel phrases
/// and the length limit, via [NoteSession].
class IosDictation {
  IosDictation(this.settings, {this.onLive});

  final VoiceSettings settings;
  final void Function(String text)? onLive;

  static final _stt = SpeechToText();

  /// Asks for microphone + speech recognition permission (first time only).
  static Future<bool> requestPermission() => _stt.initialize();

  static Future<bool> get hasPermission => _stt.hasPermission;

  NoteSession? _session;
  final _done = Completer<NoteResult>();
  Timer? _timer;

  Future<NoteResult> run() async {
    final ok = await _stt.initialize(onError: (_) => _maybeFinish(_session?.fail() ?? const NoteResult('', NoteEnd.error)));
    if (!ok) return const NoteResult('', NoteEnd.error);
    _session = settings.newSession(DateTime.now());
    await _stt.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: Duration(seconds: settings.maxSeconds),
        pauseFor: Duration(milliseconds: settings.pauseMs),
      ),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _maybeFinish(_session?.tick(DateTime.now())));
    final r = await _done.future;
    _timer?.cancel();
    await _stt.stop();
    return r;
  }

  void _onResult(SpeechRecognitionResult r) {
    final s = _session;
    if (s == null || _done.isCompleted) return;
    final now = DateTime.now();
    final words = r.recognizedWords;
    // Apple returns the whole text so far each time: treat it as one final
    // utterance once it is final or ends with a stop/cancel phrase.
    final ends = r.finalResult || stripTrailing(words, [...settings.stopPhrases, ...settings.cancelPhrases]) != null;
    NoteResult? res;
    if (ends) {
      res = s.onFinal(words, now) ?? s.finishNow();
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
