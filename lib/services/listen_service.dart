import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_listener/vosk_listener.dart';

import '../core/note_session.dart';
import '../core/phrases.dart';
import '../data/notes.dart';
import 'dictation.dart';
import 'settings.dart';
import 'vosk_model.dart';

/// Messages between the app and the service.
abstract final class Msg {
  static const dictate = 'dictate';
  static const done = 'done';
  static const cancel = 'cancel';
  static const settings = 'settings';
  static const noted = 'noted';
}

const _title = 'Pen Me In';

String endMessage(NoteEnd r) => switch (r) {
  NoteEnd.nothingHeard => "Didn't catch anything, so no note was saved.",
  NoteEnd.cancelled => 'Note cancelled.',
  NoteEnd.error => 'The microphone stopped, so no note was saved.',
  _ => 'Saved.',
};

String _preview(String s, [int max = 28]) => s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

// ----------------------------------------------------------------------------
// Background side (runs in the foreground-service isolate)

@pragma('vm:entry-point')
void listenStartCallback() {
  FlutterForegroundTask.setTaskHandler(ListenTaskHandler());
}

enum _Mode { waiting, dictating, error }

class ListenTaskHandler extends TaskHandler {
  VoiceSettings _s = const VoiceSettings();
  String? _wakePath, _notePath, _whisperPath;
  NoteInbox? _inbox;
  _Mode _mode = _Mode.waiting;
  String? _error;
  String? _status;
  StreamSubscription<VoskEvent>? _wakeSub;
  Dictation? _dict;
  bool _destroyed = false;
  int _count = 0;
  String? _last;
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLive = DateTime.fromMillisecondsSinceEpoch(0);

  static const waitingButtons = [
    NotificationButton(id: Msg.dictate, text: '✍ Note now'),
    NotificationButton(id: 'stop', text: 'Stop listening'),
  ];
  static const dictatingButtons = [
    NotificationButton(id: Msg.done, text: '✓ Done'),
    NotificationButton(id: Msg.cancel, text: '✕ Cancel'),
  ];

  String get _wake => _s.wakePhrases.first;

  Future<void> _show() {
    final String title, text;
    switch (_mode) {
      case _Mode.dictating:
        title = '$_title · 🎙 Taking a note…';
        final stop = _s.stopPhrases.isEmpty ? '' : ' or say "${_s.stopPhrases.first}"';
        text = 'Speak now. Pause to finish$stop.';
      case _Mode.error:
        title = '$_title · ⚠ Not listening';
        text = '${_error ?? 'Something went wrong'}. Open the app to fix it.';
      case _Mode.waiting:
        title = '$_title · Listening for "$_wake"';
        final counts = _count == 0
            ? 'Say "$_wake", then your note.'
            : '$_count note${_count == 1 ? '' : 's'} taken · last: "${_preview(_last ?? '')}"';
        text = _status == null ? counts : '$_status\n$counts';
    }
    return FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationButtons: _mode == _Mode.dictating ? dictatingButtons : waitingButtons,
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _s = await VoiceSettings.load();
    await _resolveModels();
    _inbox = NoteInbox((await getApplicationSupportDirectory()).path);
    await _listenForWake();
  }

  Future<void> _listenForWake() async {
    if (_destroyed) return;
    _mode = _Mode.waiting;
    final model = _wakePath;
    if (model == null) {
      _fail('No English speech model installed');
    } else if (!await VoskListener.hasPermission()) {
      _fail('No microphone permission');
    } else {
      _wakeSub ??= VoskListener.events.listen(_onWakeEvent);
      try {
        await VoskListener.start(modelPath: model, grammar: _s.wakePhrases.map(normalizeSpeech).toSet().toList());
      } catch (_) {
        _fail("Couldn't start the microphone");
      }
    }
    await _show();
  }

  void _fail(String why) {
    _mode = _Mode.error;
    _error = why;
  }

  void _onWakeEvent(VoskEvent e) {
    if (_mode != _Mode.waiting) return;
    if (e.error != null) {
      _fail('Microphone error');
      _show();
      return;
    }
    if (DateTime.now().isBefore(_cooldownUntil)) return;
    if (matchesAnyPhrase(e.text, _s.wakePhrases)) _takeNote();
  }

  Future<void> _takeNote() async {
    if (_mode == _Mode.dictating || _notePath == null) return;
    _mode = _Mode.dictating;
    _status = null;
    await _wakeSub?.cancel();
    _wakeSub = null;
    if (_s.vibrate) VoskListener.vibrate().catchError((_) {});
    await _show();
    final d = _dict = Dictation(_s, onLive: _sendLive, whisperPath: _whisperPath, onPolishing: _showPolishing);
    final r = await d.run(_notePath!);
    _dict = null;
    if (_destroyed) return;
    if (r.hasNote) {
      await _inbox!.append(r.text);
      _count++;
      _last = r.text;
      FlutterForegroundTask.sendDataToMain(Msg.noted);
      if (_s.vibrate) VoskListener.vibrate().catchError((_) {});
    } else {
      _status = endMessage(r.reason);
    }
    FlutterForegroundTask.sendDataToMain({'ended': r.reason.name, 'text': r.text});
    _cooldownUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    await _listenForWake();
  }

