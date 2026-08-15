import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/confirmed_booking.dart';
import '../services/affiliate_links.dart';
import '../services/python_adk_service.dart';
import '../providers/user_preferences_provider.dart';
import '../widgets/booking_confirm_prompt.dart';

/// Flight search entry point. There is no in-app results list: Aviasales owns
/// search, pricing and booking, and its live search shows far more than the
/// affiliate price cache can (full schedules, baggage, seats remaining), so
/// redirecting gives the user a better result than mirroring a partial copy.
///
/// The redirect never reports back, so on return we ask the user whether they
/// booked — that answer is what the itinerary is built from.
class SearchFlightsScreen extends StatefulWidget {
  const SearchFlightsScreen({super.key});

  @override
  State<SearchFlightsScreen> createState() => _SearchFlightsScreenState();
}

class _SearchFlightsScreenState extends State<SearchFlightsScreen> {
  String? _origin;
  String? _destination;
  bool _roundTrip = false;
  DateTime _departDate = DateTime.now().add(const Duration(days: 7));
  DateTime? _returnDate;
  int _passengers = 1;

  static final DateFormat _displayDate = DateFormat('dd MMM yyyy');
  final PythonADKService _adkService = PythonADKService();

  @override
  void initState() {
    super.initState();
    // Default from onboarding's trip basics (origin/destination/dates), same
    // source of truth the hotel search screen prefills from, so a flight and
    // a hotel for the same trip don't end up with mismatched dates.
    final prefs = Provider.of<UserPreferencesProvider>(
      context,
      listen: false,
    ).preferences;

    _origin = _matchFlightCity(prefs.origin);
    _destination = _matchFlightCity(prefs.destination);

    final now = DateTime.now();
    if (prefs.checkInDate != null) {
      _departDate = prefs.checkInDate!.isBefore(now) ? now : prefs.checkInDate!;
    }
    if (prefs.checkOutDate != null &&
        prefs.checkOutDate!.isAfter(_departDate)) {
      _returnDate = prefs.checkOutDate;
      _roundTrip = true;
    }

    // Onboarding cities are free text and often aren't in the built-in map,
    // which is exactly the case this resolves.
    _resolveAirports();
  }

  /// Normalises a free-text onboarding city (e.g. "Gownipalli, Karnataka,
  /// India"), preferring the canonical spelling from flightCities when it
  /// matches. Unmatched cities are kept rather than discarded so the trip
  /// entered during onboarding always carries over — see [_cityOptions].
  String? _matchFlightCity(String? rawCity) {
    if (rawCity == null || rawCity.trim().isEmpty) return null;
    final city = rawCity.split(',').first.trim();
    if (city.isEmpty) return null;
    for (final candidate in AffiliateLinks.flightCities) {
      if (candidate.toLowerCase() == city.toLowerCase()) return candidate;
    }
    return city;
  }

  /// Known flight cities plus whatever came from onboarding if it isn't among
  /// them. Without this a prefilled value outside the list would throw, since
  /// DropdownButtonFormField requires its value to match exactly one item.
  List<String> get _cityOptions {
    final options = [...AffiliateLinks.flightCities];
    for (final extra in [_origin, _destination]) {
      if (extra != null &&
          extra.isNotEmpty &&
          !options.any((c) => c.toLowerCase() == extra.toLowerCase())) {
        options.insert(0, extra);
      }
    }
    return options;
  }

  /// Airport codes for cities the built-in map doesn't cover, resolved by the
  /// server — which also substitutes the nearest airport when a city has none
  /// of its own, so Bilaspur searches from Raipur rather than nowhere.
  AirportResolution? _originAirport;
  AirportResolution? _destinationAirport;
  bool _resolvingAirports = false;

  String? _iataFor(String? city, AirportResolution? resolved) {
    if (city == null) return null;
    return AffiliateLinks.iataCodeFor(city) ?? resolved?.iata;
  }

  /// Looks up whichever of the two cities the built-in map can't handle.
  /// Cheap and cached server-side, so it just re-runs whenever a city changes.
  Future<void> _resolveAirports() async {
    setState(() => _resolvingAirports = true);
    final results = await Future.wait([
      (_origin != null && AffiliateLinks.iataCodeFor(_origin!) == null)
          ? _adkService.resolveAirport(_origin!)
          : Future<AirportResolution?>.value(null),
      (_destination != null &&
              AffiliateLinks.iataCodeFor(_destination!) == null)
          ? _adkService.resolveAirport(_destination!)
          : Future<AirportResolution?>.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _originAirport = results[0];
      _destinationAirport = results[1];
      _resolvingAirports = false;
    });
  }

