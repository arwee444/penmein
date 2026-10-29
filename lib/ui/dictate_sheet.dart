import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vosk_listener/vosk_listener.dart';

import '../core/note_session.dart';
import '../data/notes.dart';
import '../main.dart';
import '../services/dictation.dart';
import '../services/ios_dictation.dart';
import '../services/listen_service.dart';
import '../services/settings.dart';
import '../services/vosk_model.dart';
import '../theme.dart';
import 'common.dart';

/// In-app dictation. When background listening is on, the service takes the
/// note (it owns the mic); otherwise the app listens itself.
Future<void> showDictateSheet(BuildContext context) async {
  if (!ListenController.isSupported) {
    // iPhone: Apple's recogniser; it asks for mic + speech permission itself.
    if (!await IosDictation.requestPermission()) {
      if (context.mounted) toast(context, 'Allow the microphone and speech recognition in Settings › Pen Me In.');
      return;
    }
  } else if (!listen.isRunning) {
    if (!await ensureModel(context) || !context.mounted) return;
    if (!await VoskListener.requestPermission()) {
      if (context.mounted) toast(context, 'Pen Me In needs the microphone to hear you.');
      return;
    }
  }
  if (!context.mounted) return;
  final r = await showModalBottomSheet<NoteResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _DictateSheet(),
  );
  if (r != null && context.mounted) toast(context, r.hasNote ? 'Note saved' : endMessage(r.reason));
}

class _DictateSheet extends StatefulWidget {
  const _DictateSheet();

  @override
  State<_DictateSheet> createState() => _DictateSheetState();
}

class _DictateSheetState extends State<_DictateSheet> {
  String _live = '';
  Dictation? _local;
  IosDictation? _ios;
  final _subs = <StreamSubscription<Object?>>[];
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    if (listen.isRunning) {
      _subs.add(listen.live.listen((t) => setState(() => _live = t)));
      _subs.add(listen.ended.listen((e) => _close(NoteResult(e.$2, e.$1))));
      listen.send(Msg.dictate);
    } else if (!ListenController.isSupported) {
      _runIos();
    } else {
      _runLocal();
    }
  }

  Future<void> _runIos() async {
    final d = _ios = IosDictation(
      await VoiceSettings.load(),
      onLive: (t) {
        if (mounted) setState(() => _live = t);
      },
    );
    final r = await d.run();
    if (r.hasNote) await notes.add(r.text, source: NoteSource.voice);
    _close(r);
  }

  Future<void> _runLocal() async {
    final s = await VoiceSettings.load();
    final model = await SpeechModels.noteModel(s.modelId);
    if (model == null) return _close(const NoteResult('', NoteEnd.error));
    final d = _local = Dictation(
      s,
      whisperPath: await SpeechModels.whisperPath(s.whisperId),
      onPolishing: () {
        if (mounted) setState(() => _live = '✍ Writing it down…');
      },
      onLive: (t) {
        if (mounted) setState(() => _live = t);
      },
    );
    final r = await d.run(await SpeechModels.pathOf(model));
    try {
      await VoskListener.stop();
    } catch (_) {}
    if (r.hasNote) await notes.add(r.text, source: NoteSource.voice);
    _close(r);
  }

  void _close(NoteResult r) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, r);
  }

  void _done() {
    if (_ios != null) {
      _ios!.finishNow();
    } else if (_local != null) {
      _local!.finishNow();
    } else {
      listen.send(Msg.done);
    }
  }

  void _cancel() {
    if (_ios != null) {
      _ios!.cancel();
    } else if (_local != null) {
      _local!.cancel();
    } else {
      listen.send(Msg.cancel);
      _close(const NoteResult('', NoteEnd.cancelled));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _local?.cancel();
    _ios?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.graphic_eq, color: Pal.coral),
                SizedBox(width: 10),
                Text(
                  'Listening… speak now',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Pal.coral),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Pause or say "done" to finish.', style: TextStyle(color: Pal.fog)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80),
              child: Text(
                _live.isEmpty ? '…' : _live,
                style: TextStyle(fontSize: 17, height: 1.4, color: _live.isEmpty ? Pal.fog : Pal.paper),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: _cancel, child: const Text('Cancel')),
                const Spacer(),
                FilledButton.icon(onPressed: _done, icon: const Icon(Icons.check), label: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
