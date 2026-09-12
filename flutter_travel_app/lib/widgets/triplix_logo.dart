import 'package:flutter/material.dart';

/// The Triplix mark: a teal pin with an orange sun on it.
///
/// Drawn rather than loaded. The asset it used to show,
/// `assets/images/triplix_sticker.png`, has a transparency checkerboard baked
/// into it as opaque grey squares -- a picture *of* transparency -- so the mark
/// carried a chequered box behind it on every screen it appeared on. It cannot
/// be cleaned reliably either: the pin's white rim is the same white as the
/// checker squares, so removing the background by colour eats the rim, and
/// removing it by flood fill leaves a grey fringe that shows badly on paper.
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

  /// Still referenced by the launcher-icon configuration in pubspec.yaml.
  static const String assetPath = 'assets/images/triplix_sticker.png';

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
    final Widget mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PinPainter(lifted: lifted)),
    );

    // No clipping. The old widget clipped a square photograph into a circle;
    // the mark is already the right shape and a circular clip would cut its
    // point off.
    if (padding == EdgeInsets.zero &&
        backgroundColor == null &&
        boxShadow == null) {
      return mark;
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        boxShadow: boxShadow,
      ),
      child: mark,
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
