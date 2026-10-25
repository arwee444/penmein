import 'package:flutter/material.dart';

import '../theme.dart';

/// The Pen Me In mark: a pen nib with voice waves ("Talking nib").
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const NibPainter());
}

/// Draws the mark in a square. Designed on a 130-unit grid.
/// [background] paints the rounded ink tile; [scale] shrinks the drawing
/// toward the centre (Android adaptive icons need a safe margin).
class NibPainter extends CustomPainter {
  const NibPainter({this.background = true, this.scale = 1});

  final bool background;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 130;
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(28 * s)),
        Paint()..color = Pal.background,
      );
    }
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s * scale)
      ..translate(-65, -65);
    final nib = Path()
      ..moveTo(65, 22)
      ..cubicTo(85, 35, 92, 55, 85, 72)
      ..lineTo(65, 110)
      ..lineTo(45, 72)
      ..cubicTo(38, 55, 45, 35, 65, 22)
      ..close();
    canvas.drawPath(nib, Paint()..color = Pal.teal);
    final cut = Paint()
      ..color = Pal.background
      ..strokeWidth = 3;
    canvas
      ..drawLine(const Offset(65, 60), const Offset(65, 106), cut)
      ..drawCircle(const Offset(65, 57), 5, cut);
    final wave = Paint()
      ..color = Pal.coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final (x, dx, h) in [(98.0, 9.0, 15.0), (109.0, 13.0, 24.0)]) {
      for (final side in [1, -1]) {
        final x0 = 65 + side * (x - 65);
        canvas.drawPath(
          Path()
            ..moveTo(x0, 65 - h)
            ..quadraticBezierTo(x0 + side * dx, 65, x0, 65 + h),
          wave,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NibPainter old) => old.background != background || old.scale != scale;
}
