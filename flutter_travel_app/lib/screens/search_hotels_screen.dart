import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:animate_do/animate_do.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../services/affiliate_links.dart';
import '../services/python_adk_service.dart';
import '../services/google_places_service.dart';
import '../models/hotel.dart';
import '../models/confirmed_booking.dart';
import '../providers/user_preferences_provider.dart';
import '../providers/hotel_shortlist_provider.dart';
import '../widgets/booking_confirm_prompt.dart';
import 'hotel_shortlist_screen.dart';

class SearchHotelsScreen extends StatefulWidget {
  const SearchHotelsScreen({super.key});

  @override
  State<SearchHotelsScreen> createState() => _SearchHotelsScreenState();
}

class _SearchHotelsScreenState extends State<SearchHotelsScreen> {
  final PythonADKService _adkService = PythonADKService();
  final GooglePlacesService _placesService = GooglePlacesService();

  // City autocomplete. Mirrors the onboarding field: Google Places is called
  // straight from the app (fast) with the Python backend only as a fallback,
  // and cached/local matches are painted immediately so the list never looks
  // frozen while a request is in flight.
  /// Red used for the required-field marker and the empty-city highlight.
  /// Darker than Colors.red so it holds contrast against the white field.
  static const Color _errorColor = Color(0xFFD32F2F);

  /// Highlights the city field in red. Stays false until the user actually
  /// tries to search — painting the form red on open, before they've typed
  /// anything, reads as failure rather than guidance.
  bool _showCityError = false;

  /// The picked city including its region ("Bilaspur, Himachal Pradesh,
  /// India"), kept alongside the short display name.
  ///
  /// [_selectedCity] stays short because the hotel search and screen titles
  /// want a plain name, but the Aviasales handoff needs the region — two
  /// Indian cities share the name Bilaspur, and a bare one always resolves to
  /// the Chhattisgarh one. Null when the user typed freely rather than
  /// choosing a suggestion, since then we have no region to offer.
  String? _selectedCityQualified;

  final TextEditingController _cityController = TextEditingController();
  final Map<String, List<Map<String, String>>> _citySuggestionCache = {};
  List<Map<String, String>> _citySuggestions = [];
  Timer? _cityDebounce;
  bool _loadingCities = false;
  String _lastCityQuery = '';

  /// Shown instantly when nothing is cached yet, so the very first keystrokes
  /// still produce a list. Replaced as soon as a real lookup returns.
  static const List<String> _localCityFallback = [
    'Bengaluru, India',
    'Mumbai, India',
    'Delhi, India',
    'Hyderabad, India',
    'Chennai, India',
    'Pune, India',
    'Kolkata, India',
    'Ahmedabad, India',
    'Jaipur, India',
    'Goa, India',
    'Kochi, India',
    'Lucknow, India',
    'Indore, India',
    'Surat, India',
    'Nagpur, India',
  ];
  String? _selectedCity;
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _guests = 2;


  // Hotel preferences from home screen
  String? _roomType;
  List<String> _foodTypes = [];
  String? _ambiance;
  List<String> _extras = [];

