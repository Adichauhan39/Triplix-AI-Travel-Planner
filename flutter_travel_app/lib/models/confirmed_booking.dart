/// A booking the user says they completed on a partner site.
///
/// Triplix redirects to Aviasales for booking and never sees the result, so
/// nothing here is verified — it is the user's own account of what they
/// booked. The field is deliberately named [confirmedByUser] rather than
/// `confirmed` so that distinction survives into anything built on top of it:
/// an itinerary can safely be planned around this, but check-in reminders,
/// insurance or anything with money attached must not treat it as fact.
enum BookingKind { flight, hotel }

class ConfirmedBooking {
  ConfirmedBooking({
    required this.kind,
    required this.title,
    required this.startDate,
    this.endDate,
    this.flightNumber,
    this.departureTime,
    this.flightIsRealFlight = false,
    this.hotelName,
    this.hotelNameIsRealPlace = false,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  /// What was booked — drives which fields the itinerary reads.
  final BookingKind kind;

  /// Human label: "BLR → RPR" for a flight, the property name for a hotel.
  final String title;

  /// Departure date, or hotel check-in.
  final DateTime startDate;

  /// Return date, or hotel check-out. Null for a one-way flight.
  final DateTime? endDate;

  /// Flight number as the user typed it, e.g. "6E 405". Flights only, and the
  /// only detail collected — it's the one field an itinerary genuinely needs
  /// (to show the leg and, later, look up times or status). Optional: a user
  /// who skips it still gives us a confirmed leg, which is the valuable part.
  final String? flightNumber;

  /// Local departure time as "HH:mm". The single most useful field for an
  /// itinerary — it anchors everything else on the day, and it's what decides
  /// whether an airport transfer is a 4am start or an afternoon one.
  ///
  /// Filled automatically when the user picks their flight from the list of
  /// real fares; blank if they typed a flight number by hand.
  final String? departureTime;

  /// True when the flight was chosen from Aviasales' real results rather than
  /// typed. Same distinction as [hotelNameIsRealPlace]: it confirms the flight
  /// exists on that route and date, not that the user is on it.
  final bool flightIsRealFlight;

  /// The property the user actually booked. Hotels only, and it has to be
  /// asked for: the handoff to Aviasales is by city, so the user picks from
  /// hundreds of properties on the partner's site and we never see which.
  /// Prefilled when the redirect started from a specific hotel card.
  final String? hotelName;

  /// True only when [hotelName] was chosen from the Google Places list, i.e.
  /// it names a property that demonstrably exists. False when the user typed
  /// it freehand, which could be a typo, an abbreviation, or a hotel that
  /// isn't real.
  ///
  /// This says nothing about whether a booking was made — that is
  /// unverifiable here (see [confirmedByUser]). It only separates "this is a
  /// real place" from "this is what someone typed", so an itinerary can show
  /// an address and map pin for the former and treat the latter as a label.
  final bool hotelNameIsRealPlace;

  /// When the user told us, not when the booking was made.
  final DateTime recordedAt;

  /// Always true today: these records only exist because a user said so.
  /// Kept explicit so a future verified source (email parsing, a booking API)
  /// can be distinguished without a schema change.
  bool get confirmedByUser => true;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate!.toIso8601String(),
        if (flightNumber != null && flightNumber!.isNotEmpty) ...{
          'flight_number': flightNumber,
          'flight_is_real_flight': flightIsRealFlight,
        },
        if (departureTime != null && departureTime!.isNotEmpty)
          'departure_time': departureTime,
        if (hotelName != null && hotelName!.isNotEmpty) ...{
          'hotel_name': hotelName,
          'hotel_name_is_real_place': hotelNameIsRealPlace,
        },
        'recorded_at': recordedAt.toIso8601String(),
        'confirmed_by_user': confirmedByUser,
      };
}
