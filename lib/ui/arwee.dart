import 'dart:async';

import 'package:flutter/material.dart';

/// Height of the Arwee logo in a page's top-right corner.
const arweeCornerHeight = 26.0;

/// The Arwee logo for a page's top-right corner (app bar actions).
class ArweeCorner extends StatelessWidget {
  const ArweeCorner({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Center(child: ArweeWordmark(height: arweeCornerHeight)),
  );
}

/// The gold Arwee wordmark, used as a quiet parent-company credit (same as
/// Save This Spot).
///
/// With [shimmer], a soft band of light sweeps across it every few seconds.
/// Between sweeps nothing animates (no frames are drawn), and the effect is
/// off when the system asks for reduced motion.
class ArweeWordmark extends StatefulWidget {
  const ArweeWordmark({super.key, this.height = 18, this.opacity = 0.9, this.shimmer = true});

  final double height;
  final double opacity;
  final bool shimmer;

  @override
  State<ArweeWordmark> createState() => _ArweeWordmarkState();
}

class _ArweeWordmarkState extends State<ArweeWordmark> with SingleTickerProviderStateMixin {
  static const _sweep = Duration(milliseconds: 1400);
  static const _pause = Duration(seconds: 4);

  late final AnimationController _c = AnimationController(vsync: this, duration: _sweep)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _schedule(_pause);
    });
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) _schedule(const Duration(milliseconds: 800));
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, () {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Opacity(
      opacity: widget.opacity,
      child: Image.asset(
        'assets/arwee_wordmark.png',
        height: widget.height,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Arwee',
      ),
    );
    if (!widget.shimmer) return image;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: image,
        builder: (context, child) {
          if (!_c.isAnimating) return child!;
          // The light band travels from left of the logo to right of it.
          final shift = -2.0 + 4.0 * Curves.easeInOut.transform(_c.value);
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-1 + shift, -0.6),
              end: Alignment(1 + shift, 0.6),
              colors: const [Color(0x00FFFAF0), Color(0xCCFFFAF0), Color(0x00FFFAF0)],
              stops: const [0.3, 0.5, 0.7],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}
