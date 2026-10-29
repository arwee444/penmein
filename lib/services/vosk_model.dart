import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_listener/vosk_listener.dart';

/// An offline Vosk speech model the user can install from alphacephei.com.
class SpeechModel {
  const SpeechModel(this.id, this.dir, this.label, this.detail, this.sizeMb, {this.english = true, this.whisper = false});

  final String id;

  /// Folder name inside the zip (and the zip's base name).
  final String dir;
  final String label;
  final String detail;
  final int sizeMb;

  /// English models can also listen for the wake phrase.
  final bool english;

  /// A Whisper model (one .bin file) that rewrites finished notes, rather than
  /// a Vosk model that listens live.
  final bool whisper;

  String get url => whisper
      ? 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$dir'
      : 'https://alphacephei.com/vosk/models/$dir.zip';
}

const speechModels = [
  SpeechModel('en-us', 'vosk-model-small-en-us-0.15', 'English · standard', 'Small and quick. Trained mostly on US speech.', 40),
  SpeechModel(
    'en-us-accurate',
    'vosk-model-en-us-0.22-lgraph',
    'English · accurate',
    'Noticeably better at words and sentences, including UK, Australian and Indian accents. Loads a little slower.',
    128,
  ),
  SpeechModel('en-in', 'vosk-model-small-en-in-0.4', 'English (India)', 'Trained on Indian English.', 36),
  SpeechModel(
    'hi',
    'vosk-model-small-hi-0.22',
    'Hindi · हिन्दी',
    'Notes are written in Devanagari. The wake phrase still uses an English model. '
        '"done" won\'t be understood, so pause to finish (or add a Hindi stop word).',
    42,
    english: false,
  ),
];

/// Whisper models (whisper.cpp, quantised). Multilingual, so Hindi, Tamil and
/// Kannada speech can be written in English.
const whisperModels = [
  SpeechModel(
    'whisper-base',
    'ggml-base-q5_1.bin',
    'Whisper · base',
    'Much more accurate than the live models. Takes a couple of seconds after you finish.',
    57,
    english: false,
    whisper: true,
  ),
  SpeechModel(
    'whisper-small',
    'ggml-small-q5_1.bin',
    'Whisper · small',
    'The most accurate, best for accents and other languages. Takes a few seconds longer.',
    181,
    english: false,
    whisper: true,
  ),
];

SpeechModel? modelById(String id) {
  for (final m in [...speechModels, ...whisperModels]) {
    if (m.id == id) return m;
  }
  return null;
}

enum ModelState { missing, downloading, unpacking, ready, failed }

/// Installs and removes speech models, one download at a time.
class SpeechModels extends ChangeNotifier {
  SpeechModels._();
  static final instance = SpeechModels._();

  final _state = <String, ModelState>{};
  final _progress = <String, double>{};
  final _error = <String, String>{};

  ModelState state(SpeechModel m) => _state[m.id] ?? ModelState.missing;
  double progress(SpeechModel m) => _progress[m.id] ?? 0;
  String? error(SpeechModel m) => _error[m.id];
  bool get busy => _state.values.any((s) => s == ModelState.downloading || s == ModelState.unpacking);

  static Future<Directory> _root() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'vosk'));

  static Future<String> pathOf(SpeechModel m) async =>
      m.whisper ? p.join((await _root()).path, 'whisper', m.dir) : p.join((await _root()).path, m.dir);

  static Future<bool> isInstalled(SpeechModel m) async {
    final d = await pathOf(m);
    if (m.whisper) return File(d).existsSync();
    return File(p.join(d, '.installed')).existsSync() || File(p.join(d, 'am', 'final.mdl')).existsSync();
  }

  /// The model that writes notes: the chosen one if installed, otherwise the
  /// first installed model.
  static Future<SpeechModel?> noteModel(String chosenId) async {
    final chosen = modelById(chosenId);
    if (chosen != null && await isInstalled(chosen)) return chosen;
    for (final m in speechModels) {
      if (await isInstalled(m)) return m;
    }
    return null;
  }

  /// The model that listens for the wake phrase: the note model if it is
  /// English (one model = less memory), otherwise any installed English one.
  static Future<SpeechModel?> wakeModel(String chosenId) async {
    final note = await noteModel(chosenId);
    if (note != null && note.english) return note;
    for (final m in speechModels.where((m) => m.english)) {
      if (await isInstalled(m)) return m;
    }
    return null;
  }

  /// Path of the chosen Whisper model, or null when off or not installed.
  static Future<String?> whisperPath(String id) async {
    final m = modelById(id);
    if (m == null || !m.whisper || !await isInstalled(m)) return null;
    return pathOf(m);
  }

  Future<void> check() async {
    for (final m in [...speechModels, ...whisperModels]) {
      final s = state(m);
      if (s == ModelState.downloading || s == ModelState.unpacking) continue;
      _state[m.id] = await isInstalled(m) ? ModelState.ready : ModelState.missing;
    }
    notifyListeners();
  }

  Future<void> delete(SpeechModel m) async {
    if (busy) return;
    final path = await pathOf(m);
    if (m.whisper) {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } else {
      final d = Directory(path);
      if (d.existsSync()) await d.delete(recursive: true);
    }
    _set(m, ModelState.missing);
  }

  Future<void> download(SpeechModel m) async {
    if (busy) return;
    _error.remove(m.id);
    _progress[m.id] = 0;
    _set(m, ModelState.downloading);
    final client = http.Client();
    try {
      final root = await _root();
      await root.create(recursive: true);
      if (m.whisper) await Directory(p.join(root.path, 'whisper')).create(recursive: true);
      final zip = File(m.whisper ? '${await pathOf(m)}.part' : p.join(root.path, '${m.dir}.zip'));
      final res = await client.send(http.Request('GET', Uri.parse(m.url))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = zip.openWrite();
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final next = got / total;
            if (next - progress(m) >= 0.01 || next == 1) {
              _progress[m.id] = next;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw const HttpException('Download was cut off');
      if (m.whisper) {
        await zip.rename(await pathOf(m));
        _set(m, ModelState.ready);
        return;
      }
      _set(m, ModelState.unpacking);
      final dest = Directory(await pathOf(m));
      if (dest.existsSync()) await dest.delete(recursive: true);
      await VoskListener.unzip(zip.path, root.path);
      await zip.delete();
      if (!dest.existsSync()) throw const FileSystemException('Model folder missing after unpacking');
      await File(p.join(dest.path, '.installed')).writeAsString('ok');
      _set(m, ModelState.ready);
    } catch (e) {
      _error[m.id] = e is TimeoutException ? 'The connection timed out.' : 'Download failed (${e.runtimeType}).';
      debugPrint('Speech model download failed: $e');
      _set(m, ModelState.failed);
    } finally {
      client.close();
    }
  }

  void _set(SpeechModel m, ModelState s) {
    _state[m.id] = s;
    notifyListeners();
  }
}
