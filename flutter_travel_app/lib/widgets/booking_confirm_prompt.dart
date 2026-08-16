import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/confirmed_booking.dart';
import '../providers/booked_trip_provider.dart';
import '../services/affiliate_links.dart';
import '../services/python_adk_service.dart';

/// Asks the user whether they completed a booking after returning from a
/// partner site.
///
/// Booking happens on Aviasales, which never tells us the outcome, so this is
/// the only point where the app can learn what the trip actually contains.
/// It is deliberately cheap to dismiss: a wrong "yes" pollutes the itinerary,
/// and nagging costs more than a missed confirmation.
///
/// Call [show] straight after the redirect returns — AffiliateLinks.open uses
/// an in-app browser, so control comes back when the user closes that tab.
class BookingConfirmPrompt {
  BookingConfirmPrompt._();

  static final DateFormat _display = DateFormat('dd MMM yyyy');

  /// Shows the prompt for a [kind] booking described by [title].
  ///
  /// [startDate]/[endDate] prefill the form from what the user was searching,
  /// so a confirmation is usually two taps. Returns the saved booking, or null
  /// if they said no / dismissed.
  /// [knownHotelName] prefills the hotel field when the redirect started from
  /// a specific property card. Leave null for a city-level handoff, where the
  /// user picks from the partner's list and we genuinely don't know.
  /// Opens the booking link, then shows the confirmation sheet — which simply
  /// waits, open, until the user comes back to the app.
  ///
  /// An earlier version tried to detect the return via AppLifecycleListener
  /// and only then show the sheet. That never fired reliably: on web the
  /// partner opens in another browser tab and this app is never backgrounded,
  /// so no resume event arrives, and the grace-period fallback was fighting
  /// platform behaviour rather than working with it.
  ///
  /// Opening the sheet straight away is deterministic on every platform. A
  /// modal bottom sheet isn't dismissed by launching a browser, so it is
  /// simply sitting there — behind the in-app tab on mobile, on the other tab
  /// on web — whenever the user comes back. No lifecycle events involved.
  static Future<ConfirmedBooking?> launchAndConfirm(
    BuildContext context, {
    required Future<void> Function() launch,
    required BookingKind kind,
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    String? knownHotelName,
    String city = '',
    String flightOrigin = '',
    String flightDestination = '',
    String flightOriginIata = '',
    String flightDestinationIata = '',
  }) async {
    await launch();

    // Brief pause so the sheet doesn't animate up during the tab switch.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!context.mounted) return null;
    return show(
      context,
      kind: kind,
      title: title,
      startDate: startDate,
      endDate: endDate,
      knownHotelName: knownHotelName,
      city: city,
      flightOrigin: flightOrigin,
      flightDestination: flightDestination,
      flightOriginIata: flightOriginIata,
      flightDestinationIata: flightDestinationIata,
    );
  }

  /// [city] scopes hotel-name lookups, so "city lite" finds the property in
  /// the right town rather than a same-named one elsewhere.
  static Future<ConfirmedBooking?> show(
    BuildContext context, {
    required BookingKind kind,
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    String? knownHotelName,
    String city = '',
    String flightOrigin = '',
    String flightDestination = '',
    String flightOriginIata = '',
    String flightDestinationIata = '',
  }) async {
    final noun = kind == BookingKind.flight ? 'flight' : 'stay';

    final didBook = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  kind == BookingKind.flight ? Icons.flight : Icons.hotel,
                  color: AppConfig.primaryColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Did you book this $noun?',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            Text(
              endDate == null
                  ? _display.format(startDate)
                  : '${_display.format(startDate)} – ${_display.format(endDate)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 6),
            Text(
              'We can add it to your itinerary. You can change it later.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Not yet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Yes, I booked'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (didBook != true || !context.mounted) return null;

    // One field each: the flight number, or which hotel. Both are things the
    // redirect can't tell us — the user chooses the actual flight or property
    // on the partner's site, out of our sight.
    return _askDetail(
      context,
      kind: kind,
      title: title,
      startDate: startDate,
      endDate: endDate,
      initialValue: kind == BookingKind.hotel ? knownHotelName : null,
      city: city,
      // Without these the sheet has no route to look up, so the flight list
      // never loads and the user only gets a bare number field.
      flightOrigin: flightOrigin,
      flightDestination: flightDestination,
      flightOriginIata: flightOriginIata,
      flightDestinationIata: flightDestinationIata,
    );
  }

  /// Second step: one field — the flight number, or which hotel. Optional
  /// either way; a user who skips it still gives us a confirmed leg, which is
  /// the part the itinerary can't get any other way.
  static Future<ConfirmedBooking?> _askDetail(
    BuildContext context, {
    required BookingKind kind,
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    String? initialValue,
    String city = '',
    String flightOrigin = '',
    String flightDestination = '',
    String flightOriginIata = '',
    String flightDestinationIata = '',
  }) async {
    final result = await showModalBottomSheet<_DetailResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BookingDetailSheet(
        kind: kind,
        initialValue: initialValue ?? '',
        city: city,
        flightOrigin: flightOrigin,
        flightDestination: flightDestination,
        flightOriginIata: flightOriginIata,
        flightDestinationIata: flightDestinationIata,
        flightDate: startDate,
      ),
    );

    if (result == null || !context.mounted) return null;

    final isFlight = kind == BookingKind.flight;
    final entered = result.value;

    return _save(
      context,
      ConfirmedBooking(
        kind: kind,
        // For a city-level hotel handoff the title was a placeholder like
        // "Stay in Delhi" — the property the user names is better, so it
        // becomes the title too.
        title: (!isFlight && entered.isNotEmpty) ? entered : title,
        startDate: startDate,
        endDate: endDate,
        flightNumber: isFlight && entered.isNotEmpty ? entered : null,
        departureTime: isFlight ? result.departureTime : null,
        flightIsRealFlight:
            isFlight && entered.isNotEmpty ? result.pickedFromPlaces : false,
        hotelName: !isFlight && entered.isNotEmpty ? entered : null,
        hotelNameIsRealPlace:
            !isFlight && entered.isNotEmpty ? result.pickedFromPlaces : false,
      ),
      lookupFailed: result.lookupFailed,
    );
  }


