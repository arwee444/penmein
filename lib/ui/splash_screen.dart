import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_mark.dart';
import 'arwee.dart';

/// Opening screen (same layout as Save This Spot): the Pen Me In mark exactly
/// centred, the Arwee parent-company credit in the upper middle.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, _, _) => widget.next,
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1500),
        builder: (context, t, _) {
          final fade = Curves.easeOut.transform((t / 0.4).clamp(0, 1));
          // A small "hello" tilt from the robot once everything has faded in.
          final tilt = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, -0.56),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.rotate(
                        angle: 0.12 * math.sin(tilt * 2 * math.pi) * (1 - tilt),
                        alignment: Alignment.bottomCenter,
                        child: Image.asset('assets/arwee_robot.png', height: 42, filterQuality: FilterQuality.medium),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'from the house of',
                        style: TextStyle(color: Pal.fog, fontSize: 10, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 5),
                      const ArweeWordmark(height: 21, opacity: 1, shimmer: false),
                    ],
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - fade)),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppMark(size: 96),
                        SizedBox(height: 20),
                        Text(
                          'Pen Me In',
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Pal.paper),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Say it. It\'s written.',
                          style: TextStyle(fontSize: 16, color: Pal.gold, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
