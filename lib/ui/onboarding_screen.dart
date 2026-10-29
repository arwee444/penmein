import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:vosk_listener/vosk_listener.dart';

import '../main.dart';
import '../services/vosk_model.dart';
import '../theme.dart';
import 'app_mark.dart';
import 'arwee.dart';
import 'common.dart';
import 'home_screen.dart';

/// First run: explain, then ask for each permission in turn.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _mic = false, _notif = false, _model = false, _battery = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final mic = await VoskListener.hasPermission();
    final notif = await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;
    final model = await SpeechModels.noteModel('en-us') != null;
    final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!mounted) return;
    setState(() {
      _mic = mic;
      _notif = notif;
      _model = model;
      _battery = battery;
    });
  }

  Future<void> _finish() async {
    await FlutterForegroundTask.saveData(key: onboardedKey, value: true);
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  Widget _step(int n, String title, String body, bool done, VoidCallback onTap, String action) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: done ? Pal.gold : Pal.raised,
            child: done
                ? const Icon(Icons.check, size: 16, color: Pal.background)
                : Text('$n', style: const TextStyle(color: Pal.paper, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: Pal.fog, height: 1.3)),
                if (!done) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onTap, child: Text(action)),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: EdgeInsets.only(top: 12), child: AppMark(size: 56)),
                Spacer(),
                ArweeWordmark(height: 22),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Pen Me In', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Say "pen me in", even with your phone locked, then say your note. '
              'It is written down here. Speech is recognised offline, on your phone.',
              style: TextStyle(color: Pal.fog, height: 1.4),
            ),
            const SizedBox(height: 20),
            _step(1, 'Microphone', 'To hear your wake phrase and your notes.', _mic, () async {
              await VoskListener.requestPermission();
              _check();
            }, 'Allow microphone'),
            const SizedBox(height: 10),
            _step(2, 'Notifications', 'Shows when it is listening, with Done/Cancel buttons on the lock screen.', _notif, () async {
              await FlutterForegroundTask.requestNotificationPermission();
              _check();
            }, 'Allow notifications'),
            const SizedBox(height: 10),
            _step(3, 'Speech model', 'One-time download, about 40 MB, from alphacephei.com.', _model, () async {
              await ensureModel(context);
              _check();
            }, 'Download'),
            const SizedBox(height: 10),
            _step(4, 'Keep running', 'Lets it keep listening with the screen off.\n\n$samsungTip', _battery, () async {
              await askBatteryExemption();
              _check();
            }, 'Allow'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _finish,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(_mic && _notif && _model ? 'Start' : 'Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
