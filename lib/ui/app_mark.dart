import 'package:flutter/material.dart';

import '../theme.dart';

/// The Pen Me In mark (placeholder until a logo is chosen).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Pal.surface,
      borderRadius: BorderRadius.circular(size * 0.22),
      border: Border.all(color: Pal.smoke),
    ),
    child: Icon(Icons.edit_note, size: size * 0.6, color: Pal.teal),
  );
}
