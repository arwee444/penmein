import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penmein/theme.dart';
import 'package:penmein/ui/app_mark.dart';

/// Regenerates the launcher icons from [NibPainter]:
/// ICONS=1 flutter test test\render_icons_test.dart
void main() {
  Future<void> render(String path, int px, NibPainter p) async {
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), Size.square(px.toDouble()));
    final img = await rec.endRecording().toImage(px, px);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('render launcher icons', skip: Platform.environment['ICONS'] == null, (t) async {
    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    await t.runAsync(() async {
      for (final e in densities.entries) {
        // Legacy icon: 48dp tile. Adaptive foreground: 108dp, mark in the safe zone.
        await render('$res/mipmap-${e.key}/ic_launcher.png', (48 * e.value).round(), const NibPainter());
        await render(
          '$res/mipmap-${e.key}/ic_launcher_foreground.png',
          (108 * e.value).round(),
          const NibPainter(background: false, scale: 0.62),
        );
      }
      await render('build/icon_preview.png', 512, const NibPainter());
      // iOS: full-bleed square (iOS rounds the corners itself), same mark
      // scale as the Android tile. Resized + flattened to 24-bit in PowerShell.
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = Pal.background);
      const NibPainter(background: false).paint(canvas, const Size.square(1024));
      final img = await rec.endRecording().toImage(1024, 1024);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/ios_icon_1024.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
