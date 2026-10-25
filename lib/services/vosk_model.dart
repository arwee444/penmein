import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_listener/vosk_listener.dart';

enum VoskModelState { unknown, missing, downloading, unpacking, ready, failed }

/// The offline English speech model (~40 MB), downloaded once on demand.
class VoskModelManager extends ChangeNotifier {
  VoskModelManager._();
  static final instance = VoskModelManager._();

  static const name = 'vosk-model-small-en-us-0.15';
  static const url = 'https://alphacephei.com/vosk/models/$name.zip';

  VoskModelState state = VoskModelState.unknown;
  double progress = 0;
  String? error;

  static Future<Directory> _root() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'vosk'));

  /// Folder of the unpacked model.
  static Future<String> modelPath() async => p.join((await _root()).path, name);

  static Future<bool> isInstalled() async => isInstalledAt(await modelPath());

  static Future<bool> isInstalledAt(String path) async => File(p.join(path, 'am', 'final.mdl')).existsSync();

  Future<void> check() async {
    if (state == VoskModelState.downloading || state == VoskModelState.unpacking) return;
    _set(await isInstalled() ? VoskModelState.ready : VoskModelState.missing);
  }

  Future<void> download() async {
    if (state == VoskModelState.downloading || state == VoskModelState.unpacking) return;
    error = null;
    progress = 0;
    _set(VoskModelState.downloading);
    final client = http.Client();
    try {
      final root = await _root();
      await root.create(recursive: true);
      final zip = File(p.join(root.path, '$name.zip'));
      final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
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
            if (next - progress >= 0.01 || next == 1) {
              progress = next;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw const HttpException('Download was cut off');
      _set(VoskModelState.unpacking);
      final dest = Directory(await modelPath());
      if (dest.existsSync()) await dest.delete(recursive: true);
      await VoskListener.unzip(zip.path, root.path);
      await zip.delete();
      if (!await isInstalled()) throw const FileSystemException('Model files missing after unpacking');
      _set(VoskModelState.ready);
    } catch (e) {
      error = e is TimeoutException ? 'The connection timed out.' : 'Download failed (${e.runtimeType}).';
      debugPrint('Vosk model download failed: $e');
      _set(VoskModelState.failed);
    } finally {
      client.close();
    }
  }

  void _set(VoskModelState s) {
    state = s;
    notifyListeners();
  }
}