  static ConfirmedBooking _save(
    BuildContext context,
    ConfirmedBooking booking, {
    bool lookupFailed = false,
  }) {
    context.read<BookedTripProvider>().add(booking);

    // A hotel name typed freehand was never matched against a real property.
    // Places' fuzzy matching rescues well-known hotels but not smaller ones,
    // so say plainly that it was stored as written rather than implying it
    // was checked.
    final unmatchedHotel = booking.kind == BookingKind.hotel &&
        (booking.hotelName ?? '').isNotEmpty &&
        !booking.hotelNameIsRealPlace;

    final String message;
    if (booking.kind == BookingKind.flight) {
      message = 'Flight added to your itinerary';
    } else if (lookupFailed) {
      // Our lookup broke, not their spelling. Saying "check the spelling"
      // here sends the user hunting for a mistake they didn't make.
      message = 'Saved as "${booking.hotelName}" — we couldn\'t check it '
          'against hotel listings just now';
    } else if (unmatchedHotel) {
      message = 'Saved as "${booking.hotelName}" — we couldn\'t match that '
          'to a hotel we know, so check the spelling';
    } else {
      message = 'Stay added to your itinerary';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
            Duration(seconds: (unmatchedHotel || lookupFailed) ? 6 : 4),
      ),
    );
    return booking;
  }
}

/// What the detail sheet returns: the text entered, and whether it was chosen
/// from the Places list rather than typed.
class _DetailResult {
  const _DetailResult(
    this.value,
    this.pickedFromPlaces, {
    this.departureTime,
    this.lookupFailed = false,
  });

  /// Set only when a flight was chosen from the real departures list.
  final String? departureTime;

  /// True when we couldn't reach the lookup service, as opposed to reaching
  /// it and finding nothing. Changes what the user is told.
  final bool lookupFailed;
  final String value;
  final bool pickedFromPlaces;
}

/// The "flight number / which hotel" step.
///
/// A real StatefulWidget rather than a StatefulBuilder with captured locals:
/// the hotel lookup is debounced and asynchronous, and when the sheet was torn
/// down mid-lookup the callback touched a controller and an element that had
/// already been disposed, tripping a framework assertion
/// (`_dependents.isEmpty is not true`). Owning the controller and the timer
/// here means dispose() can cancel both, and setState is guarded by `mounted`.
class _BookingDetailSheet extends StatefulWidget {
  const _BookingDetailSheet({
    required this.kind,
    required this.initialValue,
    required this.city,
    this.flightOrigin = '',
    this.flightDestination = '',
    this.flightOriginIata = '',
    this.flightDestinationIata = '',
    this.flightDate,
  });

  final BookingKind kind;
  final String initialValue;
  final String city;

  /// Route and date for a flight, used to look up the real departures the
  /// user could have booked. Without them the sheet falls back to a plain
  /// flight-number field.
  final String flightOrigin;
  final String flightDestination;

  /// Airport codes resolved by the server, which substitutes the nearest
  /// airport for a city that has none. Empty when the caller didn't resolve
  /// them, in which case the built-in map is used as before.
  final String flightOriginIata;
  final String flightDestinationIata;
  final DateTime? flightDate;

  @override
  State<_BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends State<_BookingDetailSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final PythonADKService _adkService = PythonADKService();

  List<Map<String, String>> _suggestions = [];
  bool _lookingUp = false;

  /// The city's hotels, loaded once when the sheet opens. Kept separate from
  /// [_suggestions] so typing can filter them locally for an instant result,
  /// and so clearing the field restores the full list instead of nothing.
  List<Map<String, String>> _cityHotels = [];

  /// Places results keyed by the query that produced them, so re-typing or
  /// backspacing reuses what we already fetched rather than waiting on the
  /// network again. Mirrors the prefix cache behind the onboarding city
  /// fields, which is what makes those feel instant.
  final Map<String, List<Map<String, String>>> _hotelCache = {};

