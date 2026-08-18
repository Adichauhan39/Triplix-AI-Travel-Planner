import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/user_preferences_provider.dart';
import '../services/python_adk_service.dart';
import '../services/google_places_service.dart';
import '../utils/currency_input_formatter.dart';
import '../widgets/user_progress_checkpoint.dart';

/// Single-page onboarding wizard that merges the preference screens
/// (destination, budget, additional context) into a stepper flow with shared
/// Back/Next navigation.
///
/// Transport preferences used to be a step here and were dropped: Triplix
/// only books flights, so asking someone whether they prefer trains or buses
/// promised a service the app cannot deliver, and the answer had nowhere to
/// go — nothing in the booking flow read it.

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // ---------------------------------------------------------------------------
  // Accordion expansion state
  // ---------------------------------------------------------------------------
  // Indices of currently-expanded sections. First one is open by default.
  final Set<int> _expanded = {};

  // Section 0 ("Where to next?") is opened programmatically by the Explore
  // button. ExpansionTile.initiallyExpanded is only read when the tile is
  // first created, so flipping _expanded afterwards does NOT open an
  // already-built tile — the controller is what actually opens it.
  final ExpansibleController _section0Controller = ExpansibleController();

  // Anchor for scrolling section 0 into view once Explore opens it.
  final GlobalKey _section0Key = GlobalKey();

  /// Whether Explore has been tapped with valid trip basics.
  ///
  /// "Where to next?" stays locked until then. Opening it earlier showed an
  /// empty destination step with nothing to choose from — its activities and
  /// suggestions are all loaded by Explore — so the section could be expanded
  /// into a dead end before the trip had a destination or dates.
  bool _exploreTapped = false;

  // ---------------------------------------------------------------------------
  // Step 1: Destination & activities
  // ---------------------------------------------------------------------------
  DateTime? _tripFromDate;
  DateTime? _tripToDate;
  int _numberOfPeople = 1;
  bool _hasLoadedTripBasics = false;

  // Top-of-onboarding origin / destination inputs (with autocomplete)
  final TextEditingController _originController = TextEditingController();
  final FocusNode _originFocusNode = FocusNode();
  List<Map<String, String>> _originSuggestions = [];
  bool _showOriginSuggestions = false;
  Timer? _originDebounce;
  String _lastOriginQuery = '';
  final LayerLink _originLayerLink = LayerLink();
  final GlobalKey _originFieldKey = GlobalKey();
  OverlayEntry? _originOverlayEntry;

  final TextEditingController _destTopController = TextEditingController();
  final FocusNode _destTopFocusNode = FocusNode();
  List<Map<String, String>> _destTopSuggestions = [];
  bool _showDestTopSuggestions = false;
  Timer? _destTopDebounce;
  String _lastDestTopQuery = '';
  final LayerLink _destTopLayerLink = LayerLink();
  final GlobalKey _destTopFieldKey = GlobalKey();
  OverlayEntry? _destTopOverlayEntry;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PythonADKService _adkService = PythonADKService();
  final GooglePlacesService _placesService = GooglePlacesService();
  final Map<String, List<Map<String, String>>> _citySuggestionCache = {};

  List<Map<String, dynamic>> _aiCategories = [];
  // Activity keyword -> real photo URL, fetched separately/lazily after
  // _aiCategories loads (see _loadActivityImages). Chips render as text
  // immediately and swap in an image once its fetch completes.
  Map<String, String> _activityImages = {};
  List<Map<String, String>> _filteredSuggestions = [];
  final Set<String> _selectedActivities = {};
  Timer? _suggestionDebounce;
  bool _isLoadingDest = false;
  bool _showSuggestions = false;
  String _loadedCity = '';
  String _lastRequestedQuery = '';

  static const List<Color> _categoryColors = [
    Color(0xFFFF5722),
    Color(0xFF9C27B0),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF607D8B),
    Color(0xFF795548),
  ];

  // ---------------------------------------------------------------------------
  // Step 2: Budget
  // ---------------------------------------------------------------------------
  final TextEditingController _budgetController = TextEditingController();
  late String _selectedCurrencyCode;
  static const List<String> _supportedCurrencyCodes = [
    'USD',
    'EUR',
    'GBP',
    'INR',
    'JPY',
    'CNY',
    'AUD',
    'CAD',
    'SGD',
    'AED',
  ];

  double? get _enteredBudget {
    final val = double.tryParse(_budgetController.text.replaceAll(',', ''));
    return (val != null && val > 0) ? val : null;
  }

  /// Re-applies thousand-separator grouping after the currency dropdown
  /// changes, so USD (100,000) reformats to INR style (1,00,000) live.
  void _reformatBudgetForCurrency() {
    final current = _enteredBudget;
    if (current == null) return;
    final formatted =
        groupedNumberFormat(_selectedCurrencyCode).format(current.round());
    _budgetController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  // Maps the device locale to a currency code: checks a hardcoded
  // country->currency table first, then falls back to intl's own
  // locale-to-currency resolution, then USD if both fail.
  String _defaultCurrencyForLocale(Locale locale) {
    const countryToCurrency = {
      'US': 'USD',
      'CA': 'CAD',
      'GB': 'GBP',
      'IE': 'EUR',
      'FR': 'EUR',
      'DE': 'EUR',
      'ES': 'EUR',
      'IT': 'EUR',
      'NL': 'EUR',
      'PT': 'EUR',
      'IN': 'INR',
      'JP': 'JPY',
      'CN': 'CNY',
      'AU': 'AUD',
      'NZ': 'NZD',
      'SG': 'SGD',
      'AE': 'AED',
    };

    final countryCode = locale.countryCode?.toUpperCase();
    if (countryCode != null && countryToCurrency.containsKey(countryCode)) {
      return countryToCurrency[countryCode]!;
    }

    try {
      final format =
          NumberFormat.simpleCurrency(locale: locale.toLanguageTag());
      final code = format.currencyName;
      if (code != null && code.isNotEmpty) {
        return code.toUpperCase();
      }
    } catch (_) {
      // Fall through to USD.
    }

    return 'USD';
  }

  // Resolves a currency code (e.g. "INR") to its display symbol (e.g. "₹"),
  // falling back to the raw code if intl doesn't recognize it.
  String _currencySymbol(String code) {
    try {
      final format = NumberFormat.simpleCurrency(name: code);
      if (format.currencySymbol.isNotEmpty) {
        return format.currencySymbol;
      }
    } catch (_) {
      // Fall through to currency code.
    }
    return code;
  }

  // Formats an amount with the selected currency's symbol and locale-correct
  // thousand grouping (e.g. INR groups as 1,00,000 rather than 100,000).
  String _formatBudgetAmount(double amount, {bool includeCode = false}) {
    final symbol = _currencySymbol(_selectedCurrencyCode);
    final codeSuffix = includeCode ? ' $_selectedCurrencyCode' : '';
    final grouped =
        groupedNumberFormat(_selectedCurrencyCode).format(amount.round());
    return '$symbol$grouped$codeSuffix';
  }

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

  // Combines two suggestion lists (e.g. Places API + ADK service results),
  // de-duplicating by formatted label so the same city from different
  // sources doesn't appear twice, and caps the result at 8 entries.
  List<Map<String, String>> _mergeUniqueSuggestions(
    List<Map<String, String>> first,
    List<Map<String, String>> second,
  ) {
    final merged = <Map<String, String>>[];
    final seen = <String>{};

    void addAllUnique(List<Map<String, String>> source) {
      for (final s in source) {
        final label = _formatLocationLabel(
          city: s['city'] ?? '',
          country: s['country'] ?? '',
          description: s['description'] ?? '',
        );
        final key = label.toLowerCase();
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        merged.add(s);
      }
    }

    addAllUnique(first);
    addAllUnique(second);
    return merged.take(8).toList();
  }

  // Looks for the longest previously-cached query that is a prefix of the
  // current one (e.g. cached "lon" can serve "lond"), so typing further
  // characters gets an instant filtered result while the network call for
  // the exact query is still in flight.
  List<Map<String, String>> _getPrefixCachedSuggestions(String qLower) {
    String? bestKey;
    for (final key in _citySuggestionCache.keys) {
      if (qLower.startsWith(key)) {
        if (bestKey == null || key.length > bestKey.length) {
          bestKey = key;
        }
      }
    }
    if (bestKey == null) return const [];

    final source = _citySuggestionCache[bestKey] ?? const [];
    final filtered = source.where((s) {
      final label = _formatLocationLabel(
        city: s['city'] ?? '',
        country: s['country'] ?? '',
        description: s['description'] ?? '',
      ).toLowerCase();
      return label.contains(qLower);
    }).toList();

    return filtered.take(8).toList();
  }

  // Synchronous match against the small hardcoded city list, used as an
  // instant preview while the network autocomplete round-trip is in flight.
  List<Map<String, String>> _quickLocalMatches(String qLower) {
    return _localCityFallback
        .where((city) => city.toLowerCase().contains(qLower))
        .take(8)
        .map((city) {
      final parts = city.split(',').map((p) => p.trim()).toList();
      final cityName = parts.isNotEmpty ? parts.first : city;
      final country = parts.length > 1 ? parts.sublist(1).join(', ') : '';
      return {
        'city': cityName,
        'country': country,
        'description': city,
      };
    }).toList();
  }

  // Cascading city-lookup strategy, cheapest/fastest source first:
  // 1) exact-query cache, 2) Google Places autocomplete (700ms timeout),
  // 3) ADK destination service (700ms timeout) merged with any Places
  // results, 4) hardcoded local city list as a last resort. Each step's
  // result is cached so repeat keystrokes skip straight to step 1.
  Future<List<Map<String, String>>> _getFastCitySuggestions(
      String query) async {
    final q = query.trim();
    final qLower = q.toLowerCase();
    if (q.length < 2) return const [];

    final cached = _citySuggestionCache[qLower];
    if (cached != null && cached.isNotEmpty) return cached;

    final places = await _placesService
        .autocompleteCity(q)
        .timeout(const Duration(milliseconds: 700), onTimeout: () => const []);

    if (places.isNotEmpty) {
      _citySuggestionCache[qLower] = places.take(8).toList();
      return _citySuggestionCache[qLower]!;
    }

    final adk = await _adkService
        .getDestinationSuggestions(query: q, limit: 8)
        .timeout(const Duration(milliseconds: 700), onTimeout: () => const []);

    final merged = _mergeUniqueSuggestions(places, adk);
    if (merged.isNotEmpty) {
      _citySuggestionCache[qLower] = merged;
      return merged;
    }

    final local = _quickLocalMatches(qLower);

    _citySuggestionCache[qLower] = local;
    return local;
  }

  // ---------------------------------------------------------------------------
  // Step 4: Additional context
  // ---------------------------------------------------------------------------
  String _selectedCompanion = '';
  String _selectedOccasion = '';
  String _selectedExperience = '';
  final TextEditingController _aiContextController = TextEditingController();

  final Set<String> _selectedAccessibility = {};
  final Set<String> _selectedDietary = {};
  final Set<String> _selectedMedical = {};
  final Set<String> _selectedLanguage = {};

  final List<String> _companions = [
    'Solo',
    'Couple',
    'Family with children',
    'Friend groups'
  ];
  final List<String> _occasions = [
    'Honeymoon',
    'Anniversary',
    'Birthday',
    'Business',
    'Adventure',
    'Relaxation'
  ];
  final List<String> _experiences = [
    'First-time travelers',
    'Experienced explorers',
    'Frequent travelers'
  ];
  final List<String> _accessibilityOptions = [
    'Wheelchair access',
    'Mobility assistance',
    'Visual assistance',
    'Hearing assistance'
  ];
  final List<String> _dietaryOptions = [
    'VEG',
    'NON-VEG',
    'CONTINENTAL',
    'SOUTH INDIAN',
    'NORTH INDIAN',
    'VEGAN',
  ];
  final List<String> _medicalOptions = [
    'Allergies',
    'Chronic conditions',
    'Medications',
    'Emergency contact'
  ];
  final List<String> _languageOptions = [
    'English',
    'Hindi',
    'Local language support',
    'Translation services'
  ];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _selectedCurrencyCode = 'INR';
    // The FROM/TO fields gate the bottom "Complete" button via
    // _tripBasicsComplete, but the onChanged handlers only setState for
    // queries under 2 characters (they debounce instead). Without these
    // listeners the button would stay disabled while the user types a valid
    // city, until some unrelated rebuild happened to run.
    _originController.addListener(_onTripBasicsChanged);
    _destTopController.addListener(_onTripBasicsChanged);
  }

  bool _lastTripBasicsComplete = false;

  /// Red used for required-field markers and validation highlights. Darker
  /// than Colors.red so it keeps contrast against the white field background.
  static const Color _errorColor = Color(0xFFD32F2F);

  /// Whether to highlight blank required fields in red. Stays false until the
  /// user actually tries to proceed — colouring every field red the instant
  /// the screen opens (when nothing is filled yet) reads as failure rather
  /// than guidance.
  bool _showTripBasicsErrors = false;

  /// Rebuilds when the required-fields gate flips. While errors are on screen
  /// it rebuilds per keystroke instead, so a field's red clears as soon as the
  /// user types into it rather than lingering.
  void _onTripBasicsChanged() {
    final complete = _tripBasicsComplete;
    if (complete == _lastTripBasicsComplete && !_showTripBasicsErrors) return;
    _lastTripBasicsComplete = complete;
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasLoadedTripBasics) return;

    final prefs = Provider.of<UserPreferencesProvider>(context, listen: false)
        .preferences;
    _tripFromDate = prefs.checkInDate;
    _tripToDate = prefs.checkOutDate;
    _numberOfPeople =
        (prefs.numberOfPeople != null && prefs.numberOfPeople! > 0)
            ? prefs.numberOfPeople!
            : 1;
    _originController.text = prefs.origin ?? '';
    _destTopController.text = prefs.destination ?? '';

    _hasLoadedTripBasics = true;
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _originDebounce?.cancel();
    _destTopDebounce?.cancel();
    _originOverlayEntry?.remove();
    _destTopOverlayEntry?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _originController.removeListener(_onTripBasicsChanged);
    _originController.dispose();
    _originFocusNode.dispose();
    _destTopController.removeListener(_onTripBasicsChanged);
    _destTopController.dispose();
    _destTopFocusNode.dispose();
    _budgetController.dispose();
    _aiContextController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Completion helpers (for the "Saved" badge on each section header)
  // ---------------------------------------------------------------------------
  bool get _hasContextSelections =>
      _selectedCompanion.isNotEmpty ||
      _selectedOccasion.isNotEmpty ||
      _selectedExperience.isNotEmpty ||
      _selectedAccessibility.isNotEmpty ||
      _selectedDietary.isNotEmpty ||
      _selectedMedical.isNotEmpty ||
      _selectedLanguage.isNotEmpty ||
      _aiContextController.text.trim().isNotEmpty;

  // Per-section completion (used both for the "Saved" badge and to
  // unlock the next section in the sequential flow).
  bool _isSectionComplete(int index) {
    switch (index) {
      case 0:
        return _loadedCity.isNotEmpty;
      case 1:
        return _enteredBudget != null;
      case 3:
        return _hasContextSelections;
      default:
        return false;
    }
  }

  // A section is unlocked iff every previous section is complete.
  bool _isSectionUnlocked(int index) {
    if (index == 0) return _exploreTapped;
    return _isSectionComplete(index - 1);
  }

  // Trip basics (FROM / TO / dates) at the top of onboarding. Required —
  // every downstream step depends on them: flight links need both cities to
  // resolve an IATA pair, and hotel/activity results are priced and filtered
  // by the travel dates.
  bool get _tripBasicsComplete =>
      _originController.text.trim().isNotEmpty &&
      _destTopController.text.trim().isNotEmpty &&
      _tripFromDate != null &&
      _tripToDate != null;

  /// Which required trip basics are still blank, in the order they appear on
  /// screen. Empty when [_tripBasicsComplete].
  List<String> get _missingTripBasics => [
        if (_originController.text.trim().isEmpty) 'where you\'re travelling from',
        if (_destTopController.text.trim().isEmpty) 'your destination',
        if (_tripFromDate == null || _tripToDate == null) 'your trip dates',
      ];

  /// Joins items into a readable phrase: "a", "a and b", "a, b and c".
  static String _readableList(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  bool get _allComplete =>
      _tripBasicsComplete &&
      _isSectionComplete(0) &&
      _isSectionComplete(1);

  // Persists every field collected across all four steps into
  // UserPreferencesProvider in one shot, then navigates to /home.
  void _completeOnboarding() {
    final provider =
        Provider.of<UserPreferencesProvider>(context, listen: false);

    // Trip basics (top of onboarding)
    final originText = _originController.text.trim();
    if (originText.isNotEmpty) {
      provider.updateOrigin(originText);
    }
    final destTopText = _destTopController.text.trim();
    if (destTopText.isNotEmpty) {
      provider.updateDestination(destTopText);
    }
    if (_tripFromDate != null && _tripToDate != null) {
      provider.updateDates(_tripFromDate!, _tripToDate!);
    }
    provider.updateNumberOfPeople(_numberOfPeople);

    // Step 1
    if (_loadedCity.isNotEmpty) {
      provider.updateDestination(_loadedCity);
    }
    provider.updateActivities(_selectedActivities.toList());

    // Step 2
    if (_enteredBudget != null) {
      provider.updateBudget(_enteredBudget!,
          currencyCode: _selectedCurrencyCode);
    }

    // Step 4
    provider.updateAdditionalContext(
      companion: _selectedCompanion.isNotEmpty ? _selectedCompanion : null,
      occasion: _selectedOccasion.isNotEmpty ? _selectedOccasion : null,
      experience: _selectedExperience.isNotEmpty ? _selectedExperience : null,
      accessibility: _selectedAccessibility.toList(),
      dietary: _selectedDietary.toList(),
      medical: _selectedMedical.toList(),
      languages: _selectedLanguage.toList(),
    );

    Get.offAllNamed('/home');
  }

  // ---------------------------------------------------------------------------
  // Step 1 logic – destination autocomplete & interests
  // ---------------------------------------------------------------------------
  // Debounced entry point for the Step-1 city search bar: skips the network
  // round-trip for very short or repeated queries, otherwise waits 450ms of
  // idle typing before calling _loadSuggestions.
  void _updateSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      _suggestionDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _filteredSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    if (normalized == _lastRequestedQuery) return;

    _suggestionDebounce?.cancel();
    _suggestionDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _loadSuggestions(query),
    );
  }

  Future<void> _loadSuggestions(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _filteredSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    _lastRequestedQuery = q;

    final suggestions = await _adkService.getDestinationSuggestions(
      query: query,
      limit: 8,
    );

    if (!mounted || _searchController.text.trim().toLowerCase() != q) return;

    setState(() {
      _filteredSuggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  // User tapped a Step-1 search suggestion: fills the field, closes the
  // dropdown, and immediately kicks off interest-category loading for it.
  Future<void> _selectSuggestion(Map<String, String> suggestion) async {
    final city = suggestion['city'] ?? '';
    final country = suggestion['country'] ?? '';
    final description = suggestion['description'] ?? '';
    final formatted = _formatLocationLabel(
      city: city,
      country: country,
      description: description,
    );

    setState(() {
      _searchController.text = formatted;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      _showSuggestions = false;
      _filteredSuggestions = [];
      _lastRequestedQuery = '';
    });

    FocusScope.of(context).unfocus();
    await _fetchCityInterests();
  }

  // Resolves the typed city into a concrete place and loads its AI-suggested
  // interest categories. Flow: if the query has no explicit region ("Paris"
  // vs "Paris, TX"), first check for same-name matches across regions and
  // ask the user to confirm via dialog if there are several; then run a
  // second ADK disambiguation pass (catches cases the region-matching
  // step misses) and ask again if that also comes back ambiguous. Falls
  // back to a hardcoded category list if the ADK interest call fails.
  Future<void> _fetchCityInterests() async {
    final city = _searchController.text.trim();
    if (city.isEmpty) return;
    if (city.toLowerCase() == _loadedCity.toLowerCase()) return;

    setState(() {
      _showSuggestions = false;
      _filteredSuggestions = [];
      _isLoadingDest = true;
      _aiCategories = [];
      _activityImages = {};
      _selectedActivities.clear();
    });

    try {
      String resolvedCity = city;
      final bool hasExplicitRegion = city.contains(',');

      if (!hasExplicitRegion) {
        final cityMatches = await _adkService.getDestinationSuggestions(
          query: city,
          limit: 5,
        );
        if (!mounted) return;

        if (cityMatches.length > 2) {
          final picked = await _showCityConfirmationDialog(city, cityMatches);
          if (!mounted) return;
          if (picked == null) {
            setState(() => _isLoadingDest = false);
            return;
          }
          resolvedCity = picked;
          _searchController.text = resolvedCity;
        } else if (cityMatches.isNotEmpty) {
          final top = cityMatches.first;
          resolvedCity = _formatLocationLabel(
            city: top['city'] ?? '',
            country: top['country'] ?? '',
            description: top['description'] ?? '',
          );
          _searchController.text = resolvedCity;
        }

        final disambResult = await _adkService.disambiguateCity(city: city);
        if (!mounted) return;

        if (disambResult['success'] == true &&
            disambResult['ambiguous'] == true) {
          final options =
              List<Map<String, dynamic>>.from(disambResult['options'] ?? []);
          if (options.length > 1) {
            final picked = await _showDisambiguationDialog(city, options);
            if (!mounted) return;
            if (picked != null) {
              resolvedCity = picked;
              _searchController.text = resolvedCity;
            }
          }
        }
      }

      final result =
          await _adkService.getDestinationInterests(city: resolvedCity);
      if (result['success'] == true && mounted) {
        final categories =
            List<Map<String, dynamic>>.from(result['categories'] ?? []);
        setState(() {
          _aiCategories = categories.isNotEmpty
              ? categories
              : _fallbackInterestCategories(resolvedCity);
          _loadedCity = resolvedCity;
          _isLoadingDest = false;
        });
        _loadActivityImages(resolvedCity);
      } else {
        if (mounted) {
          setState(() {
            _aiCategories = _fallbackInterestCategories(resolvedCity);
            _loadedCity = resolvedCity;
            _isLoadingDest = false;
          });
          _loadActivityImages(resolvedCity);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiCategories = _fallbackInterestCategories(city);
          _loadedCity = city;
          _isLoadingDest = false;
        });
        _loadActivityImages(city);
      }
    }
  }

  /// Fetches a real photo for every activity keyword across all currently
  /// loaded categories, in one batched backend call. Fire-and-forget: chips
  /// already render as text immediately, images fade in as they arrive.
  Future<void> _loadActivityImages(String city) async {
    final activities = _aiCategories
        .expand((category) => List<String>.from(category['activities'] ?? []))
        .toSet()
        .toList();
    if (activities.isEmpty) return;

    // Kept as one request: splitting this into parallel batches was measured
    // and made no difference (every batch still landed together at ~7s). The
    // cost is upstream — two Google round trips per activity — so the wait is
    // the same however it's sliced. Chips render as text immediately and
    // images fade in when this returns.
    try {
      final images = await _adkService.getActivityImages(
          city: city, activities: activities);
      if (!mounted || images.isEmpty) return;
      setState(() => _activityImages = {..._activityImages, ...images});
    } catch (_) {
      // Images are decorative — a failure here leaves the text chips intact.
    }
  }

  // Generic interest categories shown when the ADK service can't return
  // city-specific ones (offline, error, or empty response).
  List<Map<String, dynamic>> _fallbackInterestCategories(String city) {
    final cleanedCity = city.split(',').first.trim();
    return [
      {
        'id': 'city_landmarks',
        'title': 'City Landmarks',
        'icon': 'camera_alt',
        'activities': ['Landmarks', 'Museums', 'Heritage Walks', 'Viewpoints'],
      },
      {
        'id': 'food_dining',
        'title': 'Food & Dining',
        'icon': 'restaurant',
        'activities': ['Street Food', 'Local Cuisine', 'Cafes', 'Fine Dining'],
      },
      {
        'id': 'culture_spiritual',
        'title': 'Culture & Spiritual',
        'icon': 'temple_hindu',
        'activities': [
          'Temples',
          'Cultural Sites',
          'Architecture',
          'Art Spaces'
        ],
      },
      {
        'id': 'nature_parks',
        'title': 'Nature & Parks',
        'icon': 'park',
        'activities': ['City Parks', 'Gardens', 'Nature Walks', 'Lakeside'],
      },
      {
        'id': 'shopping_nightlife',
        'title': 'Shopping & Nightlife',
        'icon': 'shopping_bag',
        'activities': ['Markets', 'Malls', 'Nightlife', 'Live Music'],
      },
      {
        'id': 'recommended_mix',
        'title': 'Recommended in $cleanedCity',
        'icon': 'local_activity',
        'activities': [
          'Top Attractions',
          'Popular Experiences',
          'Family Spots',
          'Photo Stops'
        ],
      },
    ];
  }

  // Builds the human-readable "City, Region/Country" label shown in
  // suggestion lists, preferring the API-provided description when it
  // already contains the city name to avoid duplicating it (e.g. avoids
  // "Paris, Paris, France").
  String _formatLocationLabel({
    required String city,
    required String country,
    required String description,
  }) {
    final trimmedCity = city.trim();
    final trimmedCountry = country.trim();
    final trimmedDescription = description.trim();

    if (trimmedDescription.isNotEmpty) {
      final descLower = trimmedDescription.toLowerCase();
      final cityLower = trimmedCity.toLowerCase();

      if (descLower.contains(cityLower)) {
        return trimmedDescription;
      }

      if (trimmedCountry.isNotEmpty) {
        return '$trimmedCity, $trimmedDescription';
      }

      return '$trimmedCity, $trimmedDescription';
    }
    if (trimmedCountry.isNotEmpty) {
      return '$trimmedCity, $trimmedCountry';
    }
    return trimmedCity;
  }

  // Pulls the state/region segment out of a "City, State, Country"
  // description for the small badge shown in the confirmation dialog.
  String _extractStateOrRegion(String description) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return '';

    final parts = trimmed
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return parts.first;
    }
    return trimmed;
  }

  // First-pass disambiguation: shown when the typed city name matches
  // several same-named places (from the region-matching lookup in
  // _fetchCityInterests). Returns the picked location label, or null if
  // cancelled.
  Future<String?> _showCityConfirmationDialog(
    String query,
    List<Map<String, String>> options,
  ) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_city, color: AppConfig.primaryColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm your city',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$query" matches multiple places. Select the exact city:',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (ctx, index) {
                    final option = options[index];
                    final name = option['city'] ?? query;
                    final stateOrRegion =
                        _extractStateOrRegion(option['description'] ?? '');
                    final country = option['country'] ?? '';
                    final locationLabel = _formatLocationLabel(
                      city: name,
                      country: country,
                      description: option['description'] ?? '',
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(ctx).pop(locationLabel),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppConfig.primaryColor
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.place,
                                    color: AppConfig.primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        locationLabel,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      if (stateOrRegion.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blueGrey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            stateOrRegion,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueGrey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Second-pass disambiguation: shown when the ADK service's own
  // disambiguateCity call reports ambiguity that the first pass didn't
  // catch. Returns the picked place name, or null if cancelled.
  Future<String?> _showDisambiguationDialog(
      String query, List<Map<String, dynamic>> options) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppConfig.primaryColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Did you mean?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$query" matches multiple places:',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final name = option['name'] ?? query;
              final desc = option['description'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(name),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                AppConfig.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: AppConfig.primaryColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  desc,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'terrain':
        return Icons.terrain;
      case 'museum':
        return Icons.museum;
      case 'spa':
        return Icons.spa;
      case 'movie':
        return Icons.movie;
      case 'forest':
        return Icons.forest;
      case 'camera_alt':
        return Icons.camera_alt;
      case 'restaurant':
        return Icons.restaurant;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'temple_hindu':
        return Icons.temple_hindu;
      case 'nightlife':
        return Icons.nightlife;
      case 'sports':
        return Icons.sports;
      case 'park':
        return Icons.park;
      case 'coffee':
        return Icons.coffee;
      case 'architecture':
        return Icons.architecture;
      default:
        return Icons.local_activity;
    }
  }

  // ---------------------------------------------------------------------------
  // Step 2 logic – budget allocation
  // ---------------------------------------------------------------------------
  DateTime get _tripFirstAllowedDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _tripLastAllowedDate => DateTime(DateTime.now().year + 3);

  // Opens the range picker, clamping any previously-saved dates back into
  // the allowed [today, +3 years] window in case they've since gone stale
  // (e.g. a saved start date that's now in the past).
  Future<void> _pickTripDates() async {
    final firstDate = _tripFirstAllowedDate;
    final lastDate = _tripLastAllowedDate;
    DateTime initialStart = _tripFromDate ?? firstDate;
    if (initialStart.isBefore(firstDate)) initialStart = firstDate;
    if (initialStart.isAfter(lastDate)) initialStart = lastDate;
    DateTime initialEnd =
        _tripToDate ?? initialStart.add(const Duration(days: 3));
    if (initialEnd.isBefore(initialStart)) initialEnd = initialStart;
    if (initialEnd.isAfter(lastDate)) initialEnd = lastDate;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'Select travel dates',
      saveText: 'Done',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color.fromARGB(255, 13, 13, 130),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _tripFromDate = picked.start;
      _tripToDate = picked.end;
    });

    Provider.of<UserPreferencesProvider>(context, listen: false)
        .updateDates(picked.start, picked.end);
  }

  // -----------------------------------------------------------------
  // Origin (FROM) autocomplete
  // -----------------------------------------------------------------
  // Shorter 120ms debounce than the Step-1 search bar since this field
  // shows instant cached/local matches immediately (see
  // _loadOriginSuggestions) while the network call is still pending.
  void _updateOriginSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      _originDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _originSuggestions = [];
        _showOriginSuggestions = false;
      });
      _syncOriginOverlay();
      return;
    }
    if (normalized == _lastOriginQuery &&
        _showOriginSuggestions &&
        _originSuggestions.isNotEmpty) {
      return;
    }

    _originDebounce?.cancel();
    _originDebounce = Timer(
        const Duration(milliseconds: 120), () => _loadOriginSuggestions(query));
  }

  Future<void> _loadOriginSuggestions(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _originSuggestions = [];
        _showOriginSuggestions = false;
      });
      _syncOriginOverlay();
      return;
    }

    _lastOriginQuery = q;

    // Show a best-effort instant result (cache/local) first, then replace
    // it once the slower network-backed lookup resolves.
    final instant = _getPrefixCachedSuggestions(q);
    final immediate = instant.isNotEmpty ? instant : _quickLocalMatches(q);
    if (immediate.isNotEmpty) {
      setState(() {
        _originSuggestions = immediate;
        _showOriginSuggestions = true;
      });
      _syncOriginOverlay();
    }

    final suggestions = await _getFastCitySuggestions(query);

    if (!mounted || _originController.text.trim().toLowerCase() != q) return;

    setState(() {
      _originSuggestions = suggestions;
      _showOriginSuggestions = suggestions.isNotEmpty;
    });
    _syncOriginOverlay();
  }

  // Positions/refreshes the floating suggestion list for the FROM field in
  // the root Overlay so it always paints above sibling cards below it —
  // a Positioned overlay scoped to the card's own Stack got painted over by
  // the next accordion section as soon as it overflowed the card's bounds.
  void _syncOriginOverlay() {
    final shouldShow = _showOriginSuggestions && _originSuggestions.isNotEmpty;
    if (!shouldShow) {
      _originOverlayEntry?.remove();
      _originOverlayEntry = null;
      return;
    }

    if (_originOverlayEntry != null) {
      _originOverlayEntry!.markNeedsBuild();
      return;
    }

    final renderBox =
        _originFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final fieldSize = renderBox.size;

    _originOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: fieldSize.width,
        child: CompositedTransformFollower(
          link: _originLayerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldSize.height + 4),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: _buildTopSuggestionList(
              _originSuggestions,
              _selectOriginSuggestion,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_originOverlayEntry!);
  }

  void _selectOriginSuggestion(Map<String, String> suggestion) {
    final city = suggestion['city'] ?? '';
    final country = suggestion['country'] ?? '';
    final description = suggestion['description'] ?? '';
    final formatted = _formatLocationLabel(
      city: city,
      country: country,
      description: description,
    );

    setState(() {
      _originController.text = formatted;
      _originController.selection = TextSelection.fromPosition(
        TextPosition(offset: formatted.length),
      );
      _showOriginSuggestions = false;
      _originSuggestions = [];
      _lastOriginQuery = '';
    });
    _syncOriginOverlay();

    Provider.of<UserPreferencesProvider>(context, listen: false)
        .updateOrigin(formatted);
    FocusScope.of(context).unfocus();
  }

  // -----------------------------------------------------------------
  // Destination (TO) autocomplete – top card
  // Selecting here also drives Section 0 interests loading.
  // -----------------------------------------------------------------
  void _updateDestTopSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      _destTopDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _destTopSuggestions = [];
        _showDestTopSuggestions = false;
      });
      _syncDestTopOverlay();
      return;
    }
    if (normalized == _lastDestTopQuery &&
        _showDestTopSuggestions &&
        _destTopSuggestions.isNotEmpty) {
      return;
    }

    _destTopDebounce?.cancel();
    _destTopDebounce = Timer(const Duration(milliseconds: 120),
        () => _loadDestTopSuggestions(query));
  }

  Future<void> _loadDestTopSuggestions(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _destTopSuggestions = [];
        _showDestTopSuggestions = false;
      });
      _syncDestTopOverlay();
      return;
    }

    _lastDestTopQuery = q;

    final instant = _getPrefixCachedSuggestions(q);
    final immediate = instant.isNotEmpty ? instant : _quickLocalMatches(q);
    if (immediate.isNotEmpty) {
      setState(() {
        _destTopSuggestions = immediate;
        _showDestTopSuggestions = true;
      });
      _syncDestTopOverlay();
    }

    final suggestions = await _getFastCitySuggestions(query);

    if (!mounted || _destTopController.text.trim().toLowerCase() != q) return;

    setState(() {
      _destTopSuggestions = suggestions;
      _showDestTopSuggestions = suggestions.isNotEmpty;
    });
    _syncDestTopOverlay();
  }

  // Mirrors _syncOriginOverlay for the TO field.
  void _syncDestTopOverlay() {
    final shouldShow =
        _showDestTopSuggestions && _destTopSuggestions.isNotEmpty;
    if (!shouldShow) {
      _destTopOverlayEntry?.remove();
      _destTopOverlayEntry = null;
      return;
    }

    if (_destTopOverlayEntry != null) {
      _destTopOverlayEntry!.markNeedsBuild();
      return;
    }

    final renderBox =
        _destTopFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final fieldSize = renderBox.size;

    _destTopOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: fieldSize.width,
        child: CompositedTransformFollower(
          link: _destTopLayerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldSize.height + 4),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: _buildTopSuggestionList(
              _destTopSuggestions,
              _selectDestTopSuggestion,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_destTopOverlayEntry!);
  }

  Future<void> _selectDestTopSuggestion(Map<String, String> suggestion) async {
    final city = suggestion['city'] ?? '';
    final country = suggestion['country'] ?? '';
    final description = suggestion['description'] ?? '';
    final formatted = _formatLocationLabel(
      city: city,
      country: country,
      description: description,
    );

    setState(() {
      _destTopController.text = formatted;
      _destTopController.selection = TextSelection.fromPosition(
        TextPosition(offset: formatted.length),
      );
      _showDestTopSuggestions = false;
      _destTopSuggestions = [];
      _lastDestTopQuery = '';
    });
    _syncDestTopOverlay();

    Provider.of<UserPreferencesProvider>(context, listen: false)
        .updateDestination(formatted);
    FocusScope.of(context).unfocus();
  }

  String _formatTripDate(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('dd MMM yyyy').format(date);
  }

  // A compact labeled text field wrapped in CompositedTransformTarget so its
  // paired overlay (see _syncOriginOverlay / _syncDestTopOverlay) can anchor
  // its suggestion dropdown to this field's exact position and width.
  Widget _buildLocationField({
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required LayerLink layerLink,
    required GlobalKey fieldKey,
    VoidCallback? onEditingComplete,
    bool hasError = false,
  }) {
    return CompositedTransformTarget(
      link: layerLink,
      child: Container(
        key: fieldKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasError ? _errorColor : Colors.black12,
            width: hasError ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: hasError ? _errorColor.withValues(alpha: 0.04) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: hasError ? _errorColor : iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Required fields carry a red asterisk at all times, so the
                  // user can see what's mandatory before they try to proceed.
                  Text.rich(
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        fontSize: 10,
                        color: hasError ? _errorColor : Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                      children: const [
                        TextSpan(
                          text: ' *',
                          style: TextStyle(
                            fontSize: 10,
                            color: _errorColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      onEditingComplete: onEditingComplete,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.black38,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The dropdown list rendered inside the FROM/TO overlay entries.
  Widget _buildTopSuggestionList(
    List<Map<String, String>> suggestions,
    void Function(Map<String, String>) onSelect,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: suggestions.asMap().entries.map((entry) {
          final index = entry.key;
          final s = entry.value;
          final label = _formatLocationLabel(
            city: s['city'] ?? '',
            country: s['country'] ?? '',
            description: s['description'] ?? '',
          );
          return InkWell(
            onTap: () => onSelect(s),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: index == suggestions.length - 1
                    ? null
                    : Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: AppConfig.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Always-visible card above the accordion: origin/destination, trip
  // dates, traveler count, and the "Explore" button that seeds Section 0
  // (destination & activities) from these values.
  Widget _buildTripBasicsCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Trip basics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),

              // FROM (origin) & TO (destination)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildLocationField(
                      label: 'FROM',
                      hint: 'Origin city',
                      icon: Icons.flight_takeoff,
                      iconColor: Colors.green,
                      controller: _originController,
                      focusNode: _originFocusNode,
                      layerLink: _originLayerLink,
                      fieldKey: _originFieldKey,
                      hasError: _showTripBasicsErrors &&
                          _originController.text.trim().isEmpty,
                      onChanged: _updateOriginSuggestions,
                      onEditingComplete: () {
                        final txt = _originController.text.trim();
                        if (txt.isEmpty) return;
                        Provider.of<UserPreferencesProvider>(context,
                                listen: false)
                            .updateOrigin(txt);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLocationField(
                      label: 'TO',
                      hint: 'Destination city',
                      icon: Icons.flight_land,
                      iconColor: Colors.redAccent,
                      controller: _destTopController,
                      focusNode: _destTopFocusNode,
                      layerLink: _destTopLayerLink,
                      fieldKey: _destTopFieldKey,
                      hasError: _showTripBasicsErrors &&
                          _destTopController.text.trim().isEmpty,
                      onChanged: _updateDestTopSuggestions,
                      onEditingComplete: () {
                        final txt = _destTopController.text.trim();
                        if (txt.isEmpty) return;
                        Provider.of<UserPreferencesProvider>(context,
                                listen: false)
                            .updateDestination(txt);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Trip dates (single date range picker)
              Builder(builder: (context) {
                final datesMissing =
                    _tripFromDate == null || _tripToDate == null;
                final dateError = _showTripBasicsErrors && datesMissing;
                final accent =
                    dateError ? _errorColor : const Color(0xFF4F46E5);
                return Material(
                  color: accent.withValues(alpha: dateError ? 0.04 : 0.07),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _pickTripDates,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: dateError ? 1 : 0.35),
                          width: dateError ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: 'TRIP DATES',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    children: const [
                                      TextSpan(
                                        text: ' *',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _errorColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  datesMissing
                                      ? 'Select travel dates'
                                      : '${_formatTripDate(_tripFromDate)}  -  ${_formatTripDate(_tripToDate)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: dateError
                                        ? _errorColor
                                        : datesMissing
                                            ? const Color(0xFF4F46E5)
                                                .withValues(alpha: 0.55)
                                            : const Color(0xFF3730A3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: accent),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),

              // Explore button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppConfig.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingDest ? null : _onExploreTripBasics,
                    icon: const Icon(Icons.explore,
                        color: Colors.white, size: 18),
                    label: Text(
                      _isLoadingDest ? 'Loading…' : 'Explore',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onExploreTripBasics() async {
    // FROM, TO and the trip dates are all required before exploring — see
    // _tripBasicsComplete for why.
    final missing = _missingTripBasics;
    if (missing.isNotEmpty) {
      setState(() => _showTripBasicsErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter ${_readableList(missing)}.')),
      );
      return;
    }
    if (_showTripBasicsErrors) {
      setState(() => _showTripBasicsErrors = false);
    }

    final destText = _destTopController.text.trim();
    final originText = _originController.text.trim();

    if (!_tripToDate!.isAfter(_tripFromDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your return date must be after your departure date.'),
        ),
      );
      return;
    }

    final provider =
        Provider.of<UserPreferencesProvider>(context, listen: false);
    provider.updateOrigin(originText);
    provider.updateDestination(destText);
    provider.updateDates(_tripFromDate!, _tripToDate!);
    provider.updateNumberOfPeople(_numberOfPeople);

    setState(() {
      // Unlocks "Where to next?". Set only after validation passes, so the
      // section stays locked when Explore is tapped with fields missing.
      _exploreTapped = true;
      _searchController.text = destText;
      _expanded
        ..clear()
        ..add(0);
    });

    // Open "Where to next?" and bring it into view BEFORE fetching, so the
    // tap has an immediate visible effect. Interests can take several seconds
    // to come back; opening first means the user watches the section load
    // rather than staring at an unchanged screen.
    if (!_section0Controller.isExpanded) {
      _section0Controller.expand();
    }
    await _scrollSectionIntoView(_section0Key);

    await _fetchCityInterests();
  }

  /// Scrolls [key]'s widget to the top of the accordion viewport. Waits a
  /// frame first so the freshly expanded section has been laid out at its
  /// final height — measuring before that lands the scroll short.
  Future<void> _scrollSectionIntoView(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final sectionContext = key.currentContext;
    if (sectionContext == null || !sectionContext.mounted) return;
    await Scrollable.ensureVisible(
      sectionContext,
      alignment: 0.05,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ---------------------------------------------------------------------------
  // Build – shared scaffold (vertical accordion)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppConfig.primaryGradient,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ---------- Header ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConfig.paddingMedium,
                      0,
                      AppConfig.paddingMedium,
                      AppConfig.paddingSmall,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Get.back(),
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => Get.toNamed('/account'),
                              icon: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: const Text(
                                'Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Plan your trip',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fill the sections in order. Each one unlocks the next.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---------- Scrollable accordion ----------
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConfig.paddingMedium,
                        0,
                        AppConfig.paddingMedium,
                        AppConfig.paddingMedium,
                      ),
                      child: Column(
                        children: [
                          _buildTripBasicsCard(),
                          KeyedSubtree(
                            key: _section0Key,
                            child: _buildAccordionSection(
                              controller: _section0Controller,
                              index: 0,
                              title: 'Where to next?',
                              subtitle: _loadedCity.isEmpty
                                  ? 'Choose your destination & activities'
                                  : _loadedCity,
                              icon: Icons.explore,
                              isComplete: _isSectionComplete(0),
                              isUnlocked: _isSectionUnlocked(0),
                              lockedHint:
                                  'Fill in Trip basics above and tap Explore',
                              body: _buildDestinationStep(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildAccordionSection(
                            index: 1,
                            title: 'Budget & Allocation',
                            subtitle: _budgetController.text.trim().isEmpty
                                ? 'Set your trip budget and how to split it'
                                : _formatBudgetAmount(_enteredBudget ?? 0),
                            icon: Icons.account_balance_wallet,
                            isComplete: _isSectionComplete(1),
                            isUnlocked: _isSectionUnlocked(1),
                            body: _buildBudgetStep(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ---------- Bottom action ----------
                  Padding(
                    padding: const EdgeInsets.all(AppConfig.paddingMedium),
                    child: Opacity(
                      opacity: _allComplete ? 1.0 : 0.55,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _allComplete ? _completeOnboarding : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: Text(
                            _allComplete
                                ? 'Complete Profile & Start Discovery'
                                : _tripBasicsComplete
                                    ? 'Fill all sections to continue'
                                    : 'Add ${_readableList(_missingTripBasics)} to continue',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const UserProgressCheckpoint(),
        ],
      ),
    );
  }

  // Renders one wizard step as an ExpansionTile (or a locked placeholder if
  // isUnlocked is false). Opening a section auto-closes any other open one,
  // since _expanded is cleared before the new index is added, keeping the
  // wizard to one open section at a time.
  Widget _buildAccordionSection({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isComplete,
    required bool isUnlocked,
    required Widget body,
    ExpansibleController? controller,
    String? lockedHint,
  }) {
    if (!isUnlocked) {
      return _buildLockedSection(
        title: title,
        icon: icon,
        hint: lockedHint ?? 'Finish the previous section to unlock',
      );
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            key: ValueKey('onboarding_section_$index'),
            controller: controller,
            initiallyExpanded: _expanded.contains(index),
            maintainState: true,
            onExpansionChanged: (open) {
              FocusScope.of(context).unfocus();
              setState(() {
                if (open) {
                  _expanded
                    ..clear()
                    ..add(index);
                } else {
                  _expanded.remove(index);
                }
              });
            },
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppConfig.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (isComplete)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade700, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Saved',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ),
            children: [body],
          ),
        ),
      ),
    );
  }

  /// A non-interactive placeholder shown for sections whose prerequisite
  /// (the previous section) has not been completed yet.
  // Greyed-out, non-interactive stand-in shown for a step whose predecessor
  // isn't complete yet (see _isSectionUnlocked).
  Widget _buildLockedSection({
    required String title,
    required IconData icon,
    // Section 0 isn't waiting on a previous section — it's waiting on the
    // Explore button — so the default hint would be actively misleading.
    String hint = 'Finish the previous section to unlock',
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.grey.shade500, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 22),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 UI – destination
  // ---------------------------------------------------------------------------
  Widget _buildDestinationStep() {
    final destText = _destTopController.text.trim();
    return Padding(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppConfig.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'DESTINATION',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destText.isEmpty
                            ? 'Set your destination in the "TO" field above'
                            : destText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: destText.isEmpty
                              ? Colors.black45
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoadingDest)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Discovering interests for your destination...',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (!_isLoadingDest && _aiCategories.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.explore, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      destText.isEmpty
                          ? 'Enter your destination in "TO" above and tap Explore'
                          : 'Tap Explore in Trip basics to load activities for $destText',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (!_isLoadingDest && _aiCategories.isNotEmpty) ...[
            Text(
              'Things to do in $_loadedCity',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the activities you\'re interested in',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ..._aiCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value;
              final color = _categoryColors[index % _categoryColors.length];
              final activities =
                  List<String>.from(category['activities'] ?? []);
              final iconName = category['icon'] ?? 'local_activity';
              final title = category['title'] ?? 'Category';

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _getIcon(iconName),
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: activities
                          .map(
                              (activity) => _buildActivityCard(activity, color))
                          .toList(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Selectable activity tile.
  //
  // Always the same 104x84 card, whether or not its photo has arrived. It used
  // to fall back to a FilterChip while loading, which meant every tile changed
  // width AND height when images landed — inside a Wrap that re-flowed the
  // whole grid and read as the section loading twice. Only the image layer
  // differs now, so the layout is computed once and never moves.
  Widget _buildActivityCard(String activity, Color color) {
    final isSelected = _selectedActivities.contains(activity);
    final imageUrl = _activityImages[activity];
    final hasImage = imageUrl != null;

    void toggle() {
      setState(() {
        if (isSelected) {
          _selectedActivities.remove(activity);
        } else {
          _selectedActivities.add(activity);
        }
      });
    }

    // Excluded from text selection.
    //
    // Every route is wrapped in SelectionArea (see main.dart), which registers
    // each Text as selectable and sorts them by screen position. Labels inside
    // an animating tile can be in the tree before they're laid out, and the
    // sort then reads paintBounds on an unlaid-out RenderParagraph:
    //   "RenderBox was not laid out: RenderParagraph ... NEEDS-LAYOUT"
    // These labels are chrome on a tappable tile, not prose worth selecting,
    // so keeping them out of the selection tree costs nothing.
    return SelectionContainer.disabled(
      child: InkWell(
        onTap: toggle,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 104,
          height: 84,
          clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fades the photo in over the placeholder rather than popping.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: hasImage
                  ? Image.network(
                      imageUrl,
                      key: ValueKey(imageUrl),
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : Container(color: Colors.grey[200]),
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: Colors.grey[200]),
                    )
                  : Container(
                      key: const ValueKey('placeholder'),
                      color: Colors.grey[200],
                    ),
            ),
            // Scrim only once there's a photo to darken; over the grey
            // placeholder it would just muddy it.
            if (hasImage)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                activity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // White reads against the scrim; without a photo behind it the
                // label needs dark text to stay legible on grey.
                style: TextStyle(
                  color: hasImage ? Colors.white : Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 UI – budget
  // ---------------------------------------------------------------------------
  Widget _buildBudgetStep() {
    return Padding(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter Amount',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrencyCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    icon: const Icon(Icons.arrow_drop_down),
                    items: _supportedCurrencyCodes.map((code) {
                      return DropdownMenuItem<String>(
                        value: code,
                        child: Text(code),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedCurrencyCode = value);
                      _reformatBudgetForCurrency();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _budgetController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      CurrencyInputFormatter(
                        currencyCode: _selectedCurrencyCode,
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Enter your budget',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppConfig.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Total Trip Budget',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _enteredBudget != null
                      ? _formatBudgetAmount(_enteredBudget!, includeCode: true)
                      : 'Not set',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 UI – additional context
  // ---------------------------------------------------------------------------
  Widget _buildAdditionalContextStep() {
    return Padding(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 40, color: AppConfig.primaryColor.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          const Text(
            'Anything else our AI should know?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share any special requirements, preferences, or context to help plan your perfect trip.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: TextField(
              controller: _aiContextController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText:
                    'e.g., We have a 3-year-old kid, need kid-friendly places. '
                    'My mom uses a wheelchair. We are celebrating our anniversary. '
                    'We prefer vegetarian food...',
                hintStyle: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  height: 1.5,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Travel Companion',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _companions
                .map((companion) => _buildSelectionChip(
                      companion,
                      _selectedCompanion == companion,
                      () => setState(() => _selectedCompanion = companion),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          const Text(
            'Special Occasions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _occasions
                .map((occasion) => _buildSelectionChip(
                      occasion,
                      _selectedOccasion == occasion,
                      () => setState(() => _selectedOccasion = occasion),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          const Text(
            'Travel Experience Level',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _experiences
                .map((experience) => _buildSelectionChip(
                      experience,
                      _selectedExperience == experience,
                      () => setState(() => _selectedExperience = experience),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
          const Text(
            'Accessibility & Special Needs',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildMultiSelectSection(
            'Accessibility Requirements',
            _accessibilityOptions,
            _selectedAccessibility,
          ),
          const SizedBox(height: 20),
          _buildMultiSelectSection(
            'Dietary Restrictions',
            _dietaryOptions,
            _selectedDietary,
          ),
          const SizedBox(height: 20),
          _buildMultiSelectSection(
            'Medical Needs',
            _medicalOptions,
            _selectedMedical,
          ),
          const SizedBox(height: 20),
          _buildMultiSelectSection(
            'Language Support',
            _languageOptions,
            _selectedLanguage,
          ),
        ],
      ),
    );
  }

  // Single-select chip (companion / occasion / experience level: only one
  // choice highlighted at a time within its group).
  Widget _buildSelectionChip(
      String label, bool isSelected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.grey[100],
      selectedColor: AppConfig.primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  // Multi-select chip group (accessibility / dietary / medical / language:
  // any number of options can be toggled on within its group).
  Widget _buildMultiSelectSection(
      String title, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map((option) => FilterChip(
                    label: Text(
                      option,
                      style: TextStyle(
                        color: selected.contains(option)
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                    selected: selected.contains(option),
                    onSelected: (isSelected) {
                      setState(() {
                        if (isSelected) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                      });
                    },
                    backgroundColor: Colors.grey[100],
                    selectedColor: AppConfig.primaryColor,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
