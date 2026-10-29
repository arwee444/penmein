import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// Rewrites a finished note from its recorded audio with Whisper
/// (whisper.cpp, offline). Works in the background service's isolate too.
abstract final class WhisperNotes {
  static WhisperEngine? _engine;
  static String? _path;

  /// [pcm16] is 16 kHz mono PCM16 little-endian. [language] is what the user
  /// speaks ('auto' to detect); anything but English is translated to English.
  static Future<String?> transcribe(String modelPath, Uint8List pcm16, {String language = 'en'}) async {
    if (pcm16.length < 16000) return null; // Under half a second: nothing to do.
    if (_engine == null || _path != modelPath) {
      _engine?.dispose();
      _engine = null;
      _engine = await WhisperEngine.load(modelPath);
      _path = modelPath;
    }
    final data = ByteData.sublistView(pcm16);
    final samples = Float32List(pcm16.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    final result = await _engine!
        .transcribe(samples, options: TranscribeOptions(language: language, translate: language != 'en'))
        .result;
    return result.text;
  }
}
