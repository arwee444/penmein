import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import 'data/notes.dart';
import 'services/listen_service.dart';
import 'theme.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';

late final NotesStore notes;
late final NoteInbox inbox;
late final ListenController listen;

const onboardedKey = 'pm_onboarded';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  final dir = (await getApplicationSupportDirectory()).path;
  notes = NotesStore(dir);
  inbox = NoteInbox(dir);
  await notes.load();
  await notes.importInbox(inbox);
  listen = ListenController();
  listen.onNoted = () => notes.importInbox(inbox);
  final onboarded = (await FlutterForegroundTask.getData<bool>(key: onboardedKey)) ?? false;
  runApp(PenMeInApp(onboarded: onboarded));
}

class PenMeInApp extends StatefulWidget {
  const PenMeInApp({super.key, required this.onboarded});

  final bool onboarded;

  @override
  State<PenMeInApp> createState() => _PenMeInAppState();
}

class _PenMeInAppState extends State<PenMeInApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      notes.importInbox(inbox);
      listen.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => WithForegroundTask(
    child: MaterialApp(
      title: 'Pen Me In',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: widget.onboarded ? const HomeScreen() : const OnboardingScreen(),
    ),
  );
}
