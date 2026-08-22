import 'package:flutter/foundation.dart';

import '../models/confirmed_booking.dart';
import '../services/local_store.dart';

/// What the user has told us they've booked, ready for the itinerary.
///
/// Written to the device on every change. A user who books a flight, confirms
/// it, then reopens the app to an empty itinerary will not confirm a second
/// time — and unlike a preference, this is a record of something that really
/// happened and cannot be reconstructed by asking again.
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

  /// Reads back the bookings saved on this device.
  void restore() {
    final stored = LocalStore.loadList(LocalStore.keyBookings);
    if (stored.isEmpty) return;
    _bookings
      ..clear()
      ..addAll(stored.map(ConfirmedBooking.fromJson));
    notifyListeners();
  }

  /// Persists on every change, so no future mutation can forget to save.
  @override
  void notifyListeners() {
    super.notifyListeners();
    LocalStore.save(
        LocalStore.keyBookings, _bookings.map((b) => b.toJson()).toList());
  }

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
