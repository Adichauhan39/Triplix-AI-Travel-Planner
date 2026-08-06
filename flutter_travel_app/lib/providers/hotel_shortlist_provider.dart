import 'package:flutter/foundation.dart';
import '../models/hotel.dart';

/// The single hotel the user has picked for their trip, kept in memory only
/// (same as UserPreferencesProvider — lost on app restart, no persistence
/// layer yet). Only one hotel can be selected at a time: picking a new one
/// automatically replaces whatever was previously selected. Selecting never
/// leaves the app; only booking the selected hotel triggers the third-party
/// redirect.
class HotelShortlistProvider with ChangeNotifier {
  Hotel? _selected;

  Hotel? get selected => _selected;

  /// Exposed as a list (0 or 1 items) so existing UI that iterates/reads a
  /// count doesn't need to change shape just because selection is now
  /// single-hotel rather than multi-hotel.
  List<Hotel> get hotels => _selected == null ? const [] : [_selected!];

  bool _sameHotel(Hotel a, Hotel b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty) return a.id == b.id;
    return a.name == b.name && a.city == b.city;
  }

  bool isShortlisted(Hotel hotel) =>
      _selected != null && _sameHotel(_selected!, hotel);

  /// Selects [hotel], replacing any previous selection. Tapping the
  /// already-selected hotel again deselects it. Returns the resulting
  /// selected state for [hotel].
  bool toggle(Hotel hotel) {
    final alreadySelected = isShortlisted(hotel);
    _selected = alreadySelected ? null : hotel;
    notifyListeners();
    return !alreadySelected;
  }

  void remove(Hotel hotel) {
    if (isShortlisted(hotel)) {
      _selected = null;
      notifyListeners();
    }
  }

  void clear() {
    _selected = null;
    notifyListeners();
  }
}
