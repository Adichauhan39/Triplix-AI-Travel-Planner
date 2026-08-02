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

/// Single-page onboarding wizard that merges the four preference screens
/// (destination, budget, transport, additional context) into a stepper
/// flow with shared Back/Next navigation.
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

  final TextEditingController _destTopController = TextEditingController();
  final FocusNode _destTopFocusNode = FocusNode();
  List<Map<String, String>> _destTopSuggestions = [];
  bool _showDestTopSuggestions = false;
  Timer? _destTopDebounce;
  String _lastDestTopQuery = '';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PythonADKService _adkService = PythonADKService();
  final GooglePlacesService _placesService = GooglePlacesService();
  final Map<String, List<Map<String, String>>> _citySuggestionCache = {};

  List<Map<String, dynamic>> _aiCategories = [];
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

  final Map<String, double> _allocations = {
    'accommodation': 0.0,
    'transportation': 0.0,
    'food': 0.0,
    'activities': 0.0,
    'shopping': 0.0,
    'miscellaneous': 0.0,
  };

  final List<Map<String, dynamic>> _budgetCategories = [
    {'id': 'accommodation', 'title': 'Accommodation', 'icon': Icons.hotel},
    {
      'id': 'transportation',
      'title': 'Transportation',
      'icon': Icons.directions_car
    },
    {'id': 'food', 'title': 'Food & Dining', 'icon': Icons.restaurant},
    {'id': 'activities', 'title': 'Activities', 'icon': Icons.local_activity},
    {'id': 'shopping', 'title': 'Shopping', 'icon': Icons.shopping_bag},
    {'id': 'miscellaneous', 'title': 'Emergency & Misc', 'icon': Icons.warning},
  ];
  final Map<String, TextEditingController> _allocationAmountControllers = {};

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

    final local = _localCityFallback
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

    _citySuggestionCache[qLower] = local;
    return local;
  }

  // ---------------------------------------------------------------------------
  // Step 3: Transport
  // ---------------------------------------------------------------------------
  final TextEditingController _transportController = TextEditingController();

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
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      _allocationAmountControllers[categoryId] =
          TextEditingController(text: '0');
    }
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    _originController.dispose();
    _originFocusNode.dispose();
    _destTopController.dispose();
    _destTopFocusNode.dispose();
    _budgetController.dispose();
    for (final controller in _allocationAmountControllers.values) {
      controller.dispose();
    }
    _transportController.dispose();
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
      case 2:
        return _transportController.text.trim().isNotEmpty;
      case 3:
        return _hasContextSelections;
      default:
        return false;
    }
  }

  // A section is unlocked iff every previous section is complete.
  bool _isSectionUnlocked(int index) {
    if (index == 0) return true;
    return _isSectionComplete(index - 1);
  }

  bool get _allComplete =>
      _isSectionComplete(0) && _isSectionComplete(1) && _isSectionComplete(2);

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

    // Step 3
    final txt = _transportController.text.trim();
    if (txt.isNotEmpty) {
      provider.updateTransport(
        txt.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      );
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

  Future<void> _fetchCityInterests() async {
    final city = _searchController.text.trim();
    if (city.isEmpty) return;
    if (city.toLowerCase() == _loadedCity.toLowerCase()) return;

    setState(() {
      _showSuggestions = false;
      _filteredSuggestions = [];
      _isLoadingDest = true;
      _aiCategories = [];
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
      } else {
        if (mounted) {
          setState(() {
            _aiCategories = _fallbackInterestCategories(resolvedCity);
            _loadedCity = resolvedCity;
            _isLoadingDest = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiCategories = _fallbackInterestCategories(city);
          _loadedCity = city;
          _isLoadingDest = false;
        });
      }
    }
  }

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
  void _updateAllocation(String categoryId, double newValue) {
    setState(() {
      _allocations[categoryId] = newValue;
    });
    _syncAllocationAmountControllers();
  }

  void _syncAllocationAmountControllers({String? skipCategoryId}) {
    final enteredBudget = _enteredBudget ?? 0;
    final formatter = groupedNumberFormat(_selectedCurrencyCode);
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      if (categoryId == skipCategoryId) continue;

      final controller = _allocationAmountControllers[categoryId];
      if (controller == null) continue;

      final amount = enteredBudget * (_allocations[categoryId] ?? 0);
      final text = formatter.format(amount.round());
      if (controller.text != text) {
        controller.value = controller.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  void _updateAllocationFromAmount(String categoryId, String rawValue) {
    final enteredBudget = _enteredBudget ?? 0;
    final parsed = double.tryParse(rawValue.replaceAll(',', '').trim());
    if (parsed == null || enteredBudget <= 0) return;

    final clampedAmount = parsed.clamp(0, enteredBudget);
    final ratio = enteredBudget == 0 ? 0.0 : clampedAmount / enteredBudget;

    setState(() {
      _allocations[categoryId] = ratio;
    });
    _syncAllocationAmountControllers();
  }

  DateTime get _tripFirstAllowedDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _tripLastAllowedDate => DateTime(DateTime.now().year + 3);

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
              primary: AppConfig.primaryColor,
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
  void _updateOriginSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      _originDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _originSuggestions = [];
        _showOriginSuggestions = false;
      });
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
      return;
    }

    _lastOriginQuery = q;

    final prefixCached = _getPrefixCachedSuggestions(q);
    if (prefixCached.isNotEmpty) {
      setState(() {
        _originSuggestions = prefixCached;
        _showOriginSuggestions = true;
      });
    }

    final suggestions = await _getFastCitySuggestions(query);

    if (!mounted || _originController.text.trim().toLowerCase() != q) return;

    setState(() {
      _originSuggestions = suggestions;
      _showOriginSuggestions = suggestions.isNotEmpty;
    });
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
      return;
    }

    _lastDestTopQuery = q;

    final prefixCached = _getPrefixCachedSuggestions(q);
    if (prefixCached.isNotEmpty) {
      setState(() {
        _destTopSuggestions = prefixCached;
        _showDestTopSuggestions = true;
      });
    }

    final suggestions = await _getFastCitySuggestions(query);

    if (!mounted || _destTopController.text.trim().toLowerCase() != q) return;

    setState(() {
      _destTopSuggestions = suggestions;
      _showDestTopSuggestions = suggestions.isNotEmpty;
    });
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

    Provider.of<UserPreferencesProvider>(context, listen: false)
        .updateDestination(formatted);
    FocusScope.of(context).unfocus();
  }

  void _updatePeopleCount(int nextCount) {
    final clamped = nextCount.clamp(1, 20);
    setState(() {
      _numberOfPeople = clamped;
    });
    Provider.of<UserPreferencesProvider>(context, listen: false)
        .updateNumberOfPeople(_numberOfPeople);
  }

  String _formatTripDate(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Widget _buildLocationField({
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    VoidCallback? onEditingComplete,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
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
    );
  }

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
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _pickTripDates,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month,
                            size: 18, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'TRIP DATES',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (_tripFromDate == null || _tripToDate == null)
                                    ? 'Select travel dates'
                                    : '${_formatTripDate(_tripFromDate)}  -  ${_formatTripDate(_tripToDate)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: (_tripFromDate == null ||
                                          _tripToDate == null)
                                      ? Colors.black45
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.black45),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Number of people
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups_2, size: 18, color: Colors.black54),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Number of people',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _numberOfPeople > 1
                          ? () => _updatePeopleCount(_numberOfPeople - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      '$_numberOfPeople',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: _numberOfPeople < 20
                          ? () => _updatePeopleCount(_numberOfPeople + 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

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
          if ((_showOriginSuggestions && _originSuggestions.isNotEmpty) ||
              (_showDestTopSuggestions && _destTopSuggestions.isNotEmpty))
            Positioned(
              top: 84,
              left: 0,
              right: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _showOriginSuggestions &&
                            _originSuggestions.isNotEmpty
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: _buildTopSuggestionList(
                                _originSuggestions,
                                _selectOriginSuggestion,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _showDestTopSuggestions &&
                            _destTopSuggestions.isNotEmpty
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: _buildTopSuggestionList(
                                _destTopSuggestions,
                                _selectDestTopSuggestion,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onExploreTripBasics() async {
    final destText = _destTopController.text.trim();
    if (destText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your destination (TO) first.'),
        ),
      );
      return;
    }

    final provider =
        Provider.of<UserPreferencesProvider>(context, listen: false);
    final originText = _originController.text.trim();
    if (originText.isNotEmpty) provider.updateOrigin(originText);
    provider.updateDestination(destText);
    if (_tripFromDate != null && _tripToDate != null) {
      provider.updateDates(_tripFromDate!, _tripToDate!);
    }
    provider.updateNumberOfPeople(_numberOfPeople);

    setState(() {
      _searchController.text = destText;
      _expanded.add(0);
    });

    await _fetchCityInterests();
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
                          _buildAccordionSection(
                            index: 0,
                            title: 'Where to next?',
                            subtitle: _loadedCity.isEmpty
                                ? 'Choose your destination & activities'
                                : _loadedCity,
                            icon: Icons.explore,
                            isComplete: _isSectionComplete(0),
                            isUnlocked: _isSectionUnlocked(0),
                            body: _buildDestinationStep(),
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
                          const SizedBox(height: 12),
                          _buildAccordionSection(
                            index: 2,
                            title: 'How do you like to travel?',
                            subtitle: _transportController.text.trim().isEmpty
                                ? 'Tell us your transport preferences'
                                : 'Preferences saved',
                            icon: Icons.directions_bus,
                            isComplete: _isSectionComplete(2),
                            isUnlocked: _isSectionUnlocked(2),
                            body: _buildTransportStep(),
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
                                : 'Fill all sections to continue',
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

  Widget _buildAccordionSection({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isComplete,
    required bool isUnlocked,
    required Widget body,
  }) {
    if (!isUnlocked) {
      return _buildLockedSection(title: title, icon: icon);
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
  Widget _buildLockedSection({required String title, required IconData icon}) {
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
                  'Finish the previous section to unlock',
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
                      children: activities.map((activity) {
                        final isSelected =
                            _selectedActivities.contains(activity);
                        return FilterChip(
                          label: Text(
                            activity,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              if (isSelected) {
                                _selectedActivities.remove(activity);
                              } else {
                                _selectedActivities.add(activity);
                              }
                            });
                          },
                          backgroundColor: Colors.grey[100],
                          selectedColor: color,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }).toList(),
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
                    onChanged: (_) {
                      setState(() {});
                      _syncAllocationAmountControllers();
                    },
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
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final enteredBudget = _enteredBudget ?? 0;
              final totalAllocated =
                  _allocations.values.fold<double>(0, (sum, v) => sum + v);
              final allocatedAmount = enteredBudget * totalAllocated;
              final remaining = enteredBudget - allocatedAmount;
              final isNegative = remaining < 0;
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: isNegative ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isNegative
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Remaining budget',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isNegative
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                    Text(
                      '${isNegative ? '-' : ''}${_formatBudgetAmount(remaining.abs())}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isNegative ? Colors.red : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Container(
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
          const SizedBox(height: 24),
          const Text(
            'Budget Allocation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ..._budgetCategories.map(_buildBudgetSlider),
          const SizedBox(height: 24),
          const Text(
            'Allocation Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: _budgetCategories.map((category) {
                final percentage = _allocations[category['id']]! * 100;
                final amount =
                    (_enteredBudget ?? 0) * _allocations[category['id']]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(category['icon'] as IconData,
                          size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          category['title'] as String,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(0)}% / ${_formatBudgetAmount(amount)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetSlider(Map<String, dynamic> category) {
    final categoryId = category['id'] as String;
    final currentValue = _allocations[categoryId]!;
    final amount = (_enteredBudget ?? 0) * currentValue;
    final enteredBudget = _enteredBudget ?? 0;
    final totalAllocated =
        _allocations.values.fold<double>(0, (sum, v) => sum + v);
    final remaining = enteredBudget - (enteredBudget * totalAllocated);
    final isNegative = remaining < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category['icon'] as IconData,
                  size: 20, color: AppConfig.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category['title'] as String,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              Text(
                '${(currentValue * 100).toStringAsFixed(0)}% • ${_formatBudgetAmount(amount)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConfig.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isNegative ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color:
                      isNegative ? Colors.red.shade300 : Colors.green.shade300,
                ),
              ),
              child: Text(
                'Remaining: ${isNegative ? '-' : ''}${_formatBudgetAmount(remaining.abs())}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      isNegative ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppConfig.primaryColor,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: AppConfig.primaryColor,
              overlayColor: AppConfig.primaryColor.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: currentValue,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: (value) => _updateAllocation(categoryId, value),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allocationAmountControllers[categoryId],
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    CurrencyInputFormatter(currencyCode: _selectedCurrencyCode),
                  ],
                  onChanged: (value) =>
                      _updateAllocationFromAmount(categoryId, value),
                  decoration: InputDecoration(
                    hintText: 'Enter value directly',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _selectedCurrencyCode,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 UI – transport
  // ---------------------------------------------------------------------------
  Widget _buildTransportStep() {
    return Padding(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.smart_toy_outlined,
              size: 48, color: AppConfig.primaryColor.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          const Text(
            'Tell our AI your transport preferences',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Describe how you prefer to travel and our AI will find the best options for you.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: TextField(
              controller: _transportController,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText:
                    'e.g., I prefer trains over buses because I get motion sick. '
                    'I like scenic routes even if they take longer. '
                    'For local travel I prefer auto or cab. '
                    'Budget-friendly options are fine for short distances...',
                hintStyle: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  height: 1.5,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Choose transport modes (tap to add):',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              {
                'label': 'Flight',
                'value': 'Prefer flights',
                'icon': Icons.flight,
              },
              {
                'label': 'Train',
                'value': 'Train travel preferred',
                'icon': Icons.train,
              },
              {
                'label': 'Cab',
                'value': 'Cab/Auto for local travel',
                'icon': Icons.local_taxi,
              },
              {
                'label': 'Self Drive',
                'value': 'Self-drive preferred',
                'icon': Icons.directions_car,
              },
              {
                'label': 'Bus',
                'value': 'Budget bus preferred',
                'icon': Icons.directions_bus,
              },
            ].map((item) {
              final label = item['label']! as String;
              final value = item['value']! as String;
              final icon = item['icon']! as IconData;
              final selected = _transportController.text
                  .toLowerCase()
                  .contains(value.toLowerCase());

              return InkWell(
                onTap: () {
                  final current = _transportController.text.trim();
                  if (current.toLowerCase().contains(value.toLowerCase())) {
                    return;
                  }
                  if (current.isEmpty) {
                    _transportController.text = value;
                  } else {
                    _transportController.text = '$current, $value';
                  }
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 112,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppConfig.primaryColor.withValues(alpha: 0.12)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppConfig.primaryColor
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 28,
                        color:
                            selected ? AppConfig.primaryColor : Colors.black54,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppConfig.primaryColor
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
