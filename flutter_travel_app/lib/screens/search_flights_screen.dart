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
  }

  /// The onboarding city, kept exactly as entered — including the state.
  ///
  /// This used to cut "Bilaspur, Chhattisgarh, India" down to "Bilaspur",
  /// which is the one detail that separates it from the Bilaspur in Himachal
  /// Pradesh 1150km away. The airport lookup geocodes whatever it is given,
  /// so dropping the state made a same-named city in another state a valid
  /// answer. India has many of these — Bilaspur, Hyderabad, Aurangabad — so
  /// the region travels with the name from here on.
  String? _matchFlightCity(String? rawCity) {
    final city = rawCity?.trim();
    return (city == null || city.isEmpty) ? null : city;
  }

  /// IATA codes for the chosen cities, set when a suggestion is tapped.
  /// Null means nothing real has been picked, so no route can be built.
  String? _originIata;
  String? _destinationIata;

  /// Set when the chosen airport isn't in the typed city, so the substitution
  /// stays visible after the suggestion list closes.
  String? _originNote;
  String? _destinationNote;

  /// True once both fields hold a real airport, i.e. the redirect lands on a
  /// prefilled route search rather than the Aviasales homepage.
  bool get _willPrefillRoute => _originIata != null && _destinationIata != null;

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
    // Text in the box isn't a chosen airport. A city carried over from
    // onboarding shows in the field but has no code behind it until it's
    // picked, and searching anyway sent the user to the Aviasales homepage
    // with nothing filled in — which looked like the search had worked.
    if (_originIata == null || _destinationIata == null) {
      final which = _originIata == null ? 'From' : 'To';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pick an airport from the $which list')),
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
        originIataOverride: _originIata,
        destinationIataOverride: _destinationIata,
      )),
      kind: BookingKind.flight,
      title: '$_origin → $_destination',
      startDate: _departDate,
      endDate: _roundTrip ? _returnDate : null,
      // Lets the prompt list the real departures on this route so the user
      // can tap the flight they took instead of recalling its number.
      flightOrigin: _origin!,
      flightDestination: _destination!,
      flightOriginIata: _originIata ?? '',
      flightDestinationIata: _destinationIata ?? '',
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
            _AirportField(
              label: 'From',
              icon: Icons.flight_takeoff,
              initialText: _origin ?? '',
              onSelected: (city, iata, note) => setState(() {
                _origin = city;
                _originIata = iata;
                _originNote = note;
              }),
            ),
            const SizedBox(height: 12),
            _AirportField(
              label: 'To',
              icon: Icons.flight_land,
              initialText: _destination ?? '',
              onSelected: (city, iata, note) => setState(() {
                _destination = city;
                _destinationIata = iata;
                _destinationNote = note;
              }),
            ),

            // Kept on screen after the suggestion list closes, so the reason
            // a Bhilai trip flies from Raipur doesn't disappear on selection.
            for (final note in [_originNote, _destinationNote])
              if (note != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(note,
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade900)),
                      ),
                    ],
                  ),
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
            // Cities without an IATA mapping can't be encoded into an Aviasales
            // route URL, so the link lands on their homepage instead. Say so
            // rather than letting the user discover it after tapping.
            if (_origin != null &&
                _destination != null &&
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

/// A From/To field that searches real airports as the user types.
///
/// Replaces a dropdown of 37 hardcoded cities, which is why anywhere else had
/// to be guessed at. Suggestions come from the full airport dataset, so cities
/// with two airports offer both (Mumbai BOM and NMI), and a city with none
/// falls back to the nearest one rather than silently failing.
class _AirportField extends StatefulWidget {
  const _AirportField({
    required this.label,
    required this.icon,
    required this.initialText,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final String initialText;

  /// [note] is set only when the airport isn't in the typed city, e.g.
  /// "Bhilai has no airport. Flights use Swami Vivekananda Airport (RPR)…".
  final void Function(String city, String? iata, String? note) onSelected;

  @override
  State<_AirportField> createState() => _AirportFieldState();
}

class _AirportFieldState extends State<_AirportField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final PythonADKService _adk = PythonADKService();

  List<AirportOption> _options = [];
  Timer? _debounce;
  bool _searching = false;
  bool _picked = false;

  /// Shown when the typed place has no airport of its own — either naming the
  /// airport we'd use instead, or saying we found nothing at all.
  String? _fallbackNote;
  AirportOption? _fallbackOption;

  @override
  void initState() {
    super.initState();
    // A city carried over from onboarding starts as plain text with no
    // airport behind it. Looking it up straight away turns it into a
    // tappable card — including the nearest-airport card for somewhere like
    // Bilaspur — instead of leaving it looking already chosen when it isn't.
    if (widget.initialText.trim().length >= 2) {
      _search(widget.initialText);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _picked = false;
      _fallbackNote = null;
      _fallbackOption = null;
    });
    // Clearing the field clears the selection, so a stale airport can't be
    // searched with an empty box on screen.
    widget.onSelected(value.trim(), null, null);
    if (value.trim().length < 2) {
      setState(() {
        _options = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 150), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    final found = await _adk.searchAirports(query);
    if (!mounted || _controller.text.trim() != query) return;

    // null means the lookup itself failed — server down, or running a build
    // without this endpoint. Falling through to the nearest-airport guess
    // here is how "rpr" became "rpr (BLR)": the search never ran, and the
    // geocoder happily placed the string near Bangalore. Say so instead.
    if (found == null) {
      setState(() {
        _options = [];
        _searching = false;
        _fallbackOption = null;
        _fallbackNote = "Couldn't reach the airport list. Check the server "
            'is running, then try again.';
      });
      return;
    }

    if (found.isNotEmpty) {
      setState(() {
        _options = found;
        _searching = false;
      });
      return;
    }

    // No airport by that name. Ask the server what the nearest one is before
    // telling the user there's nothing — most places without an airport are
    // still perfectly reachable, just from a neighbouring city.
    final resolved = await _adk.resolveAirport(query);
    if (!mounted || _controller.text.trim() != query) return;
    setState(() {
      _options = [];
      _searching = false;
      // Only a genuine substitution is offered. A result claiming the typed
      // place has its own airport contradicts the search that just found
      // nothing, and that combination is exactly what produced "rpr (BLR)" —
      // a geocode of the string "rpr" landing near Bangalore and reporting
      // itself as an exact match. Treat it as no match.
      final shortName = _shortCity(query);
      if (resolved == null || resolved.iata.isEmpty || !resolved.substituted) {
        _fallbackNote = 'No airport found for "$shortName".';
      } else {
        _fallbackOption = AirportOption(
          code: resolved.iata,
          name: resolved.airportName,
          // The airport's own city, not the one typed. Flying to Bhilai means
          // flying into Raipur, so the field should read "Raipur (RPR)" —
          // "Bhilai (RPR)" names a city that has no airport in it. The note
          // below still explains the connection.
          city: resolved.city.isNotEmpty ? resolved.city : shortName,
        );
        _fallbackNote = '$shortName has no airport. Nearest is '
            '${resolved.airportName} (${resolved.iata}), '
            '${resolved.distanceKm} km away.';
      }
    });
  }

  /// "Bhilai, Chhattisgarh, India" -> "Bhilai".
  ///
  /// The qualified form is what gets sent to the server, since the state is
  /// what tells two same-named cities apart, but it makes a poor label: the
  /// field read "Bhilai, Chhattisgarh, India (RPR)".
  static String _shortCity(String city) => city.split(',').first.trim();

  void _pick(AirportOption option, {String? note}) {
    _debounce?.cancel();
    _controller.text = '${_shortCity(option.city)} (${option.code})';
    FocusScope.of(context).unfocus();
    setState(() {
      _picked = true;
      _options = [];
      _searching = false;
      // Cleared, not kept. The parent shows this note in its own callout, and
      // holding onto it here printed the same sentence twice, once under the
      // field and once below it.
      _fallbackNote = null;
      _fallbackOption = null;
    });
    widget.onSelected(option.city, option.code, note);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'City or airport',
            prefixIcon: Icon(widget.icon),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _picked
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
            ),
          ),
        ),
        for (final option in _options)
          Card(
            margin: const EdgeInsets.only(top: 6),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: AppConfig.primaryColor.withValues(alpha: 0.1),
                child: Text(option.code,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppConfig.primaryColor)),
              ),
              title: Text(_shortCity(option.city),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              onTap: () => _pick(option),
            ),
          ),
        // The nearest airport for a city that has none, offered as a card so
        // it is chosen deliberately rather than substituted behind the scenes.
        if (_fallbackOption != null)
          Card(
            margin: const EdgeInsets.only(top: 6),
            elevation: 0,
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.near_me, color: Colors.blue.shade800),
              title: Text('Nearest airport: ${_fallbackOption!.code}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(_fallbackNote ?? _fallbackOption!.name,
                  style: const TextStyle(fontSize: 11)),
              onTap: () => _pick(_fallbackOption!, note: _fallbackNote),
            ),
          )
        else if (_fallbackNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              _fallbackNote!,
              style: TextStyle(fontSize: 12, color: Colors.orange[800]),
            ),
          ),
      ],
    );
  }
}
