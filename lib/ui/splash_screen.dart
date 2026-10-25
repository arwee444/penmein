import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_mark.dart';

/// Opening screen: the Pen Me In mark up front, the Arwee robot quietly underneath.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

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
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _anim, curve: const Interval(0, 0.45, curve: Curves.easeOut));
    // A small "hello" tilt from the robot once everything has faded in.
    final tilt = CurvedAnimation(parent: _anim, curve: const Interval(0.45, 1));
    return Scaffold(
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: FadeTransition(
            opacity: fade,
            child: Column(
              children: [
                const Spacer(flex: 3),
                const AppMark(size: 104),
                const SizedBox(height: 20),
                const Text('Pen Me In', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Pal.paper)),
                const SizedBox(height: 6),
                const Text('Say it. It\'s written.', style: TextStyle(color: Pal.fog, fontSize: 15)),
                const Spacer(flex: 4),
                AnimatedBuilder(
                  animation: tilt,
                  builder: (_, child) => Transform.rotate(
                    angle: 0.12 * math.sin(tilt.value * 2 * math.pi) * (1 - tilt.value),
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                  child: Image.asset('assets/arwee_robot.png', height: 56, filterQuality: FilterQuality.medium),
                ),
                const SizedBox(height: 10),
                const Text('from the house of', style: TextStyle(color: Pal.fog, fontSize: 11, letterSpacing: 0.6)),
                const SizedBox(height: 2),
                const Text(
                  'arwee',
                  style: TextStyle(color: Pal.paper, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
