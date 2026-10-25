import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penmein/theme.dart';
import 'package:penmein/ui/splash_screen.dart';

void main() {
  // Preview only: OUT=path\to\file.png flutter test test\render_splash_test.dart
  testWidgets('render splash preview', skip: Platform.environment['OUT'] == null, (t) async {
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(400, 800));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: RepaintBoundary(key: key, child: const SplashScreen(next: SizedBox())),
      ),
    );
    await t.runAsync(() async {
      await precacheImage(const AssetImage('assets/arwee_robot.png'), key.currentContext!);
    });
    await t.pump(const Duration(milliseconds: 900));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(Platform.environment['OUT']!).writeAsBytesSync(png!.buffer.asUint8List());
    });
    await t.pump(const Duration(seconds: 2));
  });
}