  List<Hotel> _searchResults = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    // Get DNS + TLS to the hotel partner out of the way now, so tapping
    // "Book" later doesn't pay for connection setup on top of the redirect
    // chain. Fire-and-forget; failure changes nothing.
    AffiliateLinks.prewarmHotelPartner();
    // Get parameters passed from home screen
    final arguments = Get.arguments;
    if (arguments != null && arguments is Map<String, dynamic>) {
      final cityInput = arguments['city'] as String?;
      setState(() {
        if (cityInput != null && cityInput.isNotEmpty) {
          _selectedCity = _resolveCity(cityInput);
        }
        _checkIn = arguments['checkIn'] as DateTime? ?? DateTime.now();
        _checkOut = arguments['checkOut'] as DateTime? ??
            DateTime.now().add(const Duration(days: 1));
        _guests = arguments['guests'] as int? ?? 2;

        // Get hotel preferences
        _roomType = arguments['roomType'] as String?;
        _foodTypes =
            (arguments['foodTypes'] as List<dynamic>?)?.cast<String>() ?? [];
        _ambiance = arguments['ambiance'] as String?;
        _extras = (arguments['extras'] as List<dynamic>?)?.cast<String>() ?? [];
      });
      // Prefill only. The screen deliberately does NOT search on open: hotel
      // search takes seconds, so an automatic run left the form locked behind
      // a spinner before the user had chosen anything, and any failure fired
      // side effects (snackbars, handoffs) they never asked for. Searching is
      // now always an explicit action.
      if (_selectedCity != null) {
        _cityController.text = _selectedCity!;
      }
    } else {
      // No GetX arguments (e.g. opened via the Home quick-access card, which
      // uses a plain Navigator.push) — fall back to whatever destination/
      // dates/guests were saved during onboarding.
      final prefs = Provider.of<UserPreferencesProvider>(
        context,
        listen: false,
      ).preferences;

      final destinationCity = prefs.destination?.split(',').first.trim();
      if (destinationCity != null && destinationCity.isNotEmpty) {
        setState(() {
          _selectedCity = _resolveCity(destinationCity);
          if (prefs.checkInDate != null) _checkIn = prefs.checkInDate!;
          if (prefs.checkOutDate != null) _checkOut = prefs.checkOutDate!;
          // Guests intentionally starts at 0 regardless of the trip's
          // traveler count — the two are tracked independently.
        });

        // Prefill only — see the note on the arguments branch above.
        _cityController.text = _selectedCity!;
      }
    }
  }

  /// Kept only to strip any country/state suffix ("Raipur, Chhattisgarh,
  /// India" -> "Raipur"). The old version also had to force the value into a
  /// fixed dropdown list; with a free-text field that's no longer needed.
  String _resolveCity(String rawCity) => rawCity.split(',').first.trim();

  @override
  void dispose() {
    _cityDebounce?.cancel();
    _cityController.dispose();
    super.dispose();
  }

  /// Debounced so a fast typist doesn't fire a request per keystroke.
  void _updateCitySuggestions(String query) {
    final normalized = query.trim();
    // Typing invalidates any previous pick — otherwise a stale _selectedCity
    // could be searched while the field shows something else entirely, and a
    // previously-picked region could end up attached to a different city.
    _selectedCity = normalized.isEmpty ? null : normalized;
    _selectedCityQualified = null;

    // Clear the red as soon as they start fixing it, rather than making them
    // search again to find out it's satisfied.
    if (_showCityError && normalized.isNotEmpty) {
      setState(() => _showCityError = false);
    }

    _cityDebounce?.cancel();
    if (normalized.length < 2) {
      setState(() {
        _citySuggestions = [];
        _loadingCities = false;
      });
      return;
    }
    if (normalized.toLowerCase() == _lastCityQuery) return;

    setState(() => _loadingCities = true);
    // 150ms, matching the onboarding field. Long enough to skip most
    // intermediate keystrokes, short enough that the list feels live.
    _cityDebounce = Timer(
      const Duration(milliseconds: 150),
      () => _loadCitySuggestions(normalized),
    );
  }

  /// Label used to de-duplicate suggestions arriving from different sources.
  String _labelFor(Map<String, String> s) {
    final city = (s['city'] ?? '').trim();
    final country = (s['country'] ?? '').trim();
    return (country.isEmpty ? city : '$city, $country').toLowerCase();
  }

  /// Reuses the results of the longest cached prefix of [qLower], filtered to
  /// what still matches. Typing "raip" after "rai" can answer from memory
  /// instead of waiting on the network.
  List<Map<String, String>> _prefixCached(String qLower) {
    String? bestKey;
    for (final key in _citySuggestionCache.keys) {
      if (qLower.startsWith(key) &&
          (bestKey == null || key.length > bestKey.length)) {
        bestKey = key;
      }
    }
    if (bestKey == null) return const [];
    return (_citySuggestionCache[bestKey] ?? const [])
        .where((s) => _labelFor(s).contains(qLower))
        .take(6)
        .toList();
  }

  List<Map<String, String>> _quickLocalMatches(String qLower) {
    return _localCityFallback
        .where((c) => c.toLowerCase().contains(qLower))
        .take(6)
        .map((c) {
      final parts = c.split(',').map((p) => p.trim()).toList();
      return {
        'city': parts.first,
        'country': parts.length > 1 ? parts.sublist(1).join(', ') : '',
        'description': '',
      };
    }).toList();
  }

  Future<void> _loadCitySuggestions(String query) async {
    final qLower = query.toLowerCase();
    _lastCityQuery = qLower;

    // Paint something immediately — a cached prefix if we have one, otherwise
    // local matches — so the list never sits empty while the network works.
    final immediate = _prefixCached(qLower).isNotEmpty
        ? _prefixCached(qLower)
        : _quickLocalMatches(qLower);
    if (immediate.isNotEmpty && mounted) {
      setState(() => _citySuggestions = immediate);
    }

    // Google Places direct from the app first: it answers in ~0.5s, where the
    // backend adds a hop. The backend is the fallback, not the primary.
    var results = await _placesService
        .autocompleteCity(query)
        .timeout(const Duration(milliseconds: 900), onTimeout: () => const []);

    if (results.isEmpty) {
      results = await _adkService
          .getDestinationSuggestions(query: query, limit: 6)
          .timeout(const Duration(milliseconds: 1500),
              onTimeout: () => const []);
    }

    // Drop the response if the field has moved on since the request went out.
    if (!mounted || _cityController.text.trim().toLowerCase() != _lastCityQuery) {
      return;
    }

    if (results.isNotEmpty) {
      _citySuggestionCache[qLower] = results.take(6).toList();
    }
    setState(() {
      if (results.isNotEmpty) _citySuggestions = results.take(6).toList();
      _loadingCities = false;
    });
  }

  /// [region] is the suggestion's description — "Himachal Pradesh, India" —
  /// which is what distinguishes two cities sharing a name. Stored so the
  /// Aviasales handoff can pass it on; the field itself keeps the short name.
  void _selectCitySuggestion(String city, {String region = ''}) {
    _cityDebounce?.cancel();
    FocusScope.of(context).unfocus();

    // Some entries already carry the region in the name ("Bilaspur (Himachal
    // Pradesh)") — drop that so it isn't repeated once the region is appended.
    final shortName = city.split('(').first.trim();
    final qualified = region.trim().isEmpty
        ? null
        : (region.toLowerCase().startsWith(shortName.toLowerCase())
            ? region.trim()
            : '$shortName, ${region.trim()}');

    setState(() {
      _selectedCity = shortName;
      _selectedCityQualified = qualified;
      _cityController.text = shortName;
      _citySuggestions = [];
      _loadingCities = false;
      _lastCityQuery = shortName.toLowerCase();
    });
  }

  /// Hands off to Aviasales for the current city and dates, then asks whether
  /// the user booked — the redirect never reports back, so this is the only
  /// way a stay reaches the itinerary.
  Future<void> _openAviasalesHotels() async {
    if (_selectedCity == null) return;
    await BookingConfirmPrompt.launchAndConfirm(
      context,
      launch: () => AffiliateLinks.open(
        AffiliateLinks.aviasalesHotelSearchByCity(
          // Region-qualified when the user picked a suggestion, so a
          // same-named city can't send them to the wrong state.
          city: _selectedCityQualified ?? _selectedCity!,
          checkIn: _checkIn,
          checkOut: _checkOut,
          guests: _guests,
        ),
      ),
      kind: BookingKind.hotel,
      title: 'Stay in $_selectedCity',
      startDate: _checkIn,
      endDate: _checkOut,
      city: _selectedCity ?? '',
    );
  }

  /// Only ever called from an explicit user action — the screen no longer
  /// searches on open, so anything here is safe to treat as intentional,
  /// including handing off to Aviasales when the search fails.
  /// Validates the form, then hands straight off to Aviasales.
  ///
  /// There is no in-app hotel list any more. The old flow called the backend
  /// first, which answered from a 65-row CSV covering 15 cities with invented
  /// prices — so it was empty for most destinations and wrong for the rest,
  /// and every search paid for a round trip before redirecting anyway.
  /// Aviasales has the real inventory, so the search goes straight there.
  Future<void> _searchHotels() async {
    if (_selectedCity == null || _selectedCity!.trim().isEmpty) {
      setState(() => _showCityError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination city')),
      );
      return;
    }
    if (_showCityError) setState(() => _showCityError = false);

    if (!_checkOut.isAfter(_checkIn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check-out must be after check-in.'),
        ),
      );
      return;
    }

    await _openAviasalesHotels();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Hotels'),
        centerTitle: true,
        actions: [
          Consumer<HotelShortlistProvider>(
            builder: (context, shortlist, _) => IconButton(
              tooltip: 'Selected Hotel',
              icon: Badge(
                label: Text('${shortlist.hotels.length}'),
                isLabelVisible: shortlist.hotels.isNotEmpty,
                child: const Icon(Icons.favorite),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HotelShortlistScreen(),
                  ),
                );
              },
            ),
          ),
          if (_searchResults.isNotEmpty && _searched)
            IconButton(
              icon: const Icon(Icons.swipe),
              onPressed: () {
                Get.toNamed('/swipeable-hotels', arguments: {
                  'hotels': _searchResults,
                });
              },
              tooltip: 'Swipe Mode',
            ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Expanded(
            flex: _searched ? 2 : 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConfig.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // City search — free text with live suggestions, rather than
                  // a fixed dropdown, so any destination works and not just
                  // the handful that used to be hardcoded here.
                  FadeInDown(
                    child: _buildSectionTitle('Where?', required: true),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 50),
                    child: TextField(
                      controller: _cityController,
                      onChanged: _updateCitySuggestions,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search any city',
                        errorText: _showCityError
                            ? 'Please enter a destination to search'
                            : null,
                        prefixIcon: Icon(
                          Icons.location_city,
                          color: _showCityError ? _errorColor : null,
                        ),
                        suffixIcon: _loadingCities
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : (_cityController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _cityDebounce?.cancel();
                                      setState(() {
                                        _cityController.clear();
                                        _selectedCity = null;
                                        _citySuggestions = [];
                                      });
                                    },
                                  )),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConfig.radiusMedium),
                        ),
                      ),
                    ),
                  ),
                  if (_citySuggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppConfig.radiusMedium),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: _citySuggestions.map((s) {
                          final city = s['city'] ?? '';
                          final country = s['country'] ?? '';
                          final subtitle = (s['famous_for']?.isNotEmpty == true)
                              ? s['famous_for']!
                              : (s['description'] ?? '');
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on,
                                size: 18, color: AppConfig.primaryColor),
                            title: Text(
                              country.isEmpty ? city : '$city, $country',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                            onTap: () => _selectCitySuggestion(
                              city,
                              region: s['description'] ?? '',
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Dates
                  FadeInDown(
                    delay: const Duration(milliseconds: 100),
                    child: _buildSectionTitle('When?'),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 150),
                    child: Row(
                      children: [
                        Expanded(
                          child: _DatePicker(
                            label: 'Check-in',
                            date: _checkIn,
                            onTap: () => _selectDate(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePicker(
                            label: 'Check-out',
                            date: _checkOut,
                            onTap: () => _selectDate(false),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Display Hotel Preferences if provided
                  if (_roomType != null ||
                      _foodTypes.isNotEmpty ||
                      _ambiance != null ||
                      _extras.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    FadeInDown(
                      delay: const Duration(milliseconds: 600),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppConfig.radiusMedium),
                          border: Border.all(
                            color:
                                AppConfig.primaryColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle,
                                    color: AppConfig.primaryColor, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Your Hotel Preferences',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_roomType != null) ...[
                              _buildPreferenceRow('🛏️ Room Type', _roomType!),
                              const SizedBox(height: 8),
                            ],
                            if (_foodTypes.isNotEmpty) ...[
                              _buildPreferenceRow(
                                  '🍽️ Food', _foodTypes.join(', ')),
                              const SizedBox(height: 8),
                            ],
                            if (_ambiance != null) ...[
                              _buildPreferenceRow('✨ Ambiance', _ambiance!),
                              const SizedBox(height: 8),
                            ],
                            if (_extras.isNotEmpty) ...[
                              _buildPreferenceRow(
                                  '🎁 Extras', _extras.join(', ')),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Search Button
                  FadeInUp(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _searchHotels,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        // The label stays put while loading — replacing it
                        // with a bare spinner made the button look absent for
                        // as long as the search took (up to ~30s), which read
                        // as the screen not having finished rendering.
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_loading) ...[
                              const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text(_loading ? 'Searching…' : 'Search Hotels',
                                style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ),

          // Results Section
          if (_searched) ...[
            const Divider(height: 1),
            Expanded(
              flex: 3,
              child: _searchResults.isEmpty
                  ? const Center(child: Text('No hotels found'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppConfig.paddingMedium),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        return FadeInUp(
                          delay: Duration(milliseconds: 50 * index),
                          child: _HotelCard(
                            hotel: _searchResults[index],
                            checkIn: _checkIn,
                            checkOut: _checkOut,
                            guests: _guests,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// [required] adds a red asterisk so the field is visibly mandatory before
  /// the user tries to search, rather than only on rejection.
  Widget _buildSectionTitle(String title, {bool required = false}) {
    if (!required) {
      return Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );
    }
    return Text.rich(
      TextSpan(
        text: title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _errorColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppConfig.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppConfig.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate(bool isCheckIn) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 400,
        child: TableCalendar(
          firstDay: DateTime.now(),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: isCheckIn ? _checkIn : _checkOut,
          selectedDayPredicate: (day) =>
              isSameDay(day, isCheckIn ? _checkIn : _checkOut),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              if (isCheckIn) {
                _checkIn = selectedDay;
              } else {
                _checkOut = selectedDay;
              }
              // Whichever field was tapped, always keep the earlier of the
              // two picked dates as check-in and the later as check-out —
              // don't rely on which field the user happened to edit.
              if (_checkOut.isBefore(_checkIn)) {
                final earlier = _checkOut;
                final later = _checkIn;
                _checkIn = earlier;
                _checkOut = later;
              }
            });
            Navigator.pop(context);
          },
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppConfig.primaryColor.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppConfig.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePicker extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePicker({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style:
                  const TextStyle(fontSize: 12, color: AppConfig.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}/${date.month}/${date.year}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  final Hotel hotel;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;

  const _HotelCard({
    required this.hotel,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasAIData =
        hotel.aiMatchScore != null || hotel.whyRecommended != null;

    return Consumer<HotelShortlistProvider>(
      builder: (context, shortlist, _) {
        final isShortlisted = shortlist.isShortlisted(hotel);
        return Stack(
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: hasAIData ? 4 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                side: hasAIData
                    ? BorderSide(
                        color: Colors.deepPurple.withValues(alpha: 0.3),
                        width: 2)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: () => shortlist.toggle(hotel),
                child: Column(
                  children: [
                    // AI Match Score Badge (if available)
                    if (hotel.aiMatchScore != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurple.withValues(alpha: 0.1),
                              Colors.purple.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppConfig.radiusMedium),
                            topRight: Radius.circular(AppConfig.radiusMedium),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: Colors.deepPurple, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${hotel.aiMatchScore} Match',
                              style: const TextStyle(
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'AI Powered',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Image
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color:
                                  AppConfig.primaryColor.withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(AppConfig.radiusSmall),
                            ),
                            child: const Icon(Icons.hotel,
                                size: 40, color: AppConfig.primaryColor),
                          ),
                          const SizedBox(width: 12),
                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hotel.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(hotel.city,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      hotel.rating.toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '₹${hotel.pricePerNight.toInt()}/night',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppConfig.successColor,
                                      ),
                                    ),
                                  ],
                                ),

                                // AI Why Recommended (if available)
                                if (hotel.whyRecommended != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.purple.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.deepPurple
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Text(
                                      hotel.whyRecommended!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppConfig.textSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],

                                // AI Highlights (if available)
                                if (hotel.highlights != null &&
                                    hotel.highlights!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: hotel.highlights!
                                        .take(3)
                                        .map((highlight) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.deepPurple
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          highlight,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.deepPurple,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ] else if (hotel.amenities.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    children:
                                        hotel.amenities.take(3).map((amenity) {
                                      return Chip(
                                        label: Text(amenity,
                                            style:
                                                const TextStyle(fontSize: 10)),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      );
                                    }).toList(),
                                  ),
                                ],

                                // Perfect For (if available)
                                if (hotel.perfectFor != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.check_circle,
                                          size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          hotel.perfectFor!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          // The redirect never reports back, so ask once the
                          // user returns — see launchAndConfirm.
                          onPressed: () => BookingConfirmPrompt.launchAndConfirm(
                            context,
                            launch: () => AffiliateLinks.open(
                              AffiliateLinks.aviasalesHotelSearch(
                                hotel: hotel,
                                checkIn: checkIn,
                                checkOut: checkOut,
                                guests: guests,
                              ),
                            ),
                            kind: BookingKind.hotel,
                            title: hotel.name,
                            startDate: checkIn,
                            endDate: checkOut,
                            knownHotelName: hotel.name,
                            city: hotel.city,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Book on Aviasales'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppConfig.radiusSmall),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: Icon(
                    isShortlisted ? Icons.favorite : Icons.favorite_border,
                    color: isShortlisted ? Colors.redAccent : Colors.grey,
                  ),
                  onPressed: () => shortlist.toggle(hotel),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
