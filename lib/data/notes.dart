import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum NoteSource { voice, typed }

class Note {
  Note({required this.id, required this.text, required this.created, DateTime? updated, this.source = NoteSource.typed})
    : updated = updated ?? created;

  final String id;
  String text;
  final DateTime created;
  DateTime updated;
  final NoteSource source;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'created': created.toUtc().toIso8601String(),
    'updated': updated.toUtc().toIso8601String(),
    'source': source.name,
  };

  static Note fromJson(Map<String, dynamic> m) => Note(
    id: m['id'] as String,
    text: (m['text'] as String?) ?? '',
    created: DateTime.parse(m['created'] as String).toLocal(),
    updated: m['updated'] == null ? null : DateTime.parse(m['updated'] as String).toLocal(),
    source: m['source'] == 'voice' ? NoteSource.voice : NoteSource.typed,
  );
}

final _rand = Random();
String newNoteId() => '${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 32).toRadixString(16)}';

/// Notes taken by the background service. The service never writes the notes
/// file (two isolates writing one file would corrupt it): it appends one JSON
/// line per note here, and the app imports the inbox. Import renames the file
/// first, so a note dropped mid-import lands in a fresh inbox and isn't lost.
class NoteInbox {
  NoteInbox(this.dir);

  final String dir;

  File get _file => File(p.join(dir, 'inbox.jsonl'));
  File get _working => File(p.join(dir, 'inbox.importing.jsonl'));

  Future<void> append(String text, {DateTime? at}) async {
    await Directory(dir).create(recursive: true);
    final entry = {'id': newNoteId(), 'text': text, 't': (at ?? DateTime.now()).toUtc().toIso8601String()};
    await _file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append, flush: true);
  }

  /// Takes all pending entries. Call [commit] once they are safely stored.
  Future<List<Note>> take() async {
    final f = _file, working = _working;
    if (f.existsSync()) {
      if (working.existsSync()) {
        // A previous import was interrupted: merge it in first.
        await working.writeAsString(await f.readAsString(), mode: FileMode.append, flush: true);
        await f.delete();
      } else {
        await f.rename(working.path);
      }
    }
    if (!working.existsSync()) return [];
    final out = <Note>[];
    for (final line in await working.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        out.add(
          Note(
            id: m['id'] as String,
            text: m['text'] as String,
            created: DateTime.parse(m['t'] as String).toLocal(),
            source: NoteSource.voice,
          ),
        );
      } catch (e) {
        debugPrint('Skipped a malformed inbox line: ${e.runtimeType}');
      }
    }
    return out;
  }

  Future<void> commit() async {
    if (_working.existsSync()) await _working.delete();
  }
}

/// All notes, kept in one JSON file. Only the UI isolate touches it.
class NotesStore extends ChangeNotifier {
  NotesStore(this.dir);

  final String dir;
  final List<Note> _notes = [];

  File get _file => File(p.join(dir, 'notes.json'));

  /// Newest first.
  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    _notes.clear();
    if (_file.existsSync()) {
      try {
        final list = jsonDecode(await _file.readAsString()) as List;
        _notes.addAll(list.map((e) => Note.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        // Keep the unreadable file for recovery instead of overwriting it.
        await _file.copy(p.join(dir, 'notes.broken.${DateTime.now().millisecondsSinceEpoch}.json'));
      }
    }
    _sort();
    notifyListeners();
  }

  Future<void> _save() async {
    await Directory(dir).create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_notes.map((n) => n.toJson()).toList()), flush: true);
    await tmp.rename(_file.path);
  }

  void _sort() => _notes.sort((a, b) => b.created.compareTo(a.created));

  Note? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<Note> add(String text, {NoteSource source = NoteSource.typed}) async {
    final n = Note(id: newNoteId(), text: text, created: DateTime.now(), source: source);
    _notes.add(n);
    _sort();
    await _save();
    notifyListeners();
    return n;
  }

  Future<void> update(Note n, String text) async {
    if (n.text == text) return;
    n.text = text;
    n.updated = DateTime.now();
    await _save();
    notifyListeners();
  }

  Future<void> delete(Note n) async {
    _notes.removeWhere((e) => e.id == n.id);
    await _save();
    notifyListeners();
  }

  Future<void> restore(Note n) async {
    if (byId(n.id) != null) return;
    _notes.add(n);
    _sort();
    await _save();
    notifyListeners();
  }

  /// Pulls in notes from [inbox]. Returns how many were new.
  Future<int> importInbox(NoteInbox inbox) async {
    final incoming = await inbox.take();
    var added = 0;
    for (final n in incoming) {
      if (byId(n.id) != null || n.text.trim().isEmpty) continue;
      _notes.add(n);
      added++;
    }
    if (added > 0) {
      _sort();
      await _save();
      notifyListeners();
    }
    await inbox.commit();
    return added;
  }

  /// Notes whose text contains every word of [query].
  List<Note> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return notes;
    return _notes.where((n) {
      final t = n.text.toLowerCase();
      return words.every(t.contains);
    }).toList();
  }
}
