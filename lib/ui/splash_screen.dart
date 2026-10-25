import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_mark.dart';

/// Opening screen: the Pen Me In mark up front, Arwee quietly underneath.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
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
    final fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    return Scaffold(
      body: SafeArea(
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
              const ArweeLogo(height: 22),
              const SizedBox(height: 8),
              Text(
                'from the house of ARWEE',
                style: TextStyle(color: Pal.fog.withValues(alpha: 0.8), fontSize: 11, letterSpacing: 1.6),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// The parent-company wordmark, recoloured to Arwee gold on any background.
class ArweeLogo extends StatelessWidget {
  const ArweeLogo({super.key, this.height = 22});

  final double height;

  static const gold = Color(0xFFBA9A56);

  @override
  Widget build(BuildContext context) => ColorFiltered(
    // Paint every pixel gold; opacity comes from how "gold" (not white or
    // transparent) the source pixel is, so a white backdrop disappears.
    colorFilter: const ColorFilter.matrix([
      0, 0, 0, 0, 186, //
      0, 0, 0, 0, 154,
      0, 0, 0, 0, 86,
      0, 0, -1.5, 1.5, 0,
    ]),
    child: Image.asset('assets/arwee_logo.webp', height: height, filterQuality: FilterQuality.medium),
  );
}
