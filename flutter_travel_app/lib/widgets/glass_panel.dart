import 'dart:ui';

import 'package:flutter/material.dart';

/// A pane of frosted glass over whatever is behind it.
///
/// The sign-in form sits on this rather than on a white card, so the living
/// background stays part of the page instead of being covered by it. The
/// blur is what makes text legible over moving colour; the hairline is what
/// makes the edge readable against it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(24),
    this.blur = 22,
    this.tint = const Color(0x14FFFFFF),
    this.edge = const Color(0x24FFFFFF),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// The fill. Light enough to see through; enough to lift the form off the
  /// ground.
  final Color tint;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: shape,
            border: Border.all(color: edge),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 48,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
