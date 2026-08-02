import 'package:flutter/material.dart';

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
  });

  static const String assetPath = 'assets/images/triplix_sticker.png';

  final double size;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget logo = SizedBox(
      width: size,
      height: size,
      child: Image.asset(assetPath, fit: fit),
    );

    if (shape == BoxShape.circle) {
      logo = ClipOval(child: logo);
    } else if (borderRadius != null) {
      logo = ClipRRect(borderRadius: borderRadius!, child: logo);
    }

    if (padding == EdgeInsets.zero &&
        backgroundColor == null &&
        borderRadius == null &&
        boxShadow == null &&
        shape == BoxShape.rectangle) {
      return logo;
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        boxShadow: boxShadow,
      ),
      child: logo,
    );
  }
}
