import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The living ground behind the sign-in page.
///
/// A few soft lights drift slowly across deep ink, in the colours of the logo.
/// Nothing on it is a picture of anything; it is there so the page feels like
/// a place rather than a form. It answers the pointer very slightly, so the
/// screen is seen to notice the person in front of it.
///
/// Drawn, not layered: four radial gradients on one CustomPaint is cheaper
/// than four blurred containers, and it stays smooth on the web renderer,
/// which is where this app is actually looked at.
class AuroraCanvas extends StatefulWidget {
  const AuroraCanvas({
    super.key,
    required this.child,
    this.ink = const Color(0xFF0B1220),
    this.lights = const [
      Color(0xFF1FA7C4), // the pin
      Color(0xFFF7941D), // the sun
      Color(0xFF3B6FE8), // dusk, so the two brand colours are not alone
      Color(0xFF15C4B0), // sea
    ],
  });

  final Widget child;
  final Color ink;
  final List<Color> lights;

  @override
  State<AuroraCanvas> createState() => _AuroraCanvasState();
}

class _AuroraCanvasState extends State<AuroraCanvas>
    with SingleTickerProviderStateMixin {
  // One slow cycle. Anything faster reads as loading; this should read as
  // weather.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat();

  /// Where the pointer is, from -1 to 1 on each axis. Zero when it has not
  /// been seen, so touch devices get the still version.
  Offset _pointer = Offset.zero;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        final size = context.size;
        if (size == null || size.isEmpty) return;
        final dx = (event.localPosition.dx / size.width) * 2 - 1;
        final dy = (event.localPosition.dy / size.height) * 2 - 1;
        setState(() => _pointer = Offset(dx.clamp(-1, 1), dy.clamp(-1, 1)));
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              painter: _AuroraPainter(
                t: _clock.value,
                pointer: _pointer,
                ink: widget.ink,
                lights: widget.lights,
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.t,
    required this.pointer,
    required this.ink,
    required this.lights,
  });

  final double t;
  final Offset pointer;
  final Color ink;
  final List<Color> lights;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ink);

    final shorter = math.min(size.width, size.height);
    const tau = math.pi * 2;

    for (var i = 0; i < lights.length; i++) {
      // Each light on its own slow orbit, out of phase with the others, so
      // the whole never settles into a pattern the eye can predict.
      final phase = i / lights.length;
      final a = tau * (t + phase);
      final b = tau * (t * 0.6 + phase * 1.7);

      final cx = size.width * (0.5 + 0.34 * math.cos(a) + 0.12 * math.sin(b));
      final cy = size.height * (0.5 + 0.30 * math.sin(a) - 0.14 * math.cos(b));

      // The pointer moves near lights more than far ones. The screen leans
      // toward the person a little; it does not follow them around.
      final depth = 0.5 + (i / lights.length) * 0.5;
      final centre = Offset(
        cx + pointer.dx * 22 * depth,
        cy + pointer.dy * 16 * depth,
      );

      final radius = shorter * (0.42 + 0.06 * math.sin(b));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            lights[i].withValues(alpha: 0.42),
            lights[i].withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36);

      canvas.drawCircle(centre, radius, paint);
    }

    // A quiet vignette, so the edges recede and the panel in the middle has
    // somewhere to sit.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 1.1,
          colors: [
            ink.withValues(alpha: 0.0),
            ink.withValues(alpha: 0.55),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.pointer != pointer;
}
