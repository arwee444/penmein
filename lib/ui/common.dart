import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/listen_service.dart';
import '../services/vosk_model.dart';
import '../theme.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String formatWhen(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = DateFormat('h:mm a').format(t);
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
  if (t.year == now.year) return '${DateFormat('d MMM').format(t)}, $time';
  return '${DateFormat('d MMM y').format(t)}, $time';
}

const samsungTip =
    'Samsung: Settings › Apps › Pen Me In › Battery › choose "Unrestricted". '
    'Otherwise the phone may stop listening after a while with the screen off.';

Future<void> askBatteryExemption() async {
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}

/// Downloads the speech model with a progress dialog. Returns true when ready.
Future<bool> ensureModel(BuildContext context) async {
  final m = VoskModelManager.instance;
  await m.check();
  if (m.state == VoskModelState.ready) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Download speech model?'),
      content: const Text(
        'Pen Me In understands speech offline, on your phone. It needs a one-time '
        'download of the English model (about 40 MB) from alphacephei.com. Wi-Fi recommended.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Download')),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  m.download();
  var closed = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => ListenableBuilder(
      listenable: m,
      builder: (c, _) {
        if (m.state == VoskModelState.ready && !closed) {
          closed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.mounted) Navigator.pop(c, true);
          });
        }
        final failed = m.state == VoskModelState.failed;
        return AlertDialog(
          title: Text(failed ? 'Download failed' : 'Getting the speech model…'),
          content: failed
              ? Text(m.error ?? 'Please try again.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: m.state == VoskModelState.downloading ? m.progress : null),
                    const SizedBox(height: 12),
                    Text(
                      m.state == VoskModelState.unpacking ? 'Unpacking…' : '${(m.progress * 100).round()}% of ~40 MB',
                      style: const TextStyle(color: Pal.fog),
                    ),
                  ],
                ),
          actions: [
            if (failed) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Close')),
            if (failed) FilledButton(onPressed: m.download, child: const Text('Retry')),
          ],
        );
      },
    ),
  );
  return ok == true;
}

/// Turns listening on, explaining whatever stands in the way.
Future<void> turnListeningOn(BuildContext context) async {
  if (!await ensureModel(context) || !context.mounted) return;
  final r = await listen.start();
  if (!context.mounted) return;
  switch (r) {
    case StartResult.started:
      toast(context, 'Listening. Lock your phone and say your wake phrase.');
    case StartResult.needsModel:
      toast(context, 'The speech model is missing. Try again.');
    case StartResult.needsMicrophone:
      toast(context, 'Pen Me In needs the microphone to hear you. Allow it in app settings.');
    case StartResult.needsNotifications:
      toast(context, 'Allow notifications so you can see when it is listening.');
    case StartResult.failed:
      toast(context, "Couldn't start listening${listen.lastError == null ? '' : ': ${listen.lastError}'}");
    case StartResult.unsupported:
      toast(context, 'Listening works on Android only.');
  }
}
