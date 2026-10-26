import 'dart:async';

import 'package:vosk_listener/vosk_listener.dart';

import '../core/note_session.dart';
import 'settings.dart';

/// One dictated note: free (non-grammar) recognition until the note ends.
/// Used both by the background service and by the in-app mic button.
class Dictation {
  Dictation(this.settings, {this.onLive});

  final VoiceSettings settings;

  /// Live preview of the text so far.
  final void Function(String text)? onLive;

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
      await VoskListener.start(modelPath: modelPath);
      // Start the clock once the mic is live, so model start-up time isn't
      // counted against the "nothing heard" timeout.
      _session = settings.newSession(DateTime.now());
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _maybeFinish(_session?.tick(DateTime.now())));
    } catch (_) {
      _maybeFinish(const NoteResult('', NoteEnd.error));
    }
    final r = await _done.future;
    _timer?.cancel();
    await _sub?.cancel();
    if (settings.beep) await _beep(r.hasNote ? 'end' : 'fail');
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
