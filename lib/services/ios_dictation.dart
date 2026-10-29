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
  bool _restarting = false;

  /// Words of the current listen not yet marked final by Apple.
  String _pending = '';

  /// Bumped on each restart; results from an older listen are ignored.
  int _gen = 0;

  Future<NoteResult> run() async {
    final ok = await _stt.initialize();
    if (!ok) return const NoteResult('', NoteEnd.error);
    // Beep before the mic opens so the tone isn't transcribed.
    if (settings.beep) {
      await _beep('start');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _session = settings.newSession(DateTime.now());
    _stt.statusListener = (status) {
      if (status == SpeechToText.listeningStatus) _session?.resume(DateTime.now());
      if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) _restart();
    };
    _stt.errorListener = (_) => _restart();
    await _listen();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _maybeFinish(_session?.tick(DateTime.now())));
    final r = await _done.future;
    _timer?.cancel();
    _stt.statusListener = null;
    _stt.errorListener = null;
    await _stt.stop();
    if (settings.beep) await _beep(r.hasNote ? 'end' : 'fail');
    return r;
  }

  static Future<void> _beep(String kind) => _beeps.invokeMethod<void>('beep', kind).catchError((_) {});

  // No pauseFor: the pause that ends a note is timed by NoteSession, as on
  // Android, not by the plugin or Apple. The plugin may refuse a new listen
  // until the last one has fully stopped, so retry briefly.
  Future<void> _listen() async {
    final gen = _gen;
    for (var i = 0; i < 10 && !_done.isCompleted; i++) {
      if (_stt.isListening) return;
      try {
        await _stt.listen(
          onResult: (r) {
            if (gen == _gen) _onResult(r);
          },
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.dictation,
            listenFor: Duration(seconds: settings.maxSeconds),
          ),
        );
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    _maybeFinish(_session?.fail());
  }

  /// Apple stopped listening but the note isn't over: listen again, so only
  /// the pause rule, "done", the Done button or the length limit end it.
  Future<void> _restart() async {
    if (_restarting || _done.isCompleted || _session == null) return;
    _restarting = true;
    // Give Apple's final result a moment to arrive, then keep any words it
    // didn't confirm: a new listen would drop them.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_pending.isNotEmpty && !_done.isCompleted) {
      _maybeFinish(_session!.onFinal(_pending, DateTime.now()));
      _pending = '';
    }
    _gen++;
    await _listen();
    _restarting = false;
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
      // Apple ended this stretch of recognition: keep what was said. The
      // status change that follows restarts listening (see [_restart]).
      res = s.onFinal(words, now);
      _pending = '';
    } else {
      s.onPartial(words, now);
      _pending = words;
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