  /// The suggestion the user tapped. Selecting is not saving: this only marks
  /// the card so they can see their choice, and "Save to itinerary" is what
  /// actually commits it.
  String? _selectedHotel;

  /// Set when a lookup succeeded but matched nothing, so the city list shown
  /// in its place can be labelled honestly rather than looking like results.
  bool _noMatch = false;

  /// True while the final "did you mean?" check runs on save.
  bool _verifying = false;

  /// Whether the on-demand schedule lookup has been run, so an empty result
  /// reads as "we looked and found nothing" rather than "not tried yet".
  bool _searchedSchedule = false;
  Timer? _debounce;

  /// Real departures on this route and date, offered so the user recognises
  /// their flight instead of recalling a number. Selecting one also captures
  /// the departure time, which is what the itinerary is actually built around.
  List<Map<String, dynamic>> _flightOptions = [];
  bool _loadingFlights = false;
  String? _pickedDepartureTime;

  /// Not seeded from initialValue: a prefilled name comes from our own hotel
  /// results, which may be CSV rows or AI-generated, so it isn't evidence the
  /// property exists.
  bool _pickedFromPlaces = false;

  bool get _isFlight => widget.kind == BookingKind.flight;

  // Sentinels for the "did you mean?" dialog, so its three outcomes stay
  // distinguishable from a real hotel name.
  static const String _editSentinel = '\u0000edit';
  static const String _keepSentinel = '\u0000keep';

  @override
  void initState() {
    super.initState();
    if (_isFlight) {
      if (widget.flightOrigin.isNotEmpty &&
          widget.flightDestination.isNotEmpty &&
          widget.flightDate != null) {
        _loadFlightOptions();
      }
    } else if (widget.city.isNotEmpty) {
      _loadCityHotels();
    }
  }

  /// Lists hotels in the city as soon as the sheet opens, so the user can just
  /// tap the one they booked.
  ///
  /// Previously nothing appeared until they typed three characters, which
  /// meant the common case — "I booked something in Bhilai, which was it" —
  /// showed an empty box, and a misspelling then produced no matches at all.
  /// Flights already work this way; hotels didn't.
  Future<void> _loadCityHotels() async {
    setState(() => _lookingUp = true);
    // Generic query: Places treats it as "hotels in <city>" and returns the
    // prominent ones, which is the right starting list to recognise from.
    final found = await _adkService.searchHotelNames(
        query: 'hotel', city: widget.city, limit: 6);
    if (!mounted) return;
    setState(() {
      if (found != null) {
        _cityHotels = found;
        // Don't clobber anything the user has already typed their way to.
        if (_controller.text.trim().isEmpty) _suggestions = found;
      }
      _lookingUp = false;
    });
  }

  /// Fetches the real departures for this route and date. Same source the
  /// flight search uses, so the list is exactly what was bookable.
  Future<void> _loadFlightOptions() async {
    setState(() => _loadingFlights = true);
    final result = await _adkService.searchFlightFares(
      from: widget.flightOrigin,
      to: widget.flightDestination,
      departureDate: widget.flightDate!,
    );
    if (!mounted) return;

    // Keep only flights actually on the requested day.
    //
    // The search endpoint deliberately widens to nearby dates when the exact
    // day has no cached fare — useful when browsing, wrong here. Asking "which
    // flight did you book on 10 Sep" while listing departures from the 3rd,
    // 5th and 24th invites the user to confirm a flight they were never on.
    // Better to show nothing and let them type it.
    final wanted = _isoDay(widget.flightDate!);
    final sameDay = List<Map<String, dynamic>>.from(result['flights'] ?? [])
        .where((f) => (f['flight_date'] ?? '').toString() == wanted);

    // Collapse to one row per flight: the fare list repeats the same flight at
    // different prices, and the user is identifying a flight, not a fare.
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final f in sameDay) {
      final key = '${f['route_number']}_${f['departure_time']}';
      if (seen.add(key)) unique.add(f);
    }

    // Show the fares straight away — they arrive in ~2s — then bring in the
    // schedule behind them.
    if (mounted && unique.isNotEmpty) {
      setState(() => _flightOptions = unique);
    }

