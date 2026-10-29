import 'phrases.dart';

enum NoteEnd { pause, stopPhrase, maxLength, nothingHeard, cancelled, error }

class NoteResult {
  const NoteResult(this.text, this.reason);

  /// The tidied note body; empty when nothing should be saved.
  final String text;
  final NoteEnd reason;

  bool get hasNote => text.isNotEmpty;
}

/// Decides when a dictated note is finished. Feed it recogniser events and
/// clock ticks; it returns a [NoteResult] once the note ends. Pure Dart.
class NoteSession {
  NoteSession({
    required DateTime start,
    this.wakePhrases = defaultWakePhrases,
    this.stopPhrases = defaultStopPhrases,
    this.cancelPhrases = defaultCancelPhrases,
    this.pause = const Duration(milliseconds: 2500),
    this.maxLength = const Duration(minutes: 2),
    this.noSpeechTimeout = const Duration(seconds: 8),
  }) : _start = start,
       _lastHeard = start;

  final List<String> wakePhrases;
  final List<String> stopPhrases;
  final List<String> cancelPhrases;

  /// Silence after speech that ends the note.
  final Duration pause;
  final Duration maxLength;

  /// How long to wait for the first word before giving up.
  final Duration noSpeechTimeout;

  final DateTime _start;
  DateTime _lastHeard;
  final List<String> _finals = [];
  String _partial = '';
  NoteResult? _result;

  NoteResult? get result => _result;

  /// Everything heard so far, wake phrase removed (for a live preview).
  String get text => tidyNote(stripWake([..._finals, _partial].join(' '), wakePhrases));

  bool get _hasSpeech => text.isNotEmpty;

  NoteResult? onPartial(String heard, DateTime now) {
    if (_result != null) return _result;
    final n = normalizeSpeech(heard);
    if (n.isNotEmpty && n != _partial) {
      _partial = n;
      _lastHeard = now;
    }
    return null;
  }

  NoteResult? onFinal(String heard, DateTime now) {
    if (_result != null) return _result;
    _partial = '';
    final n = normalizeSpeech(heard);
    if (n.isEmpty) return null;
    _finals.add(n);
    _lastHeard = now;
    final all = _finals.join(' ');
    if (stripTrailing(all, cancelPhrases) != null) return _finish(NoteEnd.cancelled, '');
    final body = stripTrailing(all, stopPhrases);
    if (body != null) return _finish(NoteEnd.stopPhrase, body);
    return null;
  }

  NoteResult? tick(DateTime now) {
    if (_result != null) return _result;
    if (now.difference(_start) >= maxLength) return _finish(NoteEnd.maxLength);
    final quiet = now.difference(_lastHeard);
    if (!_hasSpeech && quiet >= noSpeechTimeout) return _finish(NoteEnd.nothingHeard, '');
    if (_hasSpeech && quiet >= pause) return _finish(NoteEnd.pause);
    return null;
  }

  /// The mic was off for a moment (iPhone restarts Apple's recogniser): don't
  /// count that time as part of the pause.
  void resume(DateTime now) {
    if (_result == null) _lastHeard = now;
  }

  /// The user tapped Done.
  NoteResult finishNow() => _result ?? _finish(NoteEnd.stopPhrase);

  NoteResult cancel() => _result ?? _finish(NoteEnd.cancelled, '');

  NoteResult fail() => _result ?? _finish(NoteEnd.error);

  NoteResult _finish(NoteEnd reason, [String? body]) {
    final t = body == null ? text : tidyNote(stripWake(body, wakePhrases));
    final r = NoteResult(t, t.isEmpty && reason != NoteEnd.cancelled && reason != NoteEnd.error ? NoteEnd.nothingHeard : reason);
    return _result = r;
  }
}
