import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:animate_do/animate_do.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../services/affiliate_links.dart';
import '../services/api_service.dart';
import '../services/mock_data_service.dart';
import '../models/hotel.dart';
import '../providers/user_preferences_provider.dart';
import '../providers/hotel_shortlist_provider.dart';
import 'hotel_shortlist_screen.dart';

class SearchHotelsScreen extends StatefulWidget {
  const SearchHotelsScreen({super.key});

  @override
  State<SearchHotelsScreen> createState() => _SearchHotelsScreenState();
}

class _SearchHotelsScreenState extends State<SearchHotelsScreen> {
  final ApiService _api = ApiService();
  final MockDataService _mockData = MockDataService();
  final List<String> _cities = [
    'Mumbai',
    'Delhi',
    'Goa',
    'Bangalore',
    'Jaipur',
    'Kolkata',
    'Chennai',
    'Hyderabad'
  ];
  final List<String> _hotelTypes = [
    'All',
    'Resort',
    'Hotel',
    'Boutique',
    'Hostel'
  ];
  final List<String> _amenities = [
    'WiFi',
    'Pool',
    'Gym',
    'Parking',
    'Restaurant',
    'Bar',
    'Spa',
    'Beach Access'
  ];

  String? _selectedCity;
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _guests = 2;
  int _rooms = 0;
  String _specialRequest = '';
  RangeValues _priceRange = const RangeValues(0, 5000000);
  String _selectedType = 'All';
  final Set<String> _selectedAmenities = {};

  // Hotel preferences from home screen
  double _hotelBudget = 5000;
  String? _roomType;
  List<String> _foodTypes = [];
  String? _ambiance;
  List<String> _extras = [];
  Map<String, dynamic>? _aiCriteria; // AI-enhanced search criteria
  bool _aiPowered = false;

  List<Hotel> _searchResults = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
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
        _rooms = arguments['rooms'] as int? ?? 0;
        _specialRequest = arguments['specialRequest'] as String? ?? '';

        // Get hotel preferences
        _hotelBudget = arguments['hotelBudget'] as double? ?? 5000;
        _roomType = arguments['roomType'] as String?;
        _foodTypes =
            (arguments['foodTypes'] as List<dynamic>?)?.cast<String>() ?? [];
        _ambiance = arguments['ambiance'] as String?;
        _extras = (arguments['extras'] as List<dynamic>?)?.cast<String>() ?? [];

        // Get AI criteria
        _aiCriteria = arguments['aiCriteria'] as Map<String, dynamic>?;
        _aiPowered = arguments['aiPowered'] as bool? ?? false;