  void _showPolishing() {
    FlutterForegroundTask.updateService(
      notificationTitle: '$_title · ✍ Writing it down…',
      notificationText: 'Making the note accurate. A few seconds.',
      notificationButtons: waitingButtons,
    );
    FlutterForegroundTask.sendDataToMain({'live': '✍ Writing it down…'});
  }

  void _sendLive(String text) {
    final now = DateTime.now();
    if (now.difference(_lastLive) < const Duration(milliseconds: 200)) return;
    _lastLive = now;
    FlutterForegroundTask.sendDataToMain({'live': text});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _destroyed = true;
    _dict?.cancel();
    await _wakeSub?.cancel();
    try {
      await VoskListener.stop();
    } catch (_) {}
  }

  @override
  void onReceiveData(Object data) {
    switch (data) {
      case Msg.dictate:
        _takeNote();
      case Msg.done:
        _dict?.finishNow();
      case Msg.cancel:
        _dict?.cancel();
      case Msg.settings:
        _reloadSettings();
    }
  }

  Future<void> _reloadSettings() async {
    _s = await VoiceSettings.load();
    if (_mode == _Mode.dictating) return;
    // Free the old models (the note model may have changed), then reload.
    await _wakeSub?.cancel();
    _wakeSub = null;
    try {
      await VoskListener.stop();
    } catch (_) {}
    await _resolveModels();
    await _listenForWake();
  }

  Future<void> _resolveModels() async {
    final w = await SpeechModels.wakeModel(_s.modelId);
    final n = await SpeechModels.noteModel(_s.modelId);
    _wakePath = w == null ? null : await SpeechModels.pathOf(w);
    _notePath = n == null ? null : await SpeechModels.pathOf(n);
    _whisperPath = await SpeechModels.whisperPath(_s.whisperId);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    } else {
      onReceiveData(id);
    }
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

// ----------------------------------------------------------------------------
// App side

enum StartResult { started, needsModel, needsMicrophone, needsNotifications, failed, unsupported }

/// Turns background listening on/off and relays the service's messages.
class ListenController extends ChangeNotifier {
  ListenController() {
    if (!isSupported) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'listening',
        channelName: 'Listening',
        channelDescription: 'Shows when Pen Me In is listening for your wake phrase',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.HIGH,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        autoRunOnBoot: false,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    refresh();
  }

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _running = false;
  bool get isRunning => _running;

  /// Why the last start failed (shown to help diagnose).
  String? lastError;

  /// A note was saved to the inbox.
  void Function()? onNoted;

  final _live = StreamController<String>.broadcast();
  final _ended = StreamController<(NoteEnd, String)>.broadcast();

  /// Live text of a note the service is taking.
  Stream<String> get live => _live.stream;

  /// The service finished a note (reason, text).
  Stream<(NoteEnd, String)> get ended => _ended.stream;

  void _onTaskData(Object data) {
    if (data == Msg.noted) {
      onNoted?.call();
    } else if (data is Map) {
      if (data['live'] is String) _live.add(data['live'] as String);
      if (data['ended'] is String) {
        final r = NoteEnd.values.firstWhere((e) => e.name == data['ended'], orElse: () => NoteEnd.error);
        _ended.add((r, (data['text'] as String?) ?? ''));
      }
    }
  }

  Future<void> refresh() async {
    if (!isSupported) return;
    final r = await FlutterForegroundTask.isRunningService;
    if (r != _running) {
      _running = r;
      notifyListeners();
    }
  }

  Future<StartResult> start() async {
    if (!isSupported) return StartResult.unsupported;
    if (await SpeechModels.wakeModel((await VoiceSettings.load()).modelId) == null) return StartResult.needsModel;
    if (!await VoskListener.requestPermission()) return StartResult.needsMicrophone;
    var n = await FlutterForegroundTask.checkNotificationPermission();
    if (n != NotificationPermission.granted) n = await FlutterForegroundTask.requestNotificationPermission();
    if (n != NotificationPermission.granted) return StartResult.needsNotifications;
    lastError = null;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
      final res = await FlutterForegroundTask.startService(
        serviceId: 5151,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: '$_title · Starting…',
        notificationText: 'Loading the speech model.',
        notificationButtons: ListenTaskHandler.waitingButtons,
        callback: listenStartCallback,
      );
      if (res is ServiceRequestFailure) lastError = res.error.toString();
      await refresh();
      return res is ServiceRequestSuccess && _running ? StartResult.started : StartResult.failed;
    } catch (e) {
      lastError = e.toString();
      await refresh();
      return StartResult.failed;
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await FlutterForegroundTask.stopService();
    await refresh();
  }

  /// Tell a running service to reload settings (it restarts its recogniser).
  void pushSettings() {
    if (_running) FlutterForegroundTask.sendDataToTask(Msg.settings);
  }

  void send(String msg) {
    if (_running) FlutterForegroundTask.sendDataToTask(msg);
  }

  @override
  void dispose() {
    if (isSupported) FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _live.close();
    _ended.close();
    super.dispose();
  }
}