    // The fare cache is a price cache, not a timetable: BLR-RPR holds one
    // fare where the route actually flies four times a day. So the grounded
    // schedule always runs here and is merged in. It's justified at this
    // point — the sheet only opens once the user has said they booked —
    // unlike the earlier version that fired on every flight search.
    await _findFlightsOnRoute(existing: unique);
  }

  /// Merges published schedules into [existing], keeping one row per flight.
  Future<void> _findFlightsOnRoute({
    List<Map<String, dynamic>> existing = const [],
  }) async {
    final wanted = _isoDay(widget.flightDate!);

    // IATA codes, not city names: the server caches on the exact strings it
    // was given, so "Bangalore" and "BLR" would be different entries.
    // Server-resolved code first: it covers cities the built-in map doesn't,
    // and substitutes the nearest airport for a city with none. Without it a
    // Bilaspur trip asked the schedule lookup for flights from "Bilaspur",
    // which is not an airport and cannot return anything useful.
    final originIata = widget.flightOriginIata.isNotEmpty
        ? widget.flightOriginIata
        : AffiliateLinks.iataCodeFor(widget.flightOrigin) ??
            widget.flightOrigin;
    final destIata = widget.flightDestinationIata.isNotEmpty
        ? widget.flightDestinationIata
        : AffiliateLinks.iataCodeFor(widget.flightDestination) ??
            widget.flightDestination;

    if (mounted) setState(() => _loadingFlights = true);
    final schedule = await _adkService.flightSchedule(
      originIata: originIata,
      destinationIata: destIata,
      isoDate: wanted,
    );
    if (!mounted) return;

    String key(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    final merged = <Map<String, dynamic>>[...existing];
    final seen = existing
        .map((f) => key((f['route_number'] ?? '').toString()))
        .toSet();

    for (final f in schedule) {
      final number = (f['flight_number'] ?? '').toString();
      if (number.isEmpty || !seen.add(key(number))) continue;
      merged.add({
        'provider': (f['airline'] ?? '').toString(),
        'route_number': number,
        'departure_time': (f['departure_time'] ?? '').toString(),
        'arrival_time': (f['arrival_time'] ?? '').toString(),
        'stops': f['stops'] ?? 0,
        'flight_date': wanted,
        // Carried through so the card can show BOM vs NMI, or GOI vs GOX —
        // without these the row looks identical to one from the other
        // airport in the same city.
        'origin_airport': (f['origin_airport'] ?? '').toString(),
        'destination_airport': (f['destination_airport'] ?? '').toString(),
        // Marks the row as schedule-derived rather than a real fare, so the
        // UI can say where it came from.
        'from_schedule': true,
      });
    }

    setState(() {
      _searchedSchedule = true;
      _flightOptions = merged;
      _loadingFlights = false;
    });
  }

  /// "2026-09-10" -> "10 Sep", for the row subtitle.
  static String _shortDay(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('dd MMM').format(parsed);
  }

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// IATA airline codes to the names people actually type. The fare data only
  /// carries the code ("6E"), so without this "IndiGo" matches nothing — and
  /// nobody thinks of their flight as "6E1080".
  static const Map<String, String> _airlineNames = {
    '6E': 'IndiGo',
    'AI': 'Air India',
    'IX': 'Air India Express',
    'UK': 'Vistara',
    'SG': 'SpiceJet',
    'QP': 'Akasa Air',
    'G8': 'Go First',
    'I5': 'AIX Connect',
    '9I': 'Alliance Air',
    'S5': 'Star Air',
  };

  static String _airlineNameFor(String code) =>
      _airlineNames[code.toUpperCase()] ?? code;

  /// Flights matching whatever the user typed — matched against the flight
  /// number, the departure time, the airline code and the airline name, so any
  /// of them narrows the list. "6E", "18:40" and "indigo" all work, and an
  /// empty field shows everything.
  List<Map<String, dynamic>> _flightsMatching(String query) {
    // Ignore spaces and colons so "6E 405" matches "6E405" and "1840"
    // matches "18:40" — people type these inconsistently.
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s:]'), '');
    final nq = norm(query);

    return _flightOptions.where((f) {
      final code = (f['provider'] ?? '').toString();
      final number = norm((f['route_number'] ?? '').toString());
      final time = norm((f['departure_time'] ?? '').toString());
      final airline = norm(code);
      final airlineName = norm(_airlineNameFor(code));
      return number.contains(nq) ||
          time.contains(nq) ||
          airline.contains(nq) ||
          airlineName.contains(nq);
    }).toList();
  }

  /// True when the user typed something no flight matches — e.g. "SpiceJet" on
  /// a route SpiceJet doesn't fly.
  ///
  /// The list still falls back to showing everything, because leaving the user
  /// with nothing to tap is worse. But that fallback has to be labelled: an
  /// unexplained list of IndiGo flights under the word "SpiceJet" reads as a
  /// broken filter, which is exactly how it was reported.
  bool get _flightNoMatch {
    final q = _controller.text.trim();
    return q.isNotEmpty && _flightsMatching(q).isEmpty;
  }

  /// Direct flights first, then by departure time.
  ///
  /// Sorting purely by time buried them: BLR-RPR has no direct Air India
  /// service, so its one-stop connections at 00:15, 02:15, 05:30 and 06:00
  /// filled the top of the list and the direct flights were below the fold.
  /// Someone recognising the flight they took looks for a direct one first,
  /// and a screen full of connections reads as the wrong route entirely.
  List<Map<String, dynamic>> _sortedForDisplay(
      List<Map<String, dynamic>> rows) {
    final out = [...rows];
    out.sort((a, b) {
      final sa = (a['stops'] as num?)?.toInt() ?? 0;
      final sb = (b['stops'] as num?)?.toInt() ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return (a['departure_time'] ?? '')
          .toString()
          .compareTo((b['departure_time'] ?? '').toString());
    });
    return out;
  }

  List<Map<String, dynamic>> get _filteredFlights {
    final q = _controller.text.trim();
    if (q.isEmpty) return _sortedForDisplay(_flightOptions);
    final matches = _flightsMatching(q);
    return _sortedForDisplay(matches.isEmpty ? _flightOptions : matches);
  }

  /// Starts the route lookup if typing found no flights to filter.
  ///
  /// The list normally loads when the sheet opens, but that needs a route and
  /// date, and the lookup can fail or return nothing. In those cases typing
  /// used to do nothing at all — the user was filtering an empty list with no
  /// sign anything was wrong. Typing a hotel name has always triggered a
  /// search; this makes the flight field behave the same way.
  ///
  /// Cheap to call on every keystroke: it returns immediately unless the list
  /// is genuinely empty and no lookup is in flight or already done.
  void _ensureFlightsLoaded() {
    if (_flightOptions.isNotEmpty || _loadingFlights || _searchedSchedule) {
      return;
    }
    if (widget.flightDate == null ||
        widget.flightOrigin.isEmpty ||
        widget.flightDestination.isEmpty) {
      return;
    }
    _findFlightsOnRoute();
  }

  /// Whether "Save to itinerary" does anything yet.
  ///
  /// For a hotel this requires tapping a card, not merely typing. A typed name
  /// is a guess at a property we have no record of, and saving it puts an
  /// unverified hotel on the itinerary; the cards are right there, so choosing
  /// one costs a tap. Someone whose hotel genuinely isn't listed uses "I don't
  /// have it yet", which records the stay without inventing a name for it.
  ///
  /// Flights work the same way once any are listed. The exception is a route
  /// we found nothing for: with no cards to tap, requiring a tap would make
  /// the sheet impossible to complete, so a typed number is accepted there.
  bool get _canSave => _isFlight
      ? (_flightOptions.isEmpty
          ? _controller.text.trim().isNotEmpty
          : _pickedFromPlaces)
      : _selectedHotel != null;

  /// Marks a flight as the user's choice, the same way tapping a hotel card
  /// does. It does not save or close.
  ///
  /// Tapping used to confirm outright, which meant a mis-tap wrote a flight
  /// straight onto the itinerary with no chance to look at it, and the card's
  /// own selected styling could never be seen because the sheet was already
  /// gone. Selecting and saving are now two steps in both flows.
  void _pickFlight(Map<String, dynamic> flight) {
    final number = (flight['route_number'] ?? '').toString();
    final time = (flight['departure_time'] ?? '').toString();
    _debounce?.cancel();
    _controller.text = number;
    FocusScope.of(context).unfocus();
    setState(() {
      _pickedFromPlaces = true;
      _pickedDepartureTime = time.isEmpty ? null : time;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Records the booking with no flight or hotel detail, and closes at once.
  ///
  /// Deliberately does not go through [_close]. That checks a typed name
  /// against Places, which takes a couple of seconds — pointless here, since
  /// the user has just said they don't have the detail, and it made the button
  /// feel broken. Nothing typed is kept: it was rejected by the user, not
  /// entered. Any pending lookup is cancelled on the way out.
  void _dismiss() {
    _debounce?.cancel();
    Navigator.of(context).pop(const _DetailResult('', false));
  }

  /// Closes the sheet, but for a hotel name the user typed rather than picked,
  /// checks it against Places first and offers the close matches.
  ///
  /// This is the safety net for a misspelling: "amoth international" in Bhilai
  /// finds "Hotel Amit International", which the user would otherwise never be
  /// offered because they never opened the suggestion list.
  Future<void> _close() async {
    final text = _controller.text.trim();

    // Blank entries, and anything already chosen from a list, need no second
    // look.
    if (text.isEmpty || _pickedFromPlaces) {
      if (!mounted) return;
      Navigator.of(context).pop(_DetailResult(
        text,
        _pickedFromPlaces,
        departureTime: _pickedDepartureTime,
      ));
      return;
    }

    // A flight number typed rather than tapped: offer the matching flights so
    // the user confirms one, the same way a typed hotel name is checked.
    // Saving a typed number straight through means the itinerary gets a flight
    // nobody verified, and no departure time at all.
    if (_isFlight) {
      // Nothing from the fare cache: run the schedule lookup now, on Save.
      // This is the only point we know the user actually booked something and
      // wants it recorded, so it's the only point worth spending a slow,
      // billable grounded search on.
      if (_flightOptions.isEmpty && !_searchedSchedule) {
        setState(() => _verifying = true);
        await _findFlightsOnRoute();
        if (!mounted) return;
        setState(() => _verifying = false);
      }

      final candidates = _filteredFlights;
      if (candidates.isEmpty) {
        Navigator.of(context).pop(_DetailResult(text, false));
        return;
      }

      String plain(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');

      // Typed it exactly right — accept without an extra tap.
      for (final f in candidates) {
        if (plain((f['route_number'] ?? '').toString()) == plain(text)) {
          Navigator.of(context).pop(_DetailResult(
            (f['route_number'] ?? '').toString(),
            true,
            departureTime: (f['departure_time'] ?? '').toString(),
          ));
          return;
        }
      }

      final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Which one did you take?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pick your flight so we can add its departure time to your '
                  'itinerary.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              const SizedBox(height: 12),
              ...candidates.take(6).map((f) {
                final number = (f['route_number'] ?? '').toString();
                final time = (f['departure_time'] ?? '').toString();
                final arrival = (f['arrival_time'] ?? '').toString();
                final stops = (f['stops'] as num?)?.toInt() ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConfig.radiusSmall),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(AppConfig.radiusSmall),
                    onTap: () => Navigator.of(dialogCtx).pop(f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.flight_takeoff,
                              size: 20, color: AppConfig.primaryColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_airlineNameFor((f['provider'] ?? '').toString())}'
                                  '${number.isEmpty ? '' : ' · $number'}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (time.isNotEmpty)
                                      arrival.isEmpty
                                          ? 'Departs $time'
                                          : '$time – $arrival',
                                    stops == 0
                                        ? 'Non-stop'
                                        : '$stops stop(s)',
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: Colors.grey[500]),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              // Back to the field, text intact, so a mistyped flight number
              // can be corrected instead of accepted or forced through.
              onPressed: () => Navigator.of(dialogCtx)
                  .pop(<String, dynamic>{'_edit': true}),
              child: const Text('Edit'),
            ),
            TextButton(
              // The route may run flights the schedule doesn't list.
              onPressed: () => Navigator.of(dialogCtx).pop(<String, dynamic>{}),
              child: Text('Keep "$text"'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      // Dismissed, or "Edit": stay on the sheet so the text can be changed.
      if (chosen == null || chosen['_edit'] == true) return;
      if (chosen.isEmpty) {
        Navigator.of(context).pop(_DetailResult(text, false));
      } else {
        Navigator.of(context).pop(_DetailResult(
          (chosen['route_number'] ?? '').toString(),
          true,
          departureTime: (chosen['departure_time'] ?? '').toString(),
        ));
      }
      return;
    }

    setState(() => _verifying = true);
    final matches = await _adkService.searchHotelNames(
        query: text, city: widget.city, limit: 5);
    if (!mounted) return;
    setState(() => _verifying = false);

    // null means the lookup itself failed (server down, timeout). Save the
    // name and say so — blaming the user's spelling for our own outage is
    // both wrong and unhelpable.
    if (matches == null) {
      Navigator.of(context).pop(_DetailResult(text, false, lookupFailed: true));
      return;
    }

    if (matches.isEmpty) {
      // Genuinely no match — save exactly what they wrote, flagged unverified.
      Navigator.of(context).pop(_DetailResult(text, false));
      return;
    }

    // Already exactly right (bar casing): accept it as a real property
    // without making the user confirm something they got correct.
    for (final m in matches) {
      if ((m['name'] ?? '').toLowerCase() == text.toLowerCase()) {
        Navigator.of(context).pop(_DetailResult(m['name']!, true));
        return;
      }
    }

    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Did you mean?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We couldn\'t find "$text". Closest matches'
                '${widget.city.isEmpty ? '' : ' in ${widget.city}'}:',
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            const SizedBox(height: 12),
            // Cards, matching the flight picker — these are things to choose
            // between, and a bordered card reads as tappable in a way a bare
            // row does not.
            ...matches.map((m) {
              final name = m['name'] ?? '';
              final address = m['address'] ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  onTap: () => Navigator.of(dialogCtx).pop(name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.hotel,
                            size: 20, color: AppConfig.primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              if (address.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(address,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[700])),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: Colors.grey[500]),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            // Back to the field with the text intact, for the common case:
            // they mistyped and want to correct it rather than accept a
            // near-miss or save the typo.
            onPressed: () => Navigator.of(dialogCtx).pop(_editSentinel),
            child: const Text('Edit name'),
          ),
          TextButton(
            // Escape hatch: the hotel may genuinely not be on Places, and the
            // user knows where they slept better than a search index does.
            onPressed: () => Navigator.of(dialogCtx).pop(_keepSentinel),
            child: Text('Keep "$text"'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    // Dismissing (barrier tap / back gesture) means "I didn't choose", which
    // is closer to editing than to saving — never save something the user
    // walked away from.
    if (chosen == null || chosen == _editSentinel) return;
    if (chosen == _keepSentinel) {
      Navigator.of(context).pop(_DetailResult(text, false));
    } else {
      Navigator.of(context).pop(_DetailResult(chosen, true));
    }
  }

  /// Hotels already in memory whose name contains [query] — the instant half
  /// of the lookup, shown while the Places call is still in flight so the list
  /// reacts on the keystroke rather than after a round trip.
  ///
  /// Searches the city list and every cached response, deliberately not the
  /// currently displayed [_suggestions]: filtering the visible list would make
  /// it shrink-only, so backspacing could never bring a hotel back.
  List<Map<String, String>> _localMatches(String query) {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final h in [..._cityHotels, ..._hotelCache.values.expand((e) => e)]) {
      final name = h['name'] ?? '';
      if (name.toLowerCase().contains(query) && seen.add(name.toLowerCase())) {
        out.add(h);
      }
    }
    return out;
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // Editing after picking makes it free text again.
    _pickedFromPlaces = false;
    _selectedHotel = null;
    _noMatch = false;

    final query = value.trim().toLowerCase();
    // Below the useful-query threshold, fall back to the city list rather than
    // an empty box — clearing the field should return the user to where they
    // started, not to nothing.
    if (query.length < 2) {
      setState(() {
        _suggestions = _cityHotels;
        _lookingUp = false;
      });
      return;
    }

    // Instant pass: a cached response for this exact query, otherwise a local
    // filter over what's already on screen.
    final cached = _hotelCache[query];
    final immediate = cached ?? _localMatches(query);
    setState(() {
      if (immediate.isNotEmpty) _suggestions = immediate;
      _lookingUp = cached == null;
    });
    if (cached != null) return;

    // 250ms rather than the onboarding fields' 120ms: each miss here is a
    // billed Places call taking ~2s, and the instant pass above already
    // covers the gap, so a shorter debounce would buy responsiveness the
    // user can't perceive at roughly double the API spend.
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final found = await _adkService.searchHotelNames(
          query: query, city: widget.city, limit: 6);
      if (!mounted) return;
      // Ignore a response the user has already typed past.
      if (_controller.text.trim().toLowerCase() != query) return;
      setState(() {
        // null = lookup failed. Keep whatever was already on screen rather
        // than blanking the list on a transient error.
        if (found != null) {
          _hotelCache[query] = found;
          // An empty result must not empty the list. The point of this sheet
          // is to let the user tap their hotel instead of spelling it, so a
          // query we can't match is exactly when they most need the city
          // list back — showing nothing sends them back to typing.
          _noMatch = found.isEmpty;
          _suggestions = found.isNotEmpty ? found : _cityHotels;
        }
        _lookingUp = false;
      });
    });
  }

  /// Marks a suggestion as the user's choice. Deliberately does not save or
  /// close: the list stays up with the selection ticked so they can change
  /// their mind, and "Save to itinerary" is the only thing that commits.
  void _pick(String name) {
    _debounce?.cancel();
    _controller.text = name;
    _pickedFromPlaces = true;
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedHotel = name;
      _lookingUp = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      // Scrollable, because the content genuinely can't always fit: title,
      // field, a list of flights, the hint and two buttons overflowed by 65px
      // on a short browser window and the Save button was cut in half. The
      // list below is separately capped, so this only has to absorb what's
      // left over.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(
              _isFlight
                  ? 'Which flight did you book?'
                  : 'Which hotel did you book?',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              _isFlight && _flightOptions.isNotEmpty
                  ? 'Type a flight number, time or airline to narrow the list, '
                      'then tap your flight.'
                  : 'You\'ll find it on your booking confirmation.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),

          if (_isFlight && _loadingFlights) ...[
            const Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Finding flights on this route…',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 16),
          ],

          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: _isFlight
                ? TextCapitalization.characters
                : TextCapitalization.words,
            textInputAction: TextInputAction.done,
            // For flights this filters the list below rather than doing a
            // lookup — the candidates are already loaded, so matching happens
            // locally against number, time and airline.
            // setState on every change so the Save button's enabled state
            // tracks whether the field has anything in it.
            onChanged: _isFlight
                // Typing after tapping a flight drops the selection *and* its
                // departure time — keeping the time would attach the tapped
                // flight's departure to whatever number is now in the box.
                ? (_) {
                    setState(() {
                      _pickedFromPlaces = false;
                      _pickedDepartureTime = null;
                    });
                    _ensureFlightsLoaded();
                  }
                : (value) {
                    setState(() {});
                    _onQueryChanged(value);
                  },
            onSubmitted: (_) => _close(),
            decoration: InputDecoration(
              labelText: _isFlight
                  ? 'Flight number, time or airline'
                  : 'Hotel name',
              hintText: _isFlight
                  ? 'e.g. 6E 405, 18:40, or IndiGo'
                  : 'e.g. Hotel City Lite',
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
              ),
            ),
          ),
          // Real departures for this route and date. Tapping one fills in both
          // the flight number and its time, so the user never has to remember
          // either — they just recognise the flight they took.
          if (_isFlight && _flightOptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _pickedFromPlaces
                  ? 'Selected — tap "Save to itinerary" to add it'
                  : _flightNoMatch
                      ? 'No flight matches "${_controller.text.trim()}" on this '
                          'route — showing all flights that day'
                      : 'Tap the flight you took',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _pickedFromPlaces
                    ? AppConfig.primaryColor
                    : _flightNoMatch
                        ? Colors.orange[800]
                        : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              // Proportional, not a fixed 260: on a short window that fixed
              // height left no room for the Save button underneath it.
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.of(context).size.height * 0.34)
                    .clamp(140.0, 260.0),
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: _filteredFlights.map((f) {
                    final number = (f['route_number'] ?? '').toString();
                    final time = (f['departure_time'] ?? '').toString();
                    final duration = (f['duration'] ?? '').toString();
                    final fromApt = (f['origin_airport'] ?? '').toString();
                    final toApt = (f['destination_airport'] ?? '').toString();
                    final airportPair = (fromApt.isNotEmpty && toApt.isNotEmpty)
                        ? '$fromApt → $toApt'
                        : '';
                    final stops = (f['stops'] as num?)?.toInt() ?? 0;
                    final selected = _controller.text.trim() == number &&
                        _pickedDepartureTime == (time.isEmpty ? null : time);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: selected
                          ? AppConfig.primaryColor.withValues(alpha: 0.10)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConfig.radiusSmall),
                        side: BorderSide(
                          color: selected
                              ? AppConfig.primaryColor
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.flight_takeoff,
                          size: 20,
                          color: AppConfig.primaryColor,
                        ),
                        // Airline name first — that's how people recognise a
                        // flight, not by its IATA code.
                        title: Text(
                            '${_airlineNameFor((f['provider'] ?? '').toString())}'
                            '${number.isEmpty ? '' : ' · $number'}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            // Date included so a mismatched day is visible
                            // rather than something the user has to trust.
                            if ((f['flight_date'] ?? '').toString().isNotEmpty)
                              _shortDay(f['flight_date'].toString()),
                            if (time.isNotEmpty) 'Departs $time',
                            // Which airports, when the cities have more than
                            // one. Mumbai flights leave from BOM or NMI and
                            // Goa flights land at GOI or GOX; those are far
                            // enough apart that picking the wrong row puts
                            // the user at the wrong airport.
                            if (airportPair.isNotEmpty) airportPair,
                            if (duration.isNotEmpty) duration,
                            stops == 0 ? 'Non-stop' : '$stops stop(s)',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => _pickFlight(f),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                _flightOptions.first['from_schedule'] == true
                    ? 'From published schedules — check against your ticket. '
                        'Not listed? What you type above is saved as-is.'
                    : 'Not listed? Whatever you type above is saved as-is when '
                        'you tap Save.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],

          // Both sources came back empty.
          if (_isFlight &&
              !_loadingFlights &&
              _flightOptions.isEmpty &&
              _searchedSchedule) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No schedule found for this route and date — enter the '
                    'flight number yourself.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ],
          // Real properties from Google Places. Tapping one replaces whatever
          // was typed, so a misspelling still ends up as the hotel's actual
          // name — when Places can find it.
          // First load only — afterwards the field's own suffix spinner covers
          // refinements, so the list doesn't jump while the user types.
          if (!_isFlight && _lookingUp && _suggestions.isEmpty) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Finding hotels…', style: TextStyle(fontSize: 13)),
              ],
            ),
          ],
          if (!_isFlight && _suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _selectedHotel != null
                  ? 'Selected — tap "Save to itinerary" to add it'
                  : _noMatch
                      ? 'No match for that — other hotels in ${widget.city}'
                      : _controller.text.trim().isEmpty
                          ? 'Hotels in ${widget.city} — tap the one you booked'
                          : 'Did you mean one of these?',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _selectedHotel != null
                    ? AppConfig.primaryColor
                    : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  children: _suggestions.map((s) {
                    final name = s['name'] ?? '';
                    final address = s['address'] ?? '';
                    final selected = _selectedHotel == name;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      color: selected
                          ? AppConfig.primaryColor.withValues(alpha: 0.08)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConfig.radiusSmall),
                        side: BorderSide(
                          color: selected
                              ? AppConfig.primaryColor
                              : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppConfig.radiusSmall),
                        onTap: () => _pick(name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.check_circle : Icons.hotel,
                                  size: 20, color: AppConfig.primaryColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    if (address.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(address,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[700])),
                                    ],
                                  ],
                                ),
                              ),
                              if (!selected)
                                Icon(Icons.chevron_right,
                                    size: 18, color: Colors.grey[500]),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Says why the button is dead. A greyed button with no explanation
          // reads as broken; naming the missing step turns it into an
          // instruction.
          if (!_canSave && !_verifying) ...[
            Text(
              _isFlight
                  ? 'Tap the flight you took to enable saving'
                  : 'Tap the hotel you booked to enable saving',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
          ],

          // Always shown now. It used to be hidden whenever flights were
          // listed, because tapping one saved outright; now that tapping only
          // selects, hiding the button would leave nothing to confirm with.
          SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_verifying || !_canSave) ? null : _close,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                  // Stated explicitly. With only backgroundColor set, the
                  // disabled button kept enough of its colour to look
                  // tappable, so "nothing selected" read as a broken button
                  // rather than a deliberate state.
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_verifying) ...[
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(_verifying ? 'Checking…' : 'Save to itinerary'),
                  ],
                ),
              ),
            ),
          TextButton(
            onPressed: _dismiss,
            child: const Text('I don\'t have it yet'),
          ),
          ],
        ),
      ),
    );
  }
}