        // Update price range based on budget
        _priceRange = RangeValues(0, _hotelBudget);
      });
      // Auto-search if city is provided and matches
      if (_selectedCity != null && _cities.contains(_selectedCity)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchHotels();
        });
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
          _priceRange = RangeValues(0, _hotelBudget);
        });

        if (_cities.contains(_selectedCity)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _searchHotels();
          });
        }
      }
    }
  }

  /// Matches [rawCity] against the fixed dropdown list (case-insensitive).
  /// If there's no match — e.g. an onboarding destination like "Bhiwandi"
  /// that isn't one of the 8 preset cities — adds it to the list instead of
  /// dropping it, since DropdownButtonFormField asserts if its value isn't
  /// exactly one of its items. Keeps whatever the user picked in onboarding
  /// visible rather than silently clearing it.
  String _resolveCity(String rawCity) {
    final trimmed = rawCity.trim();
    final matches =
        _cities.where((city) => city.toLowerCase() == trimmed.toLowerCase());
    if (matches.isNotEmpty) return matches.first;
    _cities.add(trimmed);
    return trimmed;
  }

  Future<void> _searchHotels() async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a city')),
      );
      return;
    }

    setState(() => _loading = true);

    List<Hotel> results = [];
    bool usedMockData = false;

    try {
      // If AI-powered search is available, use it
      if (_aiPowered && _aiCriteria != null) {
        // Use AI-powered search
        results = await _mockData.searchHotelsWithAI(
          city: _selectedCity!,
          minPrice: _priceRange.start,
          maxPrice: _priceRange.end,
          aiCriteria: _aiCriteria,
        );
        usedMockData = true;

        // Show AI-powered message
        if (mounted && _aiCriteria!['intent'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '✨ AI found ${results.length} hotels: ${_aiCriteria!['intent']}'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.deepPurple,
            ),
          );
        }
      } else {
        // Regular search flow
        // If special request is provided, send to AI first
        if (_specialRequest.isNotEmpty) {
          try {
            final aiResponse = await _api.sendMessage(
              'I am looking for hotels in $_selectedCity. Special request: $_specialRequest. '
              'Check-in: ${_checkIn.toString().split(' ')[0]}, Check-out: ${_checkOut.toString().split(' ')[0]}, '
              'Guests: $_guests, Rooms: $_rooms',
            );

            // Show AI response
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'AI: ${aiResponse['response'] ?? 'Searching hotels...'}'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: AppConfig.accentColor,
                ),
              );
            }
          } catch (aiError) {
            print('AI request failed: $aiError');
            // Continue with search even if AI fails
          }
        }

        // Try backend API first
        try {
          results = await _api.getHotels(
            city: _selectedCity!,
            minPrice: _priceRange.start,
            maxPrice: _priceRange.end,
            type: _selectedType == 'All' ? null : _selectedType,
            amenities: _selectedAmenities.toList(),
          );
        } catch (apiError) {
          print('Backend API failed, using mock data: $apiError');
          // Fallback to mock data with AI prompt support
          results = await _mockData.searchHotels(
            city: _selectedCity!,
            minPrice: _priceRange.start,
            maxPrice: _priceRange.end,
            type: _selectedType == 'All' ? null : _selectedType,
            amenities: _selectedAmenities.toList(),
            aiPrompt: _specialRequest.isNotEmpty ? _specialRequest : null,
          );
          usedMockData = true;

          // Generate smart AI response for mock data
          if (_specialRequest.isNotEmpty && mounted) {
            final aiMessage =
                _mockData.generateAIResponse(_specialRequest, results.length);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('AI: $aiMessage'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
      }

      // Auto-navigate to dedicated results screen if we have results
      // IMPORTANT: Navigate BEFORE setState to avoid rendering issues on web
      if (mounted && results.isNotEmpty) {
        print('Navigating to results screen with ${results.length} hotels.');
        // Convert List<Hotel> to List<Map<String, dynamic>> for safe web navigation
        final hotelsAsJson = results.map((h) => h.toJson()).toList();
        Get.toNamed('/hotel-results', arguments: {
          'hotels': hotelsAsJson,
          'criteria': {
            'city': _selectedCity,
            'price':
                '₹${_priceRange.start.toInt()} - ₹${_priceRange.end.toInt()}',
            'type': _selectedType,
            if (_selectedAmenities.isNotEmpty)
              'amenities': _selectedAmenities.toList(),
            if (_roomType != null) 'room_type': _roomType,
            if (_ambiance != null) 'ambiance': _ambiance,
            if (_extras.isNotEmpty) 'extras': _extras,
            if (_specialRequest.isNotEmpty) 'special_request': _specialRequest,
          },
        });
        // Set loading to false after navigation starts
        setState(() => _loading = false);
        return; // Exit early to prevent inline rendering
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _searched = true;
          _loading = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              usedMockData
                  ? 'Found ${results.length} hotels in $_selectedCity (Using offline data)'
                  : 'Found ${results.length} hotels in $_selectedCity',
            ),
            backgroundColor: usedMockData ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Search error: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching hotels: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _searchHotels,
            ),
          ),
        );
      }
    }
  }

  Future<void> _searchHotelsWithAI() async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a city')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Build AI search message from preferences
      String message = _specialRequest.isNotEmpty ? _specialRequest : '';

      // Add preferences to message if no special request
      if (message.isEmpty) {
        List<String> criteria = [];
        if (_roomType != null) criteria.add('$_roomType room');
        if (_ambiance != null) criteria.add('$_ambiance ambiance');
        if (_foodTypes.isNotEmpty) {
          criteria.add('${_foodTypes.join(", ")} food');
        }
        if (_extras.isNotEmpty) criteria.add(_extras.join(', '));
        if (_selectedAmenities.isNotEmpty) {
          criteria.add(_selectedAmenities.join(', '));
        }

        message = criteria.isNotEmpty
            ? 'Find hotel with ${criteria.join(", ")}'
            : 'Find best hotels, $_rooms ${_rooms == 1 ? 'room' : 'rooms'}';
      }

      // Call AI-powered search
      final result = await _api.searchHotelsWithAI(
        message: message,
        city: _selectedCity!,
        budget: _priceRange.end,
        roomType: _roomType,
        foodTypes: _foodTypes,
        ambiance: _ambiance,
        extras: _extras,
      );

      final aiHotels = result['hotels'] as List<Hotel>;

      // Auto-navigate to results screen for AI search
      // IMPORTANT: Navigate BEFORE setState to avoid rendering issues on web
      if (mounted && aiHotels.isNotEmpty) {
        print(
            'Navigating to AI results screen with ${aiHotels.length} hotels.');
        // Convert List<Hotel> to List<Map<String, dynamic>> for safe web navigation
        final hotelsAsJson = aiHotels.map((h) => h.toJson()).toList();
        Get.toNamed('/hotel-results', arguments: {
          'hotels': hotelsAsJson,
          'criteria': {
            'city': _selectedCity,
            'budget': 'Up to ₹${_priceRange.end.toInt()}',
            if (_roomType != null) 'room_type': _roomType,
            if (_ambiance != null) 'ambiance': _ambiance,
            if (_foodTypes.isNotEmpty) 'food': _foodTypes,
            if (_selectedAmenities.isNotEmpty)
              'amenities': _selectedAmenities.toList(),
            if (_extras.isNotEmpty) 'extras': _extras,
            if (_specialRequest.isNotEmpty) 'special_request': _specialRequest,
            'ai': true,
          },
        });
        // Set loading to false after navigation starts
        setState(() => _loading = false);
        return; // Exit early to prevent inline rendering
      }

      if (mounted) {
        setState(() {
          _searchResults = aiHotels;
          _searched = true;
          _loading = false;
        });

        // Show AI success message with overall advice
        final advice = result['overall_advice'] ?? result['ai_advice'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '✨ AI found ${_searchResults.length} perfect matches!',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (advice.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    advice,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.deepPurple,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('AI Search error: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'AI Search unavailable. Make sure server is running!'),
                const SizedBox(height: 4),
                Text(
                  'Error: ${e.toString()}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            duration: const Duration(seconds: 7),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Use Regular Search',
              textColor: Colors.white,
              onPressed: _searchHotels,
            ),
          ),
        );
      }
    }
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
                  // City Dropdown
                  FadeInDown(
                    child: _buildSectionTitle('Where?'),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 50),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCity,
                      decoration: InputDecoration(
                        hintText: 'Select city',
                        prefixIcon: const Icon(Icons.location_city),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConfig.radiusMedium),
                        ),
                      ),
                      items: _cities.map((city) {
                        return DropdownMenuItem(value: city, child: Text(city));
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedCity = value),
                    ),
                  ),

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

                  // Rooms
                  FadeInDown(
                    delay: const Duration(milliseconds: 200),
                    child: _buildSectionTitle('Rooms'),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 250),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(
                              () => _rooms = (_rooms - 1).clamp(0, 10)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '$_rooms ${_rooms == 1 ? 'Room' : 'Rooms'}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(
                              () => _rooms = (_rooms + 1).clamp(0, 10)),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Price Range
                  FadeInDown(
                    delay: const Duration(milliseconds: 300),
                    child: _buildSectionTitle(
                        'Price Range (₹${_priceRange.start.toInt()} - ₹${_priceRange.end.toInt()})'),
                  ),
                  FadeInDown(
                    delay: const Duration(milliseconds: 350),
                    child: RangeSlider(
                      values: _priceRange,
                      min: 0,
                      max: 5000000,
                      divisions: 100,
                      labels: RangeLabels('₹${_priceRange.start.toInt()}',
                          '₹${_priceRange.end.toInt()}'),
                      onChanged: (values) =>
                          setState(() => _priceRange = values),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Hotel Type
                  FadeInDown(
                    delay: const Duration(milliseconds: 400),
                    child: _buildSectionTitle('Hotel Type'),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 450),
                    child: Wrap(
                      spacing: 8,
                      children: _hotelTypes.map((type) {
                        return ChoiceChip(
                          label: Text(type),
                          selected: _selectedType == type,
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedType = type);
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Amenities
                  FadeInDown(
                    delay: const Duration(milliseconds: 500),
                    child: _buildSectionTitle('Amenities'),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 550),
                    child: Wrap(
                      spacing: 8,
                      children: _amenities.map((amenity) {
                        return FilterChip(
                          label: Text(amenity),
                          selected: _selectedAmenities.contains(amenity),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedAmenities.add(amenity);
                              } else {
                                _selectedAmenities.remove(amenity);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),

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
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Search Hotels',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // AI-Powered Search Button
                  FadeInUp(
                    delay: const Duration(milliseconds: 100),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _searchHotelsWithAI,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: Colors.deepPurple.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome,
                            color: Colors.deepPurple),
                        label: const Text(
                          '✨ AI-Powered Search (Gemini 2.0)',
                          style:
                              TextStyle(fontSize: 16, color: Colors.deepPurple),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                          onPressed: () => AffiliateLinks.open(
                            AffiliateLinks.aviasalesHotelSearch(
                              hotel: hotel,
                              checkIn: checkIn,
                              checkOut: checkOut,
                              guests: guests,
                            ),
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
