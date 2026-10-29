import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:penmein/data/notes.dart';
import 'package:penmein/main.dart';
import 'package:penmein/services/listen_service.dart';
import 'package:penmein/theme.dart';
import 'package:penmein/ui/home_screen.dart';
import 'package:penmein/ui/onboarding_screen.dart';
import 'package:penmein/ui/settings_screen.dart';
import 'package:penmein/ui/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// Phone-sized previews with real fonts and sample notes:
/// SHOTS=out\dir flutter test test\render_screens_test.dart
void main() {
  final out = Platform.environment['SHOTS'];

  testWidgets('render screen previews', skip: out == null, (t) async {
    final tmp = Directory.systemTemp.createTempSync('pm_shots');
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _Paths(tmp.path);
    for (final ch in ['flutter_foreground_task/methods', 'pinnocate/vosk']) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(ch),
        (c) async => c.method == 'checkNotificationPermission'
            ? 1
            : c.method.startsWith('is') || c.method == 'hasPermission'
            ? false
            : null,
      );
    }
    await t.runAsync(() async {
      const fonts = r'C:\dev\flutter\bin\cache\artifacts\material_fonts';
      final roboto = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        roboto.addFont(Future.value(ByteData.sublistView(File('$fonts\\roboto-$f.ttf').readAsBytesSync())));
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(File('$fonts\\materialicons-regular.otf').readAsBytesSync())));
      await icons.load();

      notes = NotesStore(tmp.path);
      await notes.load();
      for (final (text, voice) in [
        ('So the last time I was thinking about something, it was generally about nothing', true),
        ('Megan: users can track each others\' live location for a custom time', true),
        ('We will explain why we are doing real lighting on product', false),
        ('Prop list: torch, tripod, white card', false),
        ('Buy milk and eggs on the way home', true),
      ]) {
        await notes.add(text, source: voice ? NoteSource.voice : NoteSource.typed);
      }
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS; // No service calls.
    listen = ListenController();
    debugDefaultTargetPlatformOverride = null;

    await t.binding.setSurfaceSize(const Size(412, 915));
    Future<void> shot(String name, Widget screen, {double height = 915}) async {
      await t.binding.setSurfaceSize(Size(412, height));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(name), // Fresh navigator per screen.
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: RepaintBoundary(key: key, child: screen),
        ),
      );
      await t.runAsync(() async {
        for (final a in ['assets/arwee_robot.png', 'assets/arwee_wordmark.png']) {
          await precacheImage(AssetImage(a), key.currentContext!);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('1_loading', const SplashScreen(next: SizedBox()));
    await t.pump(const Duration(seconds: 3));
    await shot('2_notes', const HomeScreen());
    await shot('3_settings', const SettingsScreen(), height: 1900);
    await shot('4_first_run', const OnboardingScreen());
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}
