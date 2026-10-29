import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penmein/core/note_session.dart';
import 'package:penmein/core/phrases.dart';
import 'package:penmein/data/notes.dart';

void main() {
  group('phrases', () {
    test('matches wake phrase as whole words, ignoring [unk] and case', () {
      expect(matchesAnyPhrase('[unk] Pen me IN', defaultWakePhrases), isTrue);
      expect(matchesAnyPhrase('open me inside', defaultWakePhrases), isFalse);
      expect(matchesAnyPhrase('pen me', defaultWakePhrases), isFalse);
    });

    test('strips the wake phrase from the start only', () {
      expect(stripWake('pen me in buy milk', defaultWakePhrases), 'buy milk');
      expect(stripWake('uh pen me in buy milk', defaultWakePhrases), 'buy milk');
      expect(stripWake('buy milk', defaultWakePhrases), 'buy milk');
    });

    test('keeps non-Latin scripts (Hindi notes)', () {
      expect(normalizeSpeech('दूध लाना है'), 'दूध लाना है');
      expect(stripTrailing('दूध लाना बस', ['बस']), 'दूध लाना');
    });

    test('cleans Whisper text but keeps its punctuation', () {
      expect(
        cleanTranscript('[BLANK_AUDIO] Pen me in, buy milk and eggs. Done.', wake: defaultWakePhrases, stop: defaultStopPhrases),
        'Buy milk and eggs.',
      );
      expect(cleanTranscript('Call the dentist at 4 PM.', stop: defaultStopPhrases), 'Call the dentist at 4 PM.');
      expect(cleanTranscript(' (music) ', stop: defaultStopPhrases), '');
    });

    test('strips trailing stop phrase', () {
      expect(stripTrailing('buy milk end note', defaultStopPhrases), 'buy milk');
      expect(stripTrailing('buy milk done', defaultStopPhrases), 'buy milk');
      expect(stripTrailing('done buying milk', defaultStopPhrases), isNull);
    });

    test('warns about single common wake words', () {
      expect(checkPhrase('ok', const []).$1, PhraseCheck.warning);
      expect(checkPhrase('pen me in', const ['pen me in']).$1, PhraseCheck.invalid);
      expect(checkPhrase('note this down', const []).$1, PhraseCheck.ok);
    });
  });

  group('note session', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('ends after a pause and trims the wake phrase', () {
      final s = NoteSession(start: t0);
      s.onPartial('pen me in buy', at(500));
      s.onFinal('pen me in buy milk', at(1500));
      expect(s.tick(at(3000)), isNull);
      final r = s.tick(at(4100))!;
      expect(r.reason, NoteEnd.pause);
      expect(r.text, 'Buy milk');
    });

    test('keeps listening while partial text keeps changing', () {
      final s = NoteSession(start: t0);
      for (var i = 1; i <= 10; i++) {
        s.onPartial('word ' * i, at(i * 1000));
        expect(s.tick(at(i * 1000 + 900)), isNull);
      }
    });

    test('ends on stop phrase', () {
      final s = NoteSession(start: t0);
      final r = s.onFinal('call the dentist done', at(1000))!;
      expect(r.reason, NoteEnd.stopPhrase);
      expect(r.text, 'Call the dentist');
    });

    test('cancel phrase discards the note', () {
      final s = NoteSession(start: t0);
      final r = s.onFinal('something silly cancel note', at(1000))!;
      expect(r.reason, NoteEnd.cancelled);
      expect(r.hasNote, isFalse);
    });

    test('gives up when nothing is said', () {
      final s = NoteSession(start: t0);
      expect(s.tick(at(7000)), isNull);
      expect(s.tick(at(8000))!.reason, NoteEnd.nothingHeard);
    });

    test('stop phrase alone saves nothing', () {
      final s = NoteSession(start: t0);
      final r = s.onFinal('done', at(1000))!;
      expect(r.hasNote, isFalse);
      expect(r.reason, NoteEnd.nothingHeard);
    });

    test('caps note length', () {
      final s = NoteSession(start: t0, maxLength: const Duration(seconds: 10));
      for (var i = 1; i < 10; i++) {
        s.onPartial('talking ' * i, at(i * 1000));
      }
      final r = s.tick(at(10000))!;
      expect(r.reason, NoteEnd.maxLength);
      expect(r.text, startsWith('Talking'));
    });
  });

  group('inbox import', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('penmein_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('imports notes once, newest first, and survives a bad line', () async {
      final inbox = NoteInbox(dir.path);
      await inbox.append('first', at: DateTime(2026, 1, 1, 9));
      await inbox.append('second', at: DateTime(2026, 1, 1, 10));
      File('${dir.path}/inbox.jsonl').writeAsStringSync('not json\n', mode: FileMode.append);
      final store = NotesStore(dir.path);
      await store.load();
      expect(await store.importInbox(inbox), 2);
      expect(store.notes.map((n) => n.text), ['second', 'first']);
      expect(store.notes.first.source, NoteSource.voice);
      expect(await store.importInbox(inbox), 0);

      // Persisted: a fresh store reads the same notes back.
      final again = NotesStore(dir.path);
      await again.load();
      expect(again.notes.length, 2);
    });

    test('recovers an interrupted import', () async {
      final inbox = NoteInbox(dir.path);
      await inbox.append('a');
      await inbox.take(); // Import "crashed" before commit.
      await inbox.append('b');
      final store = NotesStore(dir.path);
      await store.load();
      expect(await store.importInbox(inbox), 2);
    });

    test('search matches every word', () async {
      final store = NotesStore(dir.path);
      await store.load();
      await store.add('Buy milk and eggs');
      await store.add('Call the dentist');
      expect(store.search('milk eggs').length, 1);
      expect(store.search('').length, 2);
      expect(store.search('milk dentist'), isEmpty);
    });
  });
}