  /// True when both cities map to an IATA code, i.e. the redirect lands on a
  /// prefilled route search rather than the Aviasales homepage.
  bool get _willPrefillRoute =>
      _iataFor(_origin, _originAirport) != null &&
      _iataFor(_destination, _destinationAirport) != null;

  /// Airports we substituted, so the user is told before booking rather than
  /// finding out on the day of travel.
  List<(String, AirportResolution)> get _substitutions => [
        if (_origin != null && (_originAirport?.substituted ?? false))
          (_origin!, _originAirport!),
        if (_destination != null && (_destinationAirport?.substituted ?? false))
          (_destination!, _destinationAirport!),
      ];

  Future<void> _pickDepartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _departDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _departDate = picked;
      if (_returnDate != null && _returnDate!.isBefore(_departDate)) {
        _returnDate = _departDate.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickReturnDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate ?? _departDate.add(const Duration(days: 1)),
      firstDate: _departDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _returnDate = picked);
  }

  Future<void> _search() async {
    if (_origin == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select origin and destination')),
      );
      return;
    }
    if (_origin == _destination) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Origin and destination must differ')),
      );
      return;
    }

    // No schedule prefetch here on purpose. It was a web-grounded model call
    // on every search — slow and billable — and most searches never end in a
    // booking. The confirmation sheet offers it as a button instead, so it
    // only runs for someone who actually wants help identifying their flight.
    await BookingConfirmPrompt.launchAndConfirm(
      context,
      launch: () => AffiliateLinks.open(AffiliateLinks.aviasalesFlightSearch(
        originCity: _origin!,
        destinationCity: _destination!,
        departDate: _departDate,
        returnDate: _roundTrip ? _returnDate : null,
        passengers: _passengers,
        originIataOverride: _originAirport?.iata,
        destinationIataOverride: _destinationAirport?.iata,
      )),
      kind: BookingKind.flight,
      title: '$_origin → $_destination',
      startDate: _departDate,
      endDate: _roundTrip ? _returnDate : null,
      // Lets the prompt list the real departures on this route so the user
      // can tap the flight they took instead of recalling its number.
      flightOrigin: _origin!,
      flightDestination: _destination!,
      flightOriginIata: _iataFor(_origin, _originAirport) ?? '',
      flightDestinationIata: _iataFor(_destination, _destinationAirport) ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Flights'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConfig.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Where?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _origin,
              decoration: InputDecoration(
                labelText: 'From',
                prefixIcon: const Icon(Icons.flight_takeoff),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                ),
              ),
              items: _cityOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                setState(() => _origin = value);
                _resolveAirports();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _destination,
              decoration: InputDecoration(
                labelText: 'To',
                prefixIcon: const Icon(Icons.flight_land),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                ),
              ),
              items: _cityOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                setState(() => _destination = value);
                _resolveAirports();
              },
            ),
            const SizedBox(height: 20),
            const Text('When?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Round trip'),
                Switch(
                  value: _roundTrip,
                  onChanged: (value) => setState(() {
                    _roundTrip = value;
                    if (value) {
                      _returnDate ??= _departDate.add(const Duration(days: 7));
                    }
                  }),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickDepartDate,
                    child: Text('Depart: ${_displayDate.format(_departDate)}'),
                  ),
                ),
                if (_roundTrip) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickReturnDate,
                      child: Text(
                        _returnDate == null
                            ? 'Return'
                            : 'Return: ${_displayDate.format(_returnDate!)}',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const Text('Passengers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                      () => _passengers = (_passengers - 1).clamp(1, 9)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_passengers ${_passengers == 1 ? 'Passenger' : 'Passengers'}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                      () => _passengers = (_passengers + 1).clamp(1, 9)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppConfig.primaryGradient,
                  borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                ),
                child: ElevatedButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search, color: Colors.white),
                  label: const Text(
                    'Search Flights',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConfig.radiusMedium),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Opens Aviasales in your browser to complete the search and '
              'booking. We\'ll ask if you booked so we can add it to your trip.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            // A city with no airport of its own flies from somewhere else.
            // Said here, before booking, rather than left for the user to
            // discover on the day of travel.
            if (_resolvingAirports)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Checking nearest airports…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              for (final (city, airport) in _substitutions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$city has no airport — flying from ${airport.airportName} '
                    '(${airport.iata}), ${airport.distanceKm} km away.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                  ),
                ),
            // Cities without an IATA mapping can't be encoded into an Aviasales
            // route URL, so the link lands on their homepage instead. Say so
            // rather than letting the user discover it after tapping.
            if (_origin != null &&
                _destination != null &&
                !_resolvingAirports &&
                !_willPrefillRoute)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Aviasales will open on its search page — this route isn\'t '
                  'prefilled, so you\'ll need to enter the cities there.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
