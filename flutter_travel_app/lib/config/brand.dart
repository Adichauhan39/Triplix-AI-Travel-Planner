import 'package:flutter/material.dart';

/// The language the whole app is being brought into.
///
/// It began as the colours of the sign-in page, taken from the logo: a teal
/// pin with an orange sun on it. Everything here is one of those two, or the
/// ink they sit on.
///
/// It is separate from `AppConfig` on purpose. AppConfig holds the older
/// palette -- a grey it calls "Deep Blue", a blue-to-purple wash -- and while
/// both exist, keeping them in different files is the only way to tell which
/// colour is the new one. AppConfig goes when the last screen is converted.
class Brand {
  // ---------------------------------------------------------------- colour
  /// The ground everything sits on.
  static const Color ink = Color(0xFF0B1220);

  /// One step up from the ground: cards, sheets, rows.
  static const Color surface = Color(0xFF111A2B);

  /// Two steps up, for something raised above a card.
  static const Color raised = Color(0xFF17233A);

  static const Color teal = Color(0xFF1FA7C4);
  static const Color sun = Color(0xFFF7941D);

  static const Color text = Colors.white;

  /// Secondary text. Readable, not shouting.
  static const Color muted = Color(0xB3FFFFFF);

  /// Third-tier text: captions, disabled, fine print.
  static const Color faint = Color(0x66FFFFFF);

  /// A line, not a border -- barely there on purpose.
  static const Color hairline = Color(0x24FFFFFF);

  /// A wash for a resting surface or a quiet chip.
  static const Color fill = Color(0x0FFFFFFF);

  /// Something wrong, and something worth a second look.
  static const Color danger = Color(0xFFE5484D);
  static const Color caution = Color(0xFFF5A524);
  static const Color good = Color(0xFF30A46C);

  static const LinearGradient action = LinearGradient(
    colors: [teal, sun],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ------------------------------------------------------------------ type
  //
  // Four sizes and three weights, because the old screens used nine sizes
  // that differed by a point and nothing had a hierarchy: a place's name, its
  // categories, its rating and its hours all read as equally important, so the
  // eye had nowhere to land.

  /// A screen's name. One per page.
  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.15,
    letterSpacing: -0.4,
  );

  /// The name of a thing in a list -- a place, a day, a person.
  static const TextStyle heading = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.25,
  );

  /// Ordinary reading text.
  static const TextStyle body = TextStyle(
    fontSize: 13,
    color: muted,
    height: 1.4,
  );

  /// A fact rather than a sentence: a rating, an amount, a time.
  static const TextStyle figure = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: text,
  );

  /// Fine print and labels.
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    color: faint,
    height: 1.35,
  );

  // --------------------------------------------------------------- spacing
  //
  // A scale, so margins stop being whatever number was typed. Eight and
  // sixteen do most of the work.
  static const double tight = 6;
  static const double gap = 12;
  static const double pad = 16;
  static const double wide = 24;

  static const double radius = 14;
  static const double radiusSmall = 10;
  static const double radiusPill = 999;

  /// A card: the surface, a hairline, and a radius. Used everywhere, so it is
  /// defined once rather than re-typed with a slightly different grey.
  static BoxDecoration card({Color? color, Color? border}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? hairline),
      );

  /// A quiet chip for one fact.
  static BoxDecoration chip({Color? color}) => BoxDecoration(
        color: color ?? fill,
        borderRadius: BorderRadius.circular(radiusPill),
      );
}
