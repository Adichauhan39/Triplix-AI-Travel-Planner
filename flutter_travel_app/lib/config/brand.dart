import 'package:flutter/material.dart';

/// The colours of the entrance to the app, taken from the logo.
///
/// The mark is a teal pin with an orange sun on it. Everything here is either
/// one of those two, or the ink they sit on. `AppConfig` has other ideas -- a
/// grey it calls "Deep Blue", a wash of blue-to-purple on the old sign-in --
/// and the screens before the app proper are where one language starts.
///
/// Kept apart from AppConfig on purpose: this is the language of the entrance
/// until the rest of the app is brought to it, and mixing the two files would
/// make it impossible to tell which colour is the new one.
class Brand {
  static const Color ink = Color(0xFF0B1220);
  static const Color teal = Color(0xFF1FA7C4);
  static const Color sun = Color(0xFFF7941D);

  static const Color text = Colors.white;
  static const Color muted = Color(0xB3FFFFFF);
  static const Color faint = Color(0x66FFFFFF);
  static const Color hairline = Color(0x24FFFFFF);
  static const Color fill = Color(0x0FFFFFFF);

  static const LinearGradient action = LinearGradient(
    colors: [teal, sun],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
