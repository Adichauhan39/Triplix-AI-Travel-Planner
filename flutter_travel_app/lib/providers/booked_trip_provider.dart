import 'package:flutter/foundation.dart';

import '../models/confirmed_booking.dart';

/// What the user has told us they've booked, ready for the itinerary.
///
/// In memory only, matching UserPreferencesProvider and HotelShortlistProvider
/// — there's no persistence layer in the app yet, so this is lost on restart.
/// Worth wiring to storage before this feature ships, since a user who books a
/// flight, confirms it, then reopens the app to an empty itinerary will not
/// confirm a second time.
class BookedTripProvider with ChangeNotifier {
  final List<ConfirmedBooking> _bookings = [];

  List<ConfirmedBooking> get bookings => List.unmodifiable(_bookings);

  List<ConfirmedBooking> get flights =>
      _bookings.where((b) => b.kind == BookingKind.flight).toList();

  List<ConfirmedBooking> get hotels =>
      _bookings.where((b) => b.kind == BookingKind.hotel).toList();

  bool get hasFlight => flights.isNotEmpty;
  bool get hasHotel => hotels.isNotEmpty;

  /// True once the trip has both legs covered — the point at which a full
  /// itinerary can be built rather than a partial one.
  bool get isTripComplete => hasFlight && hasHotel;

  void add(ConfirmedBooking booking) {
    _bookings.add(booking);
    notifyListeners();
  }

  void remove(ConfirmedBooking booking) {
    _bookings.remove(booking);
    notifyListeners();
  }

  void clear() {
    if (_bookings.isEmpty) return;
    _bookings.clear();
    notifyListeners();
  }
}
