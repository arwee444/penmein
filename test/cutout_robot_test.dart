import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// One-off tool: cuts the Arwee robot out of the white-background logo.
/// SRC=logo.webp OUT=assets/arwee_robot.png flutter test test\cutout_robot_test.dart
/// Optional CROP=x,y,w,h (source pixels).
void main() {
  testWidgets('cut out robot', skip: Platform.environment['SRC'] == null, (t) async {
    await t.runAsync(() async {
      final env = Platform.environment;
      final codec = await ui.instantiateImageCodec(File(env['SRC']!).readAsBytesSync());
      final src = (await codec.getNextFrame()).image;
      final c = (env['CROP'] ?? '0,0,${src.width},${src.height}').split(',').map(int.parse).toList();
      final (cx, cy, w, h) = (c[0], c[1], c[2], c[3]);
      final all = (await src.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        px.setRange(y * w * 4, (y + 1) * w * 4, all, ((cy + y) * src.width + cx) * 4);
      }
      // Background = light, grey-ish pixels connected to the border (white
      // backdrop and its soft shadow). Highlights inside the robot are
      // enclosed by colour, so the flood never reaches them.
      bool bg(int i) {
        final r = px[i], g = px[i + 1], b = px[i + 2];
        final mx = [r, g, b].reduce((a, b) => a > b ? a : b), mn = [r, g, b].reduce((a, b) => a < b ? a : b);
        return mn > 140 && mx - mn < 40;
      }

      final seen = Uint8List(w * h);
      final stack = <int>[];
      for (var x = 0; x < w; x++) {
        stack
          ..add(x)
          ..add((h - 1) * w + x);
      }
      for (var y = 0; y < h; y++) {
        stack
          ..add(y * w)
          ..add(y * w + w - 1);
      }
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        if (seen[p] == 1 || !bg(p * 4)) continue;
        seen[p] = 1;
        px[p * 4 + 3] = 0;
        final x = p % w, y = p ~/ w;
        if (x > 0) stack.add(p - 1);
        if (x < w - 1) stack.add(p + 1);
        if (y > 0) stack.add(p - w);
        if (y < h - 1) stack.add(p + w);
      }
      // Soften the edge: kept pixels next to removed ones fade by lightness.
      for (var p = 0; p < w * h; p++) {
        if (seen[p] == 1) continue;
        final x = p % w, y = p ~/ w;
        final edge = (x > 0 && seen[p - 1] == 1) || (x < w - 1 && seen[p + 1] == 1) ||
            (y > 0 && seen[p - w] == 1) || (y < h - 1 && seen[p + w] == 1);
        if (!edge) continue;
        final i = p * 4;
        final mn = [px[i], px[i + 1], px[i + 2]].reduce((a, b) => a < b ? a : b);
        px[i + 3] = (255 - mn).clamp(90, 255);
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
      final out = await (await done.future).toByteData(format: ui.ImageByteFormat.png);
      File(env['OUT']!).writeAsBytesSync(out!.buffer.asUint8List());
    });
  });
}
