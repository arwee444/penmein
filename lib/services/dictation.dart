import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vosk_listener/vosk_listener.dart';

import '../core/note_session.dart';
import '../core/phrases.dart';
import 'settings.dart';
import 'whisper.dart';

/// One dictated note: free (non-grammar) recognition until the note ends.
/// Used both by the background service and by the in-app mic button.
///
/// Vosk listens live (preview, pause and stop/cancel phrases). With a
/// [whisperPath], the note's audio is also kept and Whisper rewrites the text
/// once it ends; if Whisper fails, Vosk's text is kept.
class Dictation {
  Dictation(this.settings, {this.onLive, this.whisperPath, this.onPolishing});

  final VoiceSettings settings;

  /// Live preview of the text so far.
  final void Function(String text)? onLive;

  final String? whisperPath;

  /// Called when listening has ended and Whisper starts rewriting.
  final void Function()? onPolishing;

  NoteSession? _session;
  final _done = Completer<NoteResult>();
  StreamSubscription<VoskEvent>? _sub;
  Timer? _timer;

  Future<NoteResult> run(String modelPath) async {
    // Beep before the mic opens so the tone isn't transcribed.
    if (settings.beep) {
      await _beep('start');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _sub = VoskListener.events.listen(_onEvent);
    try {
      await VoskListener.start(modelPath: modelPath, record: whisperPath != null);
      // Start the clock once the mic is live, so model start-up time isn't
      // counted against the "nothing heard" timeout.
      _session = settings.newSession(DateTime.now());
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _maybeFinish(_session?.tick(DateTime.now())));
    } catch (_) {
      _maybeFinish(const NoteResult('', NoteEnd.error));
    }
    var r = await _done.future;
    _timer?.cancel();
    await _sub?.cancel();
    if (settings.beep) await _beep(r.hasNote ? 'end' : 'fail');
    if (whisperPath != null) {
      final audio = await VoskListener.takeAudio().catchError((_) => null);
      if (r.hasNote && audio != null) r = await _polish(r, audio);
    }
    return r;
  }

  Future<NoteResult> _polish(NoteResult r, Uint8List audio) async {
    onPolishing?.call();
    try {
      final text = await WhisperNotes.transcribe(whisperPath!, audio, language: settings.speakLang);
      final clean = cleanTranscript(text ?? '', wake: settings.wakePhrases, stop: settings.stopPhrases);
      if (clean.isNotEmpty) return NoteResult(clean, r.reason);
    } catch (e) {
      debugPrint('Whisper failed, keeping the live text: ${e.runtimeType}');
    }
    return r;
  }

  static Future<void> _beep(String kind) => VoskListener.beep(kind).catchError((_) {});

  void _onEvent(VoskEvent e) {
    final s = _session;
    if (s == null || _done.isCompleted) return;
    if (e.error != null) return _maybeFinish(s.fail());
    final now = DateTime.now();
    final r = e.isFinal ? s.onFinal(e.text, now) : s.onPartial(e.text, now);
    onLive?.call(s.text);
    _maybeFinish(r);
  }

  void _maybeFinish(NoteResult? r) {
    if (r != null && !_done.isCompleted) _done.complete(r);
  }

  void finishNow() => _maybeFinish(_session?.finishNow() ?? const NoteResult('', NoteEnd.cancelled));

  void cancel() => _maybeFinish(_session?.cancel() ?? const NoteResult('', NoteEnd.cancelled));
}
