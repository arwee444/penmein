/// Phrase matching for the wake / stop / cancel words. Pure Dart, no Flutter.
library;

const defaultWakePhrases = ['pen me in'];
const defaultStopPhrases = ['done', 'end note'];
const defaultCancelPhrases = ['cancel note'];

final _nonWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// Lower-case words only: punctuation and apostrophes removed, spaces
/// collapsed, Vosk's "[unk]" markers dropped. "Pen me IN!" -> "pen me in".
/// Any script is kept (Hindi notes come back in Devanagari).
String normalizeSpeech(String s) => s
    .toLowerCase()
    .replaceAll('[unk]', ' ')
    .replaceAll("'", '')
    .replaceAll('’', '')
    .replaceAll(_nonWord, ' ')
    .trim();

List<String> _words(String s) {
  final n = normalizeSpeech(s);
  return n.isEmpty ? const [] : n.split(' ');
}

/// True when [heard] contains one of [phrases] as whole words, in order.
bool matchesAnyPhrase(String heard, Iterable<String> phrases) {
  final h = ' ${normalizeSpeech(heard)} ';
  for (final p in phrases) {
    final n = normalizeSpeech(p);
    if (n.isNotEmpty && h.contains(' $n ')) return true;
  }
  return false;
}

/// Removes everything up to and including the first wake phrase found in
/// the opening words of [text] ("uh pen me in buy milk" -> "buy milk").
/// Text without a wake phrase near the start is returned normalized.
String stripWake(String text, Iterable<String> phrases, {int lookahead = 4}) {
  final w = _words(text);
  for (var start = 0; start <= lookahead && start < w.length; start++) {
    for (final p in phrases) {
      final pw = _words(p);
      if (pw.isEmpty || start + pw.length > w.length) continue;
      var hit = true;
      for (var i = 0; i < pw.length; i++) {
        if (w[start + i] != pw[i]) {
          hit = false;
          break;
        }
      }
      if (hit) return w.sublist(start + pw.length).join(' ');
    }
  }
  return w.join(' ');
}

/// If [text] ends with one of [phrases], returns the text before it.
/// Returns null when it doesn't end with any of them.
String? stripTrailing(String text, Iterable<String> phrases) {
  final w = _words(text);
  for (final p in phrases) {
    final pw = _words(p);
    if (pw.isEmpty || pw.length > w.length) continue;
    var hit = true;
    for (var i = 0; i < pw.length; i++) {
      if (w[w.length - pw.length + i] != pw[i]) {
        hit = false;
        break;
      }
    }
    if (hit) return w.sublist(0, w.length - pw.length).join(' ');
  }
  return null;
}

final _tags = RegExp(r'\[[^\]]*\]|\([^)]*\)');
final _edgePunct = RegExp(r'^[\s,;:.\-–—]+|[\s,;:\-–—]+$');

/// Cleans Whisper's output, keeping its capitals and punctuation: drops
/// "[BLANK_AUDIO]"/"(music)" style tags, a leading wake phrase and a trailing
/// stop phrase ("Buy milk. Done." -> "Buy milk.").
String cleanTranscript(String text, {Iterable<String> wake = const [], Iterable<String> stop = const []}) {
  var words = text.replaceAll(_tags, ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  bool matches(List<String> slice, List<String> phrase) {
    if (slice.length != phrase.length) return false;
    for (var i = 0; i < phrase.length; i++) {
      if (normalizeSpeech(slice[i]) != phrase[i]) return false;
    }
    return true;
  }

  for (final p in wake) {
    final pw = _words(p);
    if (pw.isNotEmpty && words.length >= pw.length && matches(words.sublist(0, pw.length), pw)) {
      words = words.sublist(pw.length);
      break;
    }
  }
  for (final p in stop) {
    final pw = _words(p);
    if (pw.isNotEmpty && words.length >= pw.length && matches(words.sublist(words.length - pw.length), pw)) {
      words = words.sublist(0, words.length - pw.length);
      break;
    }
  }
  return tidyNote(words.join(' ').replaceAll(_edgePunct, ''));
}

/// "buy milk" -> "Buy milk".
String tidyNote(String s) {
  final t = s.trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

const _commonWords = {
  'yes', 'no', 'ok', 'okay', 'go', 'stop', 'the', 'a', 'and', 'this', 'that', 'what', 'yeah', //
  'hey', 'hi', 'so', 'now', 'note', 'pen', 'write', 'right', 'well', 'like', 'just',
};

enum PhraseCheck { ok, warning, invalid }

/// Validates a phrase before it is added. Returns a level and a short note.
(PhraseCheck, String?) checkPhrase(String phrase, Iterable<String> existing, {bool isWake = true}) {
  final n = normalizeSpeech(phrase);
  if (n.isEmpty) return (PhraseCheck.invalid, 'Type a few words.');
  if (existing.any((e) => normalizeSpeech(e) == n)) return (PhraseCheck.invalid, 'You already have this phrase.');
  final words = n.split(' ');
  if (words.length > 6) return (PhraseCheck.invalid, 'Keep it to 6 words or fewer.');
  if (isWake && words.length == 1) {
    return (
      PhraseCheck.warning,
      _commonWords.contains(n)
          ? '"$n" is a very common word, so it will trigger by accident. Use 2–4 words.'
          : 'Single words trigger by accident more often. 2–4 words work best.',
    );
  }
  if (words.length > 4) return (PhraseCheck.warning, 'Long phrases are harder to say exactly. 2–4 words work best.');
  return (PhraseCheck.ok, null);
}
