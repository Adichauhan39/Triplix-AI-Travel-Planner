import 'package:flutter/material.dart';

/// The Triplix mark: a teal pin with an orange sun on it.
///
/// The real artwork, not a drawing of it.
///
/// This was briefly a hand-drawn path. `triplix_sticker.png` has a
/// transparency checkerboard baked into it as opaque grey squares -- a picture
/// *of* transparency -- so it carried a chequered box behind the mark on every
/// screen, and it cannot be cleaned by colour because the pin's white rim is
/// the same white as the checker squares.
///
/// Redrawing it was the wrong answer to that. `triplix (1).png` was sitting in
/// the same folder with proper transparency all along, and a path traced by
/// eye is not the logo however close it looks -- the head was narrower and the
/// point blunter than the real mark, which is exactly the kind of drift a
/// brand cannot afford. The clean file is now used directly.
///
/// Drawing it also fixes the thing an image could never fix: it is crisp at 20
/// pixels and at 200, and its colours are the brand's constants rather than
/// whatever a JPEG round-trip left behind.
///
/// The asset path is kept because pubspec still points the launcher icon at
/// it. That one does need a clean export -- a launcher icon cannot be painted.
class TriplixLogo extends StatelessWidget {
  const TriplixLogo({
    super.key,
    required this.size,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.boxShadow,
    this.fit = BoxFit.cover,
    this.lifted = false,
  });

  /// Draws the mark as a sticker resting on the page: its own teal glow
  /// beneath it and a soft shadow under the point.
  ///
  /// Off by default, because most places show it small and inline, where a
  /// shadow is noise. The entrance screens turn it on -- there the mark is the
  /// subject, and a subject wants to sit above the paper rather than in it.
  final bool lifted;

  /// The mark itself. The launcher-icon configuration in pubspec.yaml still
  /// points at the sticker, which is correct: a launcher icon is composited
  /// onto its own opaque tile, so the baked checkerboard never shows there.
  static const String assetPath = 'assets/images/triplix_logo.png';

  final double size;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;

  /// Kept for the callers that pass it. A painted mark has nothing to crop.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // Decoded at the size it is actually drawn, in real device pixels.
    //
    // The artwork is 1024 square and this is often asked to draw it at 40.
    // Without a cache size the full 1024 is decoded and then squeezed down on
    // every single frame, which is both slow and soft -- and softest while the
    // mark is moving, because each frame resamples from scratch at a slightly
    // different sub-pixel offset. Decoding once at the right size is what
    // makes it crisp in motion.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final pixels = (size * ratio).ceil();

    final Widget mark = SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        cacheWidth: pixels,
        cacheHeight: pixels,
        // Medium, not high.
        //
        // FilterQuality.high is bicubic and is meant for scaling *up*; on a
        // reduction this large it is slower and no sharper. Medium samples
        // through mipmaps, which is exactly the right tool for shrinking a
        // big image and is what keeps the edges clean as it drifts.
        filterQuality: FilterQuality.medium,
        // Contain, never cover: the artwork is a pin on a transparent square,
        // and cropping it cuts the point off.
        fit: BoxFit.contain,
        // If the asset ever goes missing the app shows the mark drawn rather
        // than a broken-image box.
        errorBuilder: (_, __, ___) =>
            CustomPaint(painter: _PinPainter(lifted: lifted)),
      ),
    );

    // The glow, which the drawn version used to provide and the artwork does
    // not. Restored here rather than lost quietly when the mark went back to
    // being a picture: the entrance screens ask for `lifted` and were getting
    // nothing for it.
    final Widget lit = lifted
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1FA7C4).withValues(alpha: 0.28),
                  blurRadius: size * 0.42,
                  spreadRadius: size * 0.02,
                ),
              ],
            ),
            child: mark,
          )
        : mark;

    // No clipping. The old widget clipped a square photograph into a circle;
    // the mark is already the right shape and a circular clip would cut its
    // point off.
    if (padding == EdgeInsets.zero &&
        backgroundColor == null &&
        boxShadow == null) {
      return lit;
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        boxShadow: boxShadow,
      ),
      child: lit,
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter({this.lifted = false});

  final bool lifted;

  // The logo's own two colours, and the rim that separates them from whatever
  // is behind.
  static const Color _body = Color(0xFF1FA7C4);
  static const Color _sun = Color(0xFFF7941D);
  static const Color _rim = Colors.white;

  /// The pin, as a path inside a square of side [s].
  ///
  /// A circle for the head and two curves drawn down to the point, which is
  /// how the mark is shaped: a rounded teardrop, not a balloon on a stick.
  Path _pin(double s) {
    final radius = s * 0.295;
    final centre = Offset(s / 2, s * 0.375);
    final tip = Offset(s / 2, s * 0.945);

    return Path()
      ..moveTo(centre.dx - radius, centre.dy)
      // Over the top of the head, left to right.
      ..arcToPoint(
        Offset(centre.dx + radius, centre.dy),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      // Down the right flank into the point, and back up the left. The
      // control points sit outside the head so the sides swell before they
      // taper, which is what stops it looking like a triangle.
      ..quadraticBezierTo(
        centre.dx + radius * 0.80,
        centre.dy + radius * 1.15,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        centre.dx - radius * 0.80,
        centre.dy + radius * 1.15,
        centre.dx - radius,
        centre.dy,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;

    final pin = _pin(s);
    final centre = Offset(s / 2, s * 0.375);

    if (lifted) {
      // A wash of the pin's own teal, spread wider than the pin, so the mark
      // sits in a little light of its own.
      canvas.drawPath(
        pin,
        Paint()
          ..color = _body.withValues(alpha: 0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.16),
      );
      // And a shadow, offset down: what makes it read as resting on the page
      // rather than printed into it.
      canvas.save();
      canvas.translate(0, s * 0.035);
      canvas.drawPath(
        pin,
        Paint()
          ..color = const Color(0x33101828)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
      );
      canvas.restore();
    }

    // The rim, drawn as a stroke around the same path rather than as a second
    // larger path: a scaled copy thickens unevenly at the point.
    canvas.drawPath(
      pin,
      Paint()
        ..color = _rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.075
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    canvas.drawPath(pin, Paint()..color = _body..isAntiAlias = true);

    canvas.drawCircle(
      centre,
      s * 0.135,
      Paint()..color = _sun..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => oldDelegate.lifted != lifted;
}
