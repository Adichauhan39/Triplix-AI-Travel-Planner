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
  //
  // Paper, not ink. The names are kept -- `ink` is still the ground and
  // `surface` is still a card -- because 190 references across three screens
  // read better as roles than as colours, and the roles did not change when
  // the values did.

  /// The page. Not pure white: a hair of grey so a white card reads as raised.
  static const Color ink = Color(0xFFF6F7F9);

  /// A card, a sheet, a row.
  static const Color surface = Colors.white;

  /// Above a card. Same white, told apart by its border and shadow.
  static const Color raised = Colors.white;

  /// The logo, unchanged. Anything you can press is this.
  static const Color teal = Color(0xFF1FA7C4);

  /// The sun on the pin. One thing per screen, or it stops meaning anything.
  static const Color sun = Color(0xFFF7941D);

  /// Reading text.
  static const Color text = Color(0xFF0F172A);

  /// Secondary text.
  static const Color muted = Color(0xFF475569);

  /// Captions, disabled, fine print.
  static const Color faint = Color(0xFF94A3B8);

  /// A line, not a border.
  static const Color hairline = Color(0xFFE3E8EF);

  /// A wash for a resting surface or a quiet chip.
  static const Color fill = Color(0xFFF1F4F8);

  /// Something wrong, and something worth a second look.
  static const Color danger = Color(0xFFDC2626);
  static const Color caution = Color(0xFFB45309);
  static const Color good = Color(0xFF047857);

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
