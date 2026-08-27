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
    _bookings.clear();
    // Restored through the same de-duplication, so a device that already
    // stored duplicates is cleaned up on the next launch rather than
    // carrying them forever.
    for (final json in stored) {
      final booking = ConfirmedBooking.fromJson(json);
      final index =
          _bookings.indexWhere((existing) => _isSameLeg(existing, booking));
      if (index >= 0) {
        _bookings[index] = booking;
      } else {
        _bookings.add(booking);
      }
    }
    notifyListeners();
  }

  /// Persists on every change, so no future mutation can forget to save.
  @override
  void notifyListeners() {
    super.notifyListeners();
    LocalStore.save(
        LocalStore.keyBookings, _bookings.map((b) => b.toJson()).toList());
  }

  /// Records a booking, replacing an earlier one for the same leg.
  ///
  /// This used to append unconditionally, so confirming the same flight twice
  /// -- easy to do, since the sheet reappears whenever the user searches that
  /// route again -- listed it twice on the itinerary. Persistence made it
  /// worse: the duplicates survived restarts and accumulated.
  ///
  /// Replacing rather than ignoring the second one is deliberate. The later
  /// record is the one the user just confirmed, and it may correct the first:
  /// a flight saved with no number through "I don't have it yet" should be
  /// upgraded when they come back and pick it properly.
  void add(ConfirmedBooking booking) {
    final index = _bookings.indexWhere((existing) => _isSameLeg(existing, booking));
    if (index >= 0) {
      _bookings[index] = booking;
    } else {
      _bookings.add(booking);
    }
    notifyListeners();
  }

  /// Whether two records describe the same leg of the trip.
  ///
  /// Two flights on one day are only the same leg if they carry the same
  /// number -- a genuine outbound and a return on the same date must both
  /// survive. A flight with no number is treated as the day's single
  /// unnamed flight, since two of those cannot be told apart anyway.
  ///
  /// A hotel is keyed on its check-in date alone: nobody checks into two
  /// hotels on the same day, and if they change which one, the new answer
  /// replaces the old.
  static bool _isSameLeg(ConfirmedBooking a, ConfirmedBooking b) {
    if (a.kind != b.kind) return false;
    final sameDay = a.startDate.year == b.startDate.year &&
        a.startDate.month == b.startDate.month &&
        a.startDate.day == b.startDate.day;
    if (!sameDay) return false;
    if (a.kind == BookingKind.hotel) return true;

    // Two flights arriving at the same place on the same day are the same
    // leg however differently they are numbered -- nobody flies to Raipur
    // twice in one afternoon. Searching Bangalore to Raipur and then
    // Varanasi to Raipur left both on the itinerary, because the numbers
    // differed and the old one was never replaced.
    //
    // Destination rather than the whole route, so an outbound and a return
    // on one date stay separate: those share a day but end in different
    // places.
    final destA = _destinationOf(a.title);
    final destB = _destinationOf(b.title);
    if (destA != null && destB != null) return destA == destB;

    final numberA = (a.flightNumber ?? '').replaceAll(' ', '').toUpperCase();
    final numberB = (b.flightNumber ?? '').replaceAll(' ', '').toUpperCase();
    if (numberA.isEmpty || numberB.isEmpty) return true;
    return numberA == numberB;
  }

  /// Where a flight title says it ends up.
  ///
  /// Titles are built by this app as "<origin> to <destination>", so this
  /// reads our own format rather than guessing at arbitrary text. Returns
  /// null when the shape does not hold, and the caller falls back to
  /// comparing flight numbers.
  static String? _destinationOf(String title) {
    final parts = title.split(' to ');
    if (parts.length < 2) return null;
    final destination = parts.last.split(',').first.trim().toLowerCase();
    return destination.isEmpty ? null : destination;
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
