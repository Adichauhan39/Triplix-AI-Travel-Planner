import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/hotel.dart';
import '../services/python_adk_service.dart';
import '../services/voice_input_service.dart';
import '../services/trip_photo_service.dart';
import '../providers/user_preferences_provider.dart';
import '../widgets/triplix_logo.dart';
import 'trip_plan_screen.dart';
import '../widgets/plan_quick_edit.dart';
import 'bookings_screen.dart';
import 'mock_booking_screen.dart';
import 'route_map_screen.dart';
import 'trip_reel_screen.dart';
import 'trip_itinerary_screen.dart';
import 'account_screen.dart';
import 'search_hotels_screen.dart';
import 'search_flights_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // The plan takes the slot the swipe deck had. Swiping asked the user to
  // make a decision per card with no overview; the plan shows the finished
  // trip and lets them change it. SwipeScreen still exists and its route is
  // intact, so putting it back is a one-line change.
  final List<Widget> _screens = [
    const HomeTab(),
    const TripPlanScreen(),
    const BookingsScreen(),
    const BudgetTab(),
    const ProfileTab(),
    const AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const PlanQuickEditButton(),
      body: Stack(
        children: [
          // Each tab is told whether it is the one on screen.
          //
          // IndexedStack keeps every tab mounted and building, so a tab can
          // act while the user is looking at another one -- the trip planner
          // opened a "days still need filling" sheet over the Account page,
          // on top of a sign-out dialog. TickerMode is the standard channel
          // for this: a hidden tab reads TickerMode.of(context) as false and
          // can hold back anything that interrupts.
          IndexedStack(
            index: _selectedIndex,
            children: [
              for (var i = 0; i < _screens.length; i++)
                TickerMode(
                  enabled: i == _selectedIndex,
                  child: _screens[i],
                ),
            ],
          ),
          Positioned(
            top: 10,
            right: 12,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedIndex = 5),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedIndex == 5
                              ? Icons.person
                              : Icons.person_outline,
                          color: AppConfig.primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Account',
                          style: TextStyle(
                            color: AppConfig.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppConfig.primaryColor,
        unselectedItemColor: AppConfig.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Trip',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            activeIcon: Icon(Icons.bookmark),
            label: 'Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Budget',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_mosaic_outlined),
            activeIcon: Icon(Icons.auto_awesome_mosaic),
            label: 'Reel',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode(); // Add focus node
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  final ScrollController _scrollController =
      ScrollController(); // Add scroll controller
  bool _hasShownConfirmation = false;
  DateTime? _startDate;
  DateTime? _endDate;

  // Confirmation form controllers
  final TextEditingController _fromLocationController = TextEditingController();
  final TextEditingController _toLocationController = TextEditingController();
  final TextEditingController _datesController = TextEditingController();
  final TextEditingController _stayCityController = TextEditingController();
  final TextEditingController _additionalQueryController =
      TextEditingController();

  final PythonADKService _pythonADK = PythonADKService();
  final FocusNode _fromFocusNode = FocusNode();
  Timer? _fromSuggestionDebounce;
  List<Map<String, String>> _fromSuggestions = [];
  bool _showFromSuggestions = false;
  String _lastFromQuery = '';

  // Add a dummy state variable to force rebuilds
  int _rebuildCounter = 0;
  bool _forceRebuild = false; // Add this flag

  // Swipe functionality
  final CardSwiperController _cardController = CardSwiperController();
  List<Map<String, dynamic>> _currentSuggestions = [];
  final Set<String> _acceptedSuggestions = {};
  final Set<String> _rejectedSuggestions = {};

  // Multi-stage swipe workflow
  String _currentSwipeStage =
      'transport'; // transport -> accommodation -> destinations
  bool _isFullItineraryMode =
      false; // Controls whether to use multi-stage workflow
  final List<Map<String, dynamic>> _acceptedTransport = [];
  final List<Map<String, dynamic>> _acceptedAccommodation = [];
  final List<Map<String, dynamic>> _acceptedDestinations = [];
  String?
      _lastGeneratedItinerary; // Store last itinerary for modification requests
  Map<String, dynamic>? _lastGeneratedItineraryData;

  // MakeMyTrip-style form state (form removed — kept for AI chat context fallback)
  bool _showTripForm = false;
  int _travelers = 1;
  int _rooms = 1;

  @override
  void initState() {
    super.initState();
    // Add initial greeting message
    _messages.add({
      'sender': 'triplix',
      'message':
          'Hi! I\'m Triplix, your AI travel assistant. Ask me anything about your trip.',
      'type': 'text',
      'timestamp': DateTime.now().toString(),
    });
    // Auto-fill "To" from destination preferences
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = context.read<UserPreferencesProvider>().preferences;
      if (prefs.destination != null && prefs.destination!.isNotEmpty) {
        _toLocationController.text = prefs.destination!;
        _stayCityController.text = prefs.destination!;
      }
    });
    _fromFocusNode.addListener(() {
      if (!_fromFocusNode.hasFocus && mounted) {
        setState(() {
          _showFromSuggestions = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _fromSuggestionDebounce?.cancel();
    _fromFocusNode.dispose();
    _queryController.dispose();
    _queryFocusNode.dispose(); // Dispose focus node
    _fromLocationController.dispose();
    _toLocationController.dispose();
    _datesController.dispose();
    _stayCityController.dispose();
    _additionalQueryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFromSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      _fromSuggestionDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _fromSuggestions = [];
        _showFromSuggestions = false;
      });
      return;
    }

    if (normalized == _lastFromQuery) return;

    _fromSuggestionDebounce?.cancel();
    _fromSuggestionDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadFromSuggestions(query),
    );
  }

  Future<void> _loadFromSuggestions(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return;

    _lastFromQuery = q;
    final suggestions = await _pythonADK.getDestinationSuggestions(
      query: query,
      limit: 8,
      preferPlaces: true,
    );

    if (!mounted || _fromLocationController.text.trim().toLowerCase() != q) {
      return;
    }

    setState(() {
      _fromSuggestions = suggestions;
      _showFromSuggestions = suggestions.isNotEmpty && _fromFocusNode.hasFocus;
    });
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

      return '$trimmedCity, $trimmedDescription';
    }

    if (trimmedCountry.isNotEmpty) {
      return '$trimmedCity, $trimmedCountry';
    }
    return trimmedCity;
  }

  void _selectFromSuggestion(Map<String, String> suggestion) {
    final city = suggestion['city'] ?? '';
    final country = suggestion['country'] ?? '';
    final description = suggestion['description'] ?? '';
    final formatted = _formatLocationLabel(
      city: city,
      country: country,
      description: description,
    );

    setState(() {
      _fromLocationController.text = formatted;
      _fromLocationController.selection = TextSelection.fromPosition(
        TextPosition(offset: _fromLocationController.text.length),
      );
      _fromSuggestions = [];
      _showFromSuggestions = false;
      _lastFromQuery = '';
    });

    FocusScope.of(context).unfocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _processTravelDetails() async {
    // Calculate number of days
    final days = _endDate!.difference(_startDate!).inDays + 1;

    // Show confirmation message
    setState(() {
      _messages.add({
        'sender': 'triplix',
        'message': 'Great! I have your travel details:\n'
            '📍 From: ${_fromLocationController.text}\n'
            '📍 To: ${_toLocationController.text}\n'
            '🏨 Stay: ${_stayCityController.text}\n'
            '📅 Dates: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate!.day}/${_endDate!.month}/${_endDate!.year} ($days days)\n\n'
            'Let me help you build your perfect itinerary step by step!',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
      _isTyping = true;
      _hasShownConfirmation = true;

      // Enable multi-stage workflow for full itinerary
      _isFullItineraryMode = true;

      // Reset swipe workflow
      _currentSwipeStage = 'hotels';
      _acceptedTransport.clear();
      _acceptedAccommodation.clear();
      _acceptedDestinations.clear();
    });
    _scrollToBottom();

    // Start multi-stage swipe workflow: HOTELS FIRST
    try {
      final prefsProvider = context.read<UserPreferencesProvider>();
      final userPrefs = prefsProvider.preferences;

      // Stage 1: Get hotel recommendations from AI
      final hotelResponse = await _pythonADK.searchHotels(
        city: _stayCityController.text,
        maxPrice: userPrefs.budget != null
            ? (userPrefs.budget! * 0.3)
            : 25000, // 30% of budget for accommodation
        roomType: userPrefs.selectedAccommodation.isNotEmpty
            ? userPrefs.selectedAccommodation.first
            : null,
        amenities: ['WiFi', 'Restaurant', 'Pool'],
      );

      print(
          '🏨 [HomeScreen] hotelResponse keys: ${hotelResponse.keys.toList()}');
      print(
          '🏨 [HomeScreen] hotelResponse success: ${hotelResponse['success']}');
      print('🏨 [HomeScreen] hotelResponse data: ${hotelResponse['data']}');
      print(
          '🏨 [HomeScreen] hotelResponse data type: ${hotelResponse['data']?.runtimeType}');
      if (hotelResponse['data'] != null &&
          hotelResponse['data']['hotels'] != null) {
        print(
            '🏨 [HomeScreen] hotels count: ${(hotelResponse['data']['hotels'] as List).length}');
      }

      final List<Hotel> hotelCards = [];
      if (hotelResponse['success'] == true && hotelResponse['data'] != null) {
        final hotels =
            (hotelResponse['data']['hotels'] as List?)?.take(8).toList() ?? [];
        print(
            '🏨 [HomeScreen] Found ${hotels.length} hotels for one-page card board');

        for (final item in hotels) {
          if (item is Map) {
            try {
              hotelCards.add(Hotel.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              print('⚠️ [HomeScreen] Failed to parse hotel card: $e');
            }
          }
        }
      }

      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'triplix',
          'message': hotelCards.isNotEmpty
              ? '🏨 Step 1/3: I opened your hotel recommendations in one page.\n\n'
                  '✅ Keep the hotels you like\n'
                  '🟥 Move not-interested hotels to the red section.'
              : 'I could not find hotels right now. Try adjusting your city or budget.',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });

      if (hotelCards.isNotEmpty) {
        Future.microtask(() {
          if (!mounted) return;
          Get.toNamed('/swipeable-hotels', arguments: {'hotels': hotelCards});
        });
      }
      _scrollToBottom();
    } catch (e) {
      print('❌ [HomeScreen] _processTravelDetails error: $e');
      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'triplix',
          'message':
              'Something went wrong while searching hotels. Please make sure the server is running on port 8001 and try again.\n\nError: $e',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final query = _queryController.text.trim();

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🚀 [HomeScreen] _sendMessage called');
    print('   Query: "$query"');
    print('   Query empty: ${query.isEmpty}');
    print('   Has shown confirmation: $_hasShownConfirmation');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    if (query.isEmpty) {
      print('⚠️ [HomeScreen] Query is empty, returning early');
      return;
    }

    // Add user message
    setState(() {
      _messages.add({
        'sender': 'user',
        'message': query,
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
      _isTyping = true;
    });
    _scrollToBottom();

    _queryController.clear();

    // Check if this is the first interaction and user is asking for itinerary/recommendation
    if (!_hasShownConfirmation && _isItineraryRequest(query)) {
      print(
          'ℹ️ [HomeScreen] First itinerary request detected, showing confirmation dialog');
      setState(() {
        _isFullItineraryMode =
            true; // Enable multi-stage workflow for full itinerary
      });
      await _showConfirmationDialog();
      return;
    }

    // Check if user wants to book (and we have selections to book)
    if (_isBookingRequest(query)) {
      print('📋 [HomeScreen] Booking request detected');
      if (_hasCompletedSwipe()) {
        print('✅ [HomeScreen] User has completed swipe, proceeding to book');
        await _handleBookingRequest();
      } else {
        print('⚠️ [HomeScreen] No selections made yet, guiding user');
        setState(() {
          _isTyping = false;
          _messages.add({
            'sender': 'triplix',
            'message': '📋 I\'d love to help you book!\n\n'
                'To book hotels and flights, I need you to:\n'
                '1. Tell me your travel plans (e.g., "Plan a trip from Delhi to Goa")\n'
                '2. Swipe through and select hotels you like 🏨\n'
                '3. Swipe through and select transport 🚗✈️\n'
                '4. Then I can create your booking!\n\n'
                'Would you like to start planning your trip now?',
            'type': 'text',
            'timestamp': DateTime.now().toString(),
          });
        });
        _scrollToBottom();
      }
      return;
    }

    // For simple queries (not itinerary requests), disable multi-stage workflow
    if (!_isItineraryRequest(query)) {
      setState(() {
        _isFullItineraryMode = false;
      });
    }

    print('✅ [HomeScreen] Proceeding to send query to AI backend...');

    try {
      // Gather user preferences for context-aware AI response
      final prefsProvider = context.read<UserPreferencesProvider>();
      final userPrefs = prefsProvider.preferences;

      // Build rich context for AI agent
      final aiContext = {
        'page': 'home',
        'user_preferences': {
          'budget': userPrefs.budget,
          'destination': userPrefs.destination,
          'from': userPrefs.origin ?? _fromLocationController.text,
          'to': userPrefs.destination ?? _toLocationController.text,
          'stay_city': userPrefs.destination ?? _stayCityController.text,
          'dates': _datesController.text,
          'duration_days':
              userPrefs.checkInDate != null && userPrefs.checkOutDate != null
                  ? userPrefs.checkOutDate!
                          .difference(userPrefs.checkInDate!)
                          .inDays +
                      1
                  : (_startDate != null && _endDate != null
                      ? _endDate!.difference(_startDate!).inDays + 1
                      : null),
          'travelers': userPrefs.numberOfPeople ?? _travelers,
          'activities':
              userPrefs.selectedActivities.toList(), // Convert to list
          'transport': userPrefs.selectedTransport.toList(), // Convert to list
          'accommodation':
              userPrefs.selectedAccommodation.toList(), // Convert to list
          'dietary': userPrefs.selectedDietary.toList(), // Convert to list
          'companion': userPrefs.companion,
          'occasion': userPrefs.occasion,
        },
        'conversation_history': _messages
            .map((msg) => {
                  'role': msg['sender'] == 'user' ? 'user' : 'assistant',
                  'content': msg['message'],
                })
            .toList(),
        'trip_state': {
          'selected_hotels':
              _acceptedAccommodation.map((h) => h['title'] ?? h['id']).toList(),
          'selected_transport':
              _acceptedTransport.map((t) => t['title'] ?? t['id']).toList(),
          'selected_destinations':
              _acceptedDestinations.map((d) => d['title'] ?? d['id']).toList(),
          'has_itinerary': _lastGeneratedItinerary != null,
        },
        'current_itinerary': _lastGeneratedItinerary,
        'current_itinerary_data': _lastGeneratedItineraryData,
        'accepted_suggestions':
            _acceptedSuggestions.toList(), // Convert Set to List
        'rejected_suggestions':
            _rejectedSuggestions.toList(), // Convert Set to List
        'has_shown_confirmation': _hasShownConfirmation,
      };

      // Determine if this is an itinerary generation/update request
      // Only use /api/manager for actual itinerary generation
      final bool isItineraryGenerationRequest =
          _isItineraryGenerationRequest(query);

      // Send to AI Manager Agent with rich context
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print(
          '📤 [HomeScreen] Sending to AI ${isItineraryGenerationRequest ? "Manager (Itinerary)" : "Agent (Chat)"}:');
      print('   Query: "$query"');
      print('   Context keys: ${aiContext.keys.toList()}');
      print('   Has conversation history: ${_messages.length} messages');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Add timeout to prevent infinite waiting
      final response = await (isItineraryGenerationRequest
              ? _pythonADK.sendToManager(
                  message: query,
                  context: aiContext,
                  page: 'home',
                )
              : _pythonADK.sendToAgent(
                  message: query,
                  context: aiContext,
                  page: 'home',
                ))
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏰ [HomeScreen] AI request timed out after 30 seconds');
          return {
            'response':
                'I apologize for the delay. I\'m processing your request. Could you please rephrase or ask something else?',
            'status': 'timeout',
          };
        },
      );

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ [HomeScreen] AI Response received:');
      print('   Response keys: ${response.keys.toList()}');
      print('   Full response: ${response.toString()}');
      print(
          '   Response text length: ${(response['response'] ?? '').toString().length} chars');
      print('   Success flag: ${response['success']}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Handle AI response intelligently
      final responseMessage =
          response['response'] ?? 'I\'m here to help with your travel plans!';

      // Store itinerary if this was a manager response
      if (isItineraryGenerationRequest && responseMessage.length > 200) {
        _lastGeneratedItinerary = responseMessage;
        final itinerary = response['itinerary'];
        if (itinerary is Map<String, dynamic>) {
          final state = itinerary['state'];
          if (state is Map<String, dynamic>) {
            _lastGeneratedItineraryData = state;
          }
        }
      }

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📝 [HomeScreen] Processing response message:');
      print('   Response is null: ${response['response'] == null}');
      print('   Response length: ${responseMessage.length} chars');
      print(
          '   First 200 chars: ${responseMessage.substring(0, responseMessage.length > 200 ? 200 : responseMessage.length)}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Check if AI agent wants to show suggestions
      final suggestions = response['suggestions'] as List<dynamic>?;
      final shouldShowSuggestions =
          response['show_suggestions'] as bool? ?? false;

      setState(() {
        if (shouldShowSuggestions &&
            suggestions != null &&
            suggestions.isNotEmpty) {
          // AI agent wants to show swipeable suggestions
          _messages.add({
            'sender': 'triplix',
            'message': responseMessage,
            'type': 'suggestions',
            'suggestions': suggestions,
            'timestamp': DateTime.now().toString(),
          });
          _currentSuggestions = suggestions.cast<Map<String, dynamic>>();
        } else {
          // Regular text response — attach directions data if present
          final msgData = <String, dynamic>{
            'sender': 'triplix',
            'message': responseMessage,
            'type': 'text',
            'timestamp': DateTime.now().toString(),
          };
          // If backend returned directions data, attach it so we can show "View Route" button
          final dirData = response['data'];
          if (dirData is Map &&
              dirData['origin'] != null &&
              dirData['destination'] != null) {
            msgData['route_origin'] = dirData['origin'];
            msgData['route_destination'] = dirData['destination'];
          }
          // Tag itinerary messages
          if (isItineraryGenerationRequest && responseMessage.length > 200) {
            msgData['is_itinerary'] = true;
          }
          _messages.add(msgData);
        }
        _isTyping = false;
      });
      _scrollToBottom();
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [HomeScreen] Error in _sendMessage:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      setState(() {
        _messages.add({
          'sender': 'triplix',
          'message':
              'I apologize, but I\'m having trouble processing your request. Please try again or rephrase your question.\n\nError details: $e',
          'timestamp': DateTime.now().toString(),
        });
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  bool _isItineraryRequest(String query) {
    final lowerQuery = query.toLowerCase();

    // Full itinerary indicators - these mean user wants complete trip planning
    final fullItineraryKeywords = [
      'full itinerary',
      'complete itinerary',
      'plan my trip',
      'plan my travel',
      'plan a trip',
      'book a trip',
      'organize my trip',
      'create itinerary',
      'multi-day trip',
      'vacation plan',
      'holiday plan',
    ];

    // Check for full itinerary keywords
    for (var keyword in fullItineraryKeywords) {
      if (lowerQuery.contains(keyword)) {
        return true;
      }
    }

    // If user mentions travel dates or duration, it's likely a full itinerary
    if ((lowerQuery.contains('day') || lowerQuery.contains('days')) &&
        (lowerQuery.contains('trip') || lowerQuery.contains('travel'))) {
      return true;
    }

    // Simple suggestions are NOT itinerary requests
    // Examples: "spas in Goa", "best hotels", "restaurants"
    final simpleQuestionIndicators = [
      'what are',
      'show me',
      'suggest',
      'recommend',
      'best',
      'top',
      'good',
      'popular',
      'famous',
    ];

    for (var indicator in simpleQuestionIndicators) {
      if (lowerQuery.startsWith(indicator) ||
          lowerQuery.contains('can you $indicator') ||
          lowerQuery.contains('could you $indicator')) {
        // This is a simple question/suggestion request, not full itinerary
        return false;
      }
    }

    // Default: only trigger itinerary if explicitly asks for planning
    return lowerQuery.contains('plan') && lowerQuery.contains('trip');
  }

  bool _isBookingRequest(String query) {
    final lowerQuery = query.toLowerCase();

    // Booking keywords
    final bookingKeywords = [
      'book',
      'reserve',
      'confirm booking',
      'make a booking',
      'finalize',
      'proceed to book',
      'complete booking',
      'book the',
      'book my',
      'reserve the',
      'reserve my',
    ];

    for (var keyword in bookingKeywords) {
      if (lowerQuery.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  bool _isItineraryGenerationRequest(String query) {
    final lowerQuery = query.toLowerCase();

    // This method determines if the query specifically asks for itinerary GENERATION or MODIFICATION
    // (not just general conversation about travel)

    // Keywords that indicate user wants an itinerary generated
    final itineraryGenerationKeywords = [
      'generate itinerary',
      'create itinerary',
      'make itinerary',
      'show itinerary',
      'show my itinerary',
      'create my plan',
      'generate my plan',
      'finalize itinerary',
      'complete my itinerary',
      'show the plan',
      'what\'s my plan',
      'show plan',
    ];

    for (var keyword in itineraryGenerationKeywords) {
      if (lowerQuery.contains(keyword)) {
        return true;
      }
    }

    // Plan MODIFICATION keywords - route to manager if we have an existing itinerary
    if (_lastGeneratedItinerary != null) {
      final modificationKeywords = [
        'change hotel',
        'swap hotel',
        'replace hotel',
        'different hotel',
        'another hotel',
        'change transport',
        'change flight',
        'change train',
        'swap day',
        'switch day',
        'move day',
        'rearrange',
        'modify itinerary',
        'modify plan',
        'update itinerary',
        'update plan',
        'change plan',
        'edit itinerary',
        'edit plan',
        'add activity',
        'add place',
        'add destination',
        'remove activity',
        'remove place',
        'remove destination',
        'skip',
        'replace',
        'extend trip',
        'shorten trip',
        'add a day',
        'remove a day',
        'change budget',
        'increase budget',
        'decrease budget',
        'more time at',
        'less time at',
        'add restaurant',
        'change restaurant',
        'free day',
        'rest day',
        'make it cheaper',
        'make it luxury',
        'upgrade',
        'downgrade',
        // Dynamic adjustment keywords - handle "extra" requests naturally
        'i also want',
        'i want to',
        'i\'d like to',
        'can we also',
        'can you also',
        'can we add',
        'can you add',
        'include',
        'what about',
        'how about adding',
        'let\'s also',
        'i\'d also like',
        'throw in',
        'squeeze in',
        'fit in',
        'make room for',
        'instead of',
        'rather than',
        'prefer',
        'switch to',
        'move to',
        'cancel',
        'drop',
        'don\'t want',
        'not interested in',
        'too expensive',
        'too cheap',
        'more adventure',
        'more relaxation',
        'more culture',
        'more food',
        'more shopping',
        'more nature',
        'add spa',
        'add scuba',
        'add trek',
        'add temple',
        'add beach',
        'add museum',
        'add market',
        'add nightlife',
        'adjust',
        'tweak',
        'rework',
        'redo',
        'revise',
        'shuffle',
        'reorder',
        'prioritize',
        'focus more on',
        'less of',
        'more of',
        'shift',
        'push back',
        'earlier',
        'later',
        'morning',
        'evening',
        'afternoon',
        'night plan',
        'replan',
        're-plan',
        'weather update',
        'weather changed',
        'bad weather',
        'rain forecast',
        'storm warning',
        'delay',
        'delayed',
        'backup plan',
      ];

      for (var keyword in modificationKeywords) {
        if (lowerQuery.contains(keyword)) {
          return true;
        }
      }
    }

    // If user has completed swipe flow and asks about their selections/plan
    if (_hasCompletedSwipe()) {
      final contextualKeywords = [
        'my selections',
        'what did i select',
        'my choices',
        'combine',
        'put together',
        'organize',
      ];

      for (var keyword in contextualKeywords) {
        if (lowerQuery.contains(keyword)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasCompletedSwipe() {
    // Check if user has made selections in swipe stages
    return _acceptedAccommodation.isNotEmpty ||
        _acceptedTransport.isNotEmpty ||
        _acceptedDestinations.isNotEmpty;
  }

  Future<void> _handleBookingRequest() async {
    setState(() => _isTyping = true);

    try {
      // Check if comparison is needed
      bool needsHotelComparison = _acceptedAccommodation.length > 1;
      bool needsTransportComparison = _acceptedTransport.length > 1;

      if (needsHotelComparison || needsTransportComparison) {
        // Show message about comparison
        setState(() {
          _isTyping = false;
          _messages.add({
            'sender': 'triplix',
            'message': '🔍 I noticed you\'ve selected multiple options!\n\n'
                '${needsHotelComparison ? "✅ Hotels: ${_acceptedAccommodation.length}\n" : ""}'
                '${needsTransportComparison ? "✅ Transport: ${_acceptedTransport.length}\n" : ""}\n'
                'Let me help you compare them so you can decide which one to book! 📊',
            'type': 'text',
            'timestamp': DateTime.now().toString(),
          });
        });
        _scrollToBottom();

        await Future.delayed(const Duration(milliseconds: 800));

        // Show comparison dialog
        if (mounted) {
          final comparisonResult = await _showComparisonDialog(
            needsHotelComparison: needsHotelComparison,
            needsTransportComparison: needsTransportComparison,
          );

          if (comparisonResult == null) {
            // User cancelled
            setState(() {
              _messages.add({
                'sender': 'triplix',
                'message': '👋 Okay, no problem! Take your time to decide.\n\n'
                    'Just let me know when you\'re ready to book!',
                'type': 'text',
                'timestamp': DateTime.now().toString(),
              });
            });
            _scrollToBottom();
            return;
          }
        }
      }

      // Show confirmation message
      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'triplix',
          'message': '✨ Perfect! Let me process your booking...\n\n'
              'Opening booking confirmation page...',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();

      // Navigate to mock booking screen
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MockBookingScreen(
              acceptedHotels: _acceptedAccommodation,
              acceptedTransport: _acceptedTransport,
              acceptedDestinations: _acceptedDestinations,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'triplix',
          'message':
              '❌ Sorry, I encountered an error while preparing your booking.\n\n'
                  'Error: $e\n\n'
                  'Please try again or contact support.',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();
    }
  }

  Future<bool?> _showComparisonDialog({
    required bool needsHotelComparison,
    required bool needsTransportComparison,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppConfig.primaryColor,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.compare_arrows,
                              color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Compare Your Options',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (needsHotelComparison) ...[
                              _buildComparisonSection(
                                title: '🏨 Hotels Comparison',
                                items: _acceptedAccommodation,
                                onSelect: (index) {
                                  setDialogState(() {
                                    // Keep only the selected hotel
                                    final selected =
                                        _acceptedAccommodation[index];
                                    _acceptedAccommodation.clear();
                                    _acceptedAccommodation.add(selected);
                                  });
                                },
                              ),
                              if (needsTransportComparison)
                                const SizedBox(height: 24),
                            ],
                            if (needsTransportComparison) ...[
                              _buildComparisonSection(
                                title: '🚗 Transport Comparison',
                                items: _acceptedTransport,
                                onSelect: (index) {
                                  setDialogState(() {
                                    // Keep only the selected transport
                                    final selected = _acceptedTransport[index];
                                    _acceptedTransport.clear();
                                    _acceptedTransport.add(selected);
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Action buttons
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              // Check if all needed selections are made
                              bool hotelSelectionComplete =
                                  !needsHotelComparison ||
                                      _acceptedAccommodation.length == 1;
                              bool transportSelectionComplete =
                                  !needsTransportComparison ||
                                      _acceptedTransport.length == 1;

                              if (hotelSelectionComplete &&
                                  transportSelectionComplete) {
                                Navigator.of(context).pop(true);
                              }
                            },
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: const Text('Proceed with Selection'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
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
          },
        );
      },
    );
  }

  Widget _buildComparisonSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required Function(int) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConfig.primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Select one option to proceed:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = items.length == 1;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    isSelected ? AppConfig.primaryColor : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: isSelected
                  ? AppConfig.primaryColor.withValues(alpha: 0.05)
                  : Colors.white,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isSelected ? null : () => onSelect(index),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Selection indicator
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppConfig.primaryColor
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                          color: isSelected
                              ? AppConfig.primaryColor
                              : Colors.white,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),

                      // Item details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? AppConfig.primaryColor
                                    : Colors.black87,
                              ),
                            ),
                            if (item['location'] != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on,
                                      size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      item['location'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (item['price'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${item['price']}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                            if (item['description'] != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                item['description'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
        }),
      ],
    );
  }

  Future<void> _showConfirmationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Travel Details Confirmation',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppConfig.primaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'before i recommend you with the itennary, can you please confirm, from and to location for the travel, and the dates, and also, which city are you looking for the stay, or any additional query if you have.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _fromLocationController,
                  decoration: const InputDecoration(
                    labelText: 'From Location',
                    hintText: 'Enter departure city',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _toLocationController,
                  decoration: const InputDecoration(
                    labelText: 'To Location',
                    hintText: 'Enter destination city',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _datesController,
                  decoration: const InputDecoration(
                    labelText: 'Travel Dates',
                    hintText: 'e.g., Dec 15-20, 2025',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stayCityController,
                  decoration: const InputDecoration(
                    labelText: 'Stay City',
                    hintText: 'Which city are you looking for stay?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _additionalQueryController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional Query (Optional)',
                    hintText: 'Any specific preferences or requirements?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isTyping = false;
                });
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _processConfirmedDetails();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm & Get Recommendations'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processConfirmedDetails() async {
    setState(() {
      _hasShownConfirmation = true;
      _messages.add({
        'sender': 'triplix',
        'message':
            'Great! I\'ve noted your travel details. Let me create a personalized itinerary for you.',
        'timestamp': DateTime.now().toString(),
      });
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // Create a comprehensive query with all the confirmed details
      final travelDetails = '''
Travel Details:
- From: ${_fromLocationController.text}
- To: ${_toLocationController.text}
- Dates: ${_datesController.text}
- Stay City: ${_stayCityController.text}
${_additionalQueryController.text.isNotEmpty ? '- Additional: ${_additionalQueryController.text}' : ''}

Please provide a detailed travel itinerary with recommendations for hotels, activities, and transportation.
      '''
          .trim();

      final response = await _pythonADK.sendToManager(
        message: travelDetails,
        context: {
          'from_location': _fromLocationController.text,
          'to_location': _toLocationController.text,
          'dates': _datesController.text,
          'stay_city': _stayCityController.text,
          'additional_query': _additionalQueryController.text,
        },
        page: 'home',
      );

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ [HomeScreen] Itinerary AI Response received:');
      print('   Response keys: ${response.keys.toList()}');
      print('   Full response: ${response.toString()}');
      print(
          '   Response text length: ${(response['response'] ?? '').toString().length} chars');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Process the AI response and extract suggestions
      final aiResponse = response['response'] ?? '';
      if (aiResponse.isNotEmpty) {
        // Add the AI response message
        setState(() {
          _messages.add({
            'sender': 'triplix',
            'message': aiResponse,
            'type': 'text',
            'timestamp': DateTime.now().toString(),
          });
        });
        _scrollToBottom();
      }

      setState(() {
        _messages.add({
          'sender': 'triplix',
          'message':
              'Here are some personalized recommendations for your trip! Swipe right to add them to your itinerary, or left to see alternatives.',
          'type': 'suggestions',
          'suggestions': _generateInitialSuggestions(),
          'timestamp': DateTime.now().toString(),
        });
        _currentSuggestions = _generateInitialSuggestions();
        _isTyping = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'sender': 'triplix',
          'message':
              'Sorry, I\'m having trouble generating your itinerary. Please try again.',
          'timestamp': DateTime.now().toString(),
        });
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppConfig.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const TriplixLogo(
                        size: 24,
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Triplix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // Quick Access: Hotels / Flights / Plan my trip
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: [
                    _buildQuickAccessRow(
                      icon: Icons.hotel,
                      title: 'Hotels',
                      subtitle: 'Find and book stays',
                      color: AppConfig.successColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchHotelsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildQuickAccessRow(
                      icon: Icons.flight,
                      title: 'Flights',
                      subtitle: 'Search and book flights',
                      color: Colors.blue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchFlightsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Replaces the Destination and Travel Mode shortcuts.
                    // Destination duplicated what onboarding already asks, and
                    // Travel Mode offered trains, buses and cabs that Triplix
                    // cannot book. This goes straight to the day-by-day plan,
                    // which is the thing those two were meant to lead toward.
                    _buildQuickAccessRow(
                      icon: Icons.map,
                      title: 'Plan my trip',
                      subtitle: 'See your day-by-day itinerary',
                      color: AppConfig.primaryColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TripPlanScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Chat Messages
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppConfig.paddingMedium),
                    child: Column(
                      children: [
                        ..._messages.map((message) {
                          final isTriplix = message['sender'] == 'triplix';
                          return _buildMessageBubble(message, isTriplix);
                        }),
                        if (_isTyping) _buildTypingIndicator(),
                      ],
                    ),
                  ),
                ),
              ),

              // Input Area
              Container(
                padding: const EdgeInsets.all(AppConfig.paddingMedium),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    // Voice Input Button
                    VoiceInputButton(
                      onTranscript: (transcript) {
                        if (transcript.isEmpty) return;
                        setState(() {
                          _queryController.value =
                              TextEditingValue(text: transcript);
                          _queryController.text = transcript;
                          _rebuildCounter++;
                          _forceRebuild = !_forceRebuild;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _queryFocusNode.requestFocus();
                        });
                      },
                      size: 28,
                      color: AppConfig.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: ValueKey('query_input_$_rebuildCounter'),
                        controller: _queryController,
                        focusNode: _queryFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Ask me about your travel plans...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppConfig.primaryGradient,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: IconButton(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send, color: Colors.white),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppConfig.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppConfig.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // MakeMyTrip-Style Trip Search Form
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildTripSearchForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Form Fields ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              children: [
                // From → To Row
                Row(
                  children: [
                    // FROM
                    Expanded(
                      child: _buildFormField(
                        controller: _fromLocationController,
                        label: 'FROM',
                        hint: 'City',
                        icon: Icons.flight_takeoff,
                        iconColor: AppConfig.successColor,
                        focusNode: _fromFocusNode,
                        onTap: () => _updateFromSuggestions(
                            _fromLocationController.text),
                        onChanged: _updateFromSuggestions,
                      ),
                    ),
                    // Swap button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            final temp = _fromLocationController.text;
                            _fromLocationController.text =
                                _toLocationController.text;
                            _toLocationController.text = temp;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color:
                                AppConfig.primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.swap_horiz,
                              size: 18, color: AppConfig.primaryColor),
                        ),
                      ),
                    ),
                    // TO
                    Expanded(
                      child: _buildFormField(
                        controller: _toLocationController,
                        label: 'TO',
                        hint: 'City',
                        icon: Icons.flight_land,
                        iconColor: AppConfig.errorColor,
                      ),
                    ),
                  ],
                ),
                if (_showFromSuggestions && _fromSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppConfig.borderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: _fromSuggestions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final suggestion = entry.value;
                        final city = suggestion['city'] ?? '';
                        final country = suggestion['country'] ?? '';
                        final description = suggestion['description'] ?? '';
                        final locationLabel = _formatLocationLabel(
                          city: city,
                          country: country,
                          description: description,
                        );

                        return InkWell(
                          onTap: () => _selectFromSuggestion(suggestion),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: index == _fromSuggestions.length - 1
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                        color: Colors.grey[200]!,
                                      ),
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
                                    locationLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppConfig.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Date + Stay Row
                Row(
                  children: [
                    // DATE
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final dateRange = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            initialDateRange:
                                _startDate != null && _endDate != null
                                    ? DateTimeRange(
                                        start: _startDate!, end: _endDate!)
                                    : null,
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
                          if (dateRange != null) {
                            setState(() {
                              _startDate = dateRange.start;
                              _endDate = dateRange.end;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppConfig.borderColor),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 16, color: AppConfig.primaryColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('DATES',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: AppConfig.textSecondary,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _startDate == null
                                          ? 'Select Dates'
                                          : '${_startDate!.day}/${_startDate!.month} - ${_endDate!.day}/${_endDate!.month}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _startDate == null
                                            ? AppConfig.textTertiary
                                            : AppConfig.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // TRAVELERS & ROOMS
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showTravelersBottomSheet(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppConfig.borderColor),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person,
                                  size: 16, color: AppConfig.primaryColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('TRAVELERS & ROOMS',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: AppConfig.textSecondary,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$_travelers Traveler${_travelers > 1 ? 's' : ''}, $_rooms Room${_rooms > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppConfig.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // SEARCH Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _onSearchPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flight_takeoff, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'START ITINERARY',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    Color? iconColor,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppConfig.borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppConfig.primaryColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppConfig.textSecondary,
                        fontWeight: FontWeight.w600)),
                SizedBox(
                  height: 22,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onTap: onTap,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppConfig.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: AppConfig.textTertiary,
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

  void _showTravelersBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Travelers & Rooms',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _buildCounterRow(
                    'Travelers',
                    _travelers,
                    (val) {
                      setSheetState(() => _travelers = val);
                      setState(() {});
                    },
                    min: 1,
                    max: 9,
                  ),
                  const SizedBox(height: 12),
                  _buildCounterRow(
                    'Rooms',
                    _rooms,
                    (val) {
                      setSheetState(() => _rooms = val);
                      setState(() {});
                    },
                    min: 1,
                    max: 5,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Done', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCounterRow(String label, int value, ValueChanged<int> onChanged,
      {int min = 0, int max = 10}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Row(
          children: [
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: AppConfig.primaryColor,
            ),
            SizedBox(
              width: 30,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
              color: AppConfig.primaryColor,
            ),
          ],
        ),
      ],
    );
  }

  void _onSearchPressed() {
    final from = _fromLocationController.text.trim();
    final to = _toLocationController.text.trim();

    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter From and To cities'),
          backgroundColor: AppConfig.errorColor,
        ),
      );
      return;
    }

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your travel dates'),
          backgroundColor: AppConfig.errorColor,
        ),
      );
      return;
    }

    // Auto-fill accommodation city as destination
    if (_stayCityController.text.trim().isEmpty) {
      _stayCityController.text = to;
    }

    // Collapse the form
    setState(() {
      _showTripForm = false;
    });

    // Process travel details (same as before)
    _processTravelDetails();
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isTriplix) {
    final messageType = message['type'] ?? 'text';

    if (messageType == 'suggestions') {
      return _buildSuggestionsMessage(message, isTriplix);
    }

    if (messageType == 'comparison') {
      return _buildComparisonMessage(message, isTriplix);
    }

    if (messageType == 'replacement_prompt') {
      return _buildReplacementPromptMessage(message, isTriplix);
    }

    return Align(
      alignment: isTriplix ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        child: isTriplix
            ? _buildTriplixMessage(message)
            : _buildUserMessage(message),
      ),
    );
  }

  Widget _buildTriplixMessage(Map<String, dynamic> message) {
    final messageText = message['message'] ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConfig.primaryColor.withValues(alpha: 0.15),
            AppConfig.primaryColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: AppConfig.primaryColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Prevent overflow
        children: [
          // Header with AI icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppConfig.primaryColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TriplixLogo(
                  size: 16,
                  padding: EdgeInsets.all(4),
                  backgroundColor: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                SizedBox(width: 8),
                Text(
                  'Triplix AI',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppConfig.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          // Message content with enhanced formatting
          Padding(
            padding: const EdgeInsets.all(16),
            child: _formatAIMessage(messageText),
          ),
          // Show "View Route on Map" button if this message has directions data
          if (message['route_origin'] != null &&
              message['route_destination'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RouteMapScreen(
                          origin: message['route_origin'],
                          destination: message['route_destination'],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('View Route on Map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConfig.primaryColor,
                    side: const BorderSide(color: AppConfig.primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          // Show "Share Trip QR" button for itinerary messages
          if (message['is_itinerary'] == true)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _openItineraryTimeline(message['message'] ?? ''),
                      icon: const Icon(Icons.timeline, size: 18),
                      label: const Text('View Itinerary Timeline'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConfig.primaryColor,
                        side: const BorderSide(color: AppConfig.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showQRShareDialog(message['message'] ?? ''),
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('Share Trip QR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppConfig.primaryColor,
                            side:
                                const BorderSide(color: AppConfig.primaryColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _shareItineraryText(message['message'] ?? ''),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Share Text'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppConfig.accentColor,
                            side:
                                const BorderSide(color: AppConfig.accentColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserMessage(Map<String, dynamic> message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConfig.primaryColor,
            AppConfig.primaryColor.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: AppConfig.primaryColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message['message'] ?? '',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _formatAIMessage(String text) {
    // Remove excessive markdown asterisks and clean up formatting
    String cleanedText = text
        .replaceAll('**', '') // Remove bold markdown
        .replaceAll('__', '') // Remove alternative bold markdown
        .replaceAll('###', '') // Remove h3 headers
        .replaceAll('##', '') // Remove h2 headers
        .replaceAll('#', ''); // Remove h1 headers

    // Split message into sections for better formatting
    final lines = cleanedText.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Check for emoji headers (lines starting with emoji)
      final emojiMatch = RegExp(
              r'^([\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}])\s*(.+)',
              unicode: true)
          .firstMatch(line);
      if (emojiMatch != null && line.length < 80) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppConfig.primaryColor.withValues(alpha: 0.1),
                    AppConfig.primaryColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                  left: BorderSide(
                    color: AppConfig.primaryColor,
                    width: 4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    emojiMatch.group(1)!,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      emojiMatch.group(2)!.trim(),
                      style: const TextStyle(
                        color: AppConfig.primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      // Check for bullet points or numbered lists
      else if (line.startsWith('•') ||
          line.startsWith('-') ||
          RegExp(r'^\d+[\.)]\s').hasMatch(line)) {
        final content = line.replaceFirst(RegExp(r'^[•\-\d+[\.)]\s]+'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, right: 12),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppConfig.primaryColor,
                        AppConfig.primaryColor.withValues(alpha: 0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppConfig.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      height: 1.6,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Check for headers (lines ending with :)
      else if (line.endsWith(':') && line.length < 60) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: AppConfig.primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Check for price/cost lines (contains ₹ or Rs.)
      else if (line.contains('₹') ||
          line.contains('Rs.') ||
          line.toLowerCase().contains('cost') ||
          line.toLowerCase().contains('price')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 18,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      // Regular text with improved styling
      else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // Prevent overflow by sizing to content
      children: widgets.isNotEmpty
          ? widgets
          : [
              Text(
                text,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
    );
  }

  Widget _buildSuggestionsMessage(
      Map<String, dynamic> message, bool isTriplix) {
    final dynamic rawSuggestions = message['suggestions'];
    if (rawSuggestions == null || rawSuggestions is! List) {
      return _buildMessageBubble({
        'sender': message['sender'],
        'message': message['message'] ?? 'No suggestions available',
        'type': 'text',
        'timestamp': message['timestamp'],
      }, isTriplix);
    }

    final List<Map<String, dynamic>> suggestions = [];
    for (final item in rawSuggestions) {
      if (item is Map<String, dynamic>) {
        suggestions.add(item);
      }
    }

    if (suggestions.isEmpty) {
      return _buildMessageBubble({
        'sender': message['sender'],
        'message': message['message'] ?? 'No suggestions available',
        'type': 'text',
        'timestamp': message['timestamp'],
      }, isTriplix);
    }

    // Show message with a button to open overlay
    return Align(
      alignment: isTriplix ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppConfig.primaryColor.withValues(alpha: 0.15),
              AppConfig.primaryColor.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(24),
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: AppConfig.primaryColor.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppConfig.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Personalized Recommendations',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppConfig.primaryColor,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppConfig.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${suggestions.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message['message'] != null &&
                      message['message'].toString().isNotEmpty)
                    Text(
                      message['message'],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Preview cards
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          suggestions.length > 3 ? 3 : suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        final type = suggestion['type'] ?? 'general';
                        return Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _getTypeColor(type).withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getTypeIcon(type),
                                    size: 16,
                                    color: _getTypeColor(type),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _getTypeLabel(type),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _getTypeColor(type),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                suggestion['title'] ?? 'Suggestion',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (suggestions.length > 3) ...[
                    const SizedBox(height: 8),
                    Text(
                      '+${suggestions.length - 3} more suggestions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Swipe button with animation
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppConfig.primaryColor,
                          AppConfig.primaryColor.withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppConfig.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _showSuggestionsOverlay(suggestions),
                      icon: const Icon(Icons.swipe_right, size: 22),
                      label: const Text(
                        'Start Swiping',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

  Widget _buildComparisonMessage(Map<String, dynamic> message, bool isTriplix) {
    final options = message['options'] as List<dynamic>? ?? [];
    final analysis = message['analysis'] ?? '';
    final comparisonType = message['comparison_type'] ?? 'option';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        decoration: BoxDecoration(
          color: AppConfig.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppConfig.primaryColor.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                const Icon(Icons.compare_arrows,
                    color: AppConfig.primaryColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compare ${comparisonType == 'transport' ? 'Transport Options' : 'Accommodation Options'}',
                    style: const TextStyle(
                      color: AppConfig.primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // AI Analysis
            if (analysis.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  analysis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Option Cards
            ...options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value as Map<String, dynamic>;
              return Container(
                margin: EdgeInsets.only(
                    bottom: index < options.length - 1 ? 12 : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppConfig.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Option Header
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppConfig.primaryColor,
                          radius: 14,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            option['name'] ??
                                option['airline'] ??
                                option['hotel_name'] ??
                                'Option ${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Option Details
                    if (option['price'] != null)
                      Text('Price: ${option['price']}',
                          style: const TextStyle(fontSize: 14)),
                    if (option['duration'] != null)
                      Text('Duration: ${option['duration']}',
                          style: const TextStyle(fontSize: 14)),
                    if (option['rating'] != null)
                      Text('Rating: ${option['rating']} ⭐',
                          style: const TextStyle(fontSize: 14)),

                    const SizedBox(height: 12),

                    // Confirm Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            _confirmSelection(comparisonType, option),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Confirm This Option',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildReplacementPromptMessage(
      Map<String, dynamic> message, bool isTriplix) {
    final removedItem = message['removed_item'] as Map<String, dynamic>? ?? {};
    final itemName =
        removedItem['name'] ?? removedItem['destination'] ?? 'this item';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon and title
            Row(
              children: [
                Icon(Icons.help_outline,
                    color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Replacement Needed?',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              message['message'] ??
                  'You removed "$itemName". Would you like me to suggest a replacement?',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Yes/No Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _handleReplacementResponse(true, removedItem),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Yes, Please',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _handleReplacementResponse(false, removedItem),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('No, Thanks',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestionsOverlay(List<Map<String, dynamic>> suggestions) {
    // Store current suggestions for swipe handler
    _currentSuggestions = suggestions;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
              maxWidth: 500,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Swipe to Choose',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                // Swipeable cards
                Flexible(
                  child: Container(
                    height: 460,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CardSwiper(
                      controller: _cardController,
                      cardsCount: suggestions.length,
                      onSwipe: (previousIndex, currentIndex, direction) {
                        final result = _handleSuggestionSwipe(
                            previousIndex, currentIndex, direction);
                        // DON'T auto-close - let user close manually
                        // User can click X button or press back to close
                        return result;
                      },
                      numberOfCardsDisplayed: suggestions.length > 1 ? 2 : 1,
                      backCardOffset: const Offset(15, 15),
                      padding: const EdgeInsets.all(8),
                      cardBuilder: (context,
                          index,
                          horizontalThresholdPercentage,
                          verticalThresholdPercentage) {
                        if (index < 0 || index >= suggestions.length) {
                          return const SizedBox.shrink();
                        }
                        final suggestion = suggestions[index];
                        return _buildSuggestionCard(suggestion, index);
                      },
                    ),
                  ),
                ),
                // Action buttons with Finish button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Swipe instruction text
                      Text(
                        'Swipe left to skip, right to like',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Swipe buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FloatingActionButton(
                            onPressed: () =>
                                _cardController.swipe(CardSwiperDirection.left),
                            backgroundColor: Colors.red,
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                          ),
                          FloatingActionButton(
                            onPressed: () => _cardController
                                .swipe(CardSwiperDirection.right),
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.favorite,
                                color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Finish button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _finishCurrentStage(),
                          icon: const Icon(Icons.check_circle,
                              color: Colors.white),
                          label: Text(
                            _getFinishButtonText(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
      },
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> suggestion, int index) {
    final type = (suggestion['type'] as String?) ?? 'general';
    final title = (suggestion['title'] as String?) ?? 'Suggestion';
    final description = (suggestion['description'] as String?) ?? '';
    final price = suggestion['price'];
    final rating = suggestion['rating'];
    final location = suggestion['location'] ?? suggestion['address'];
    final openingHours = suggestion['opening_hours'] ?? suggestion['hours'];
    final amenities = suggestion['amenities'];
    final highlights = suggestion['highlights'];
    final imageUrl =
        suggestion['image'] ?? suggestion['image_url'] ?? suggestion['photo'];

    return Card(
      elevation: 12,
      shadowColor: _getTypeColor(type).withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        height: 460,
        width: 420,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced header with REAL IMAGE or gradient fallback
            Stack(
              children: [
                // Image or gradient background
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    gradient: imageUrl == null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _getTypeColor(type).withValues(alpha: 0.85),
                              _getTypeColor(type).withValues(alpha: 0.65),
                            ],
                          )
                        : null,
                  ),
                  child: imageUrl != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // The actual image
                              Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  // Fallback to gradient if image fails to load
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _getTypeColor(type)
                                              .withValues(alpha: 0.85),
                                          _getTypeColor(type)
                                              .withValues(alpha: 0.65),
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _getTypeIcon(type),
                                        size: 50, // Reduced from 60
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  );
                                },
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: _getTypeColor(type)
                                        .withValues(alpha: 0.1),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: _getTypeColor(type),
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Dark overlay for better text readability
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.3),
                                      Colors.black.withValues(alpha: 0.1),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Icon(
                            _getTypeIcon(type),
                            size: 50, // Reduced from 60
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                ),
                // Type badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTypeIcon(type),
                          color: _getTypeColor(type),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(type),
                          style: TextStyle(
                            color: _getTypeColor(type),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Rating badge
                if (rating != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 14, // Reduced from 16
                          ),
                          const SizedBox(width: 3), // Reduced from 4
                          Text(
                            rating.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11, // Reduced from 13
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Key info visible without scrolling, rest scrollable
            // Title + location + price row (always visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Location row
                  if (location != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location.toString(),
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Price row
                  if (price != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      price is num ? '₹${price.toStringAsFixed(0)}' : '₹$price',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getTypeColor(type),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable details section
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Location with icon (REMOVED — shown above now)

                          const SizedBox(height: 6),

                          // Description
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),

                          // Category & Best Time badges
                          if (suggestion['category'] != null ||
                              suggestion['best_time'] != null ||
                              suggestion['seasonal_rating'] != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (suggestion['category'] != null)
                                  _buildActivityBadge(
                                    _getCategoryIcon(suggestion['category']),
                                    suggestion['category']
                                        .toString()
                                        .toUpperCase(),
                                    _getCategoryColor(suggestion['category']),
                                  ),
                                if (suggestion['best_time'] != null)
                                  _buildActivityBadge(
                                    Icons.schedule,
                                    suggestion['best_time']
                                        .toString()
                                        .toUpperCase(),
                                    Colors.blueGrey,
                                  ),
                                if (suggestion['seasonal_rating'] != null)
                                  _buildActivityBadge(
                                    Icons.thumb_up,
                                    '⭐' *
                                        (suggestion['seasonal_rating']
                                                as int? ??
                                            3),
                                    Colors.amber.shade700,
                                  ),
                              ],
                            ),
                          ],

                          // Highlights/Amenities tags
                          if (highlights != null || amenities != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children:
                                  _buildFeatureTags(highlights ?? amenities),
                            ),
                          ],

                          // Opening hours
                          if (openingHours != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    openingHours.toString(),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Hotel/Transport specific details only
                          if (type == 'hotel' || type == 'transport')
                            _buildAdditionalDetails(suggestion, type),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // Maps button - Now part of scrollable content
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4), // Reduced from 6
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top:
                              BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final locationText = location ?? title;
                            final query =
                                Uri.encodeComponent('$title $locationText');
                            final url =
                                'https://www.google.com/maps/search/?api=1&query=$query';
                            final uri = Uri.parse(url);

                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            } catch (e) {
                              print('Error launching maps: $e');
                            }
                          },
                          icon: const Icon(Icons.map, size: 16),
                          label: const Text(
                            'View on Google Maps',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1976D2),
                            side: const BorderSide(
                                color: Color(0xFF1976D2), width: 1.5),
                            padding: const EdgeInsets.symmetric(
                                vertical: 6), // Reduced from 8
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Price already shown in the fixed header above
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeatureTags(dynamic features) {
    if (features == null) return [];

    List<String> featureList;
    if (features is List) {
      featureList =
          features.map((e) => e.toString()).take(4).toList(); // Limit to 4
    } else if (features is String) {
      featureList = features.split(',').take(4).toList();
    } else {
      return [];
    }

    return featureList.map((feature) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppConfig.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          feature.trim(),
          style: const TextStyle(
            fontSize: 10,
            color: AppConfig.primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAdditionalDetails(Map<String, dynamic> suggestion, String type) {
    // Extract type-specific details
    final details = suggestion['details'] as Map<String, dynamic>?;

    if (details == null) return const SizedBox.shrink();

    List<Widget> detailWidgets = [];

    // Hotel-specific details
    if (type == 'hotel' || type == 'accommodation') {
      if (details['check_in'] != null || details['check_out'] != null) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.access_time,
            'Check-in: ${details['check_in'] ?? 'N/A'} | Check-out: ${details['check_out'] ?? 'N/A'}',
          ),
        );
      }
      if (details['room_type'] != null) {
        detailWidgets.add(
          _buildDetailRow(Icons.bed, 'Room: ${details['room_type']}'),
        );
      }
    }

    // Transport-specific details
    if (type == 'transport') {
      if (details['departure'] != null || details['arrival'] != null) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.schedule,
            'Depart: ${details['departure'] ?? 'N/A'} → Arrive: ${details['arrival'] ?? 'N/A'}',
          ),
        );
      }
      if (details['duration'] != null) {
        detailWidgets.add(
          _buildDetailRow(Icons.timer, 'Duration: ${details['duration']}'),
        );
      }
    }

    // Destination-specific details
    if (type == 'destination' || type == 'activity') {
      // Handle the details map from destination recommendations
      if (details['Location Type'] != null &&
          details['Location Type'].toString().isNotEmpty) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.location_city,
            'Type: ${details['Location Type']}',
          ),
        );
      }
      if (details['Travel Style'] != null &&
          details['Travel Style'].toString().isNotEmpty) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.style,
            'Style: ${details['Travel Style']}',
          ),
        );
      }
      if (details['Best Season'] != null &&
          details['Best Season'].toString().isNotEmpty) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.wb_sunny,
            'Best: ${details['Best Season']}',
          ),
        );
      }
      if (details['Cuisine'] != null &&
          details['Cuisine'].toString().isNotEmpty) {
        detailWidgets.add(
          _buildDetailRow(
            Icons.restaurant,
            'Food: ${details['Cuisine']}',
          ),
        );
      }
    }

    // If no specific details, show generic ones
    if (detailWidgets.isEmpty) {
      if (suggestion['category'] != null) {
        detailWidgets.add(
          _buildDetailRow(
              Icons.category, 'Category: ${suggestion['category']}'),
        );
      }
      if (suggestion['subcategory'] != null) {
        detailWidgets.add(
          _buildDetailRow(Icons.info_outline, '${suggestion['subcategory']}'),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: detailWidgets.take(2).toList(), // Limit to 2 lines
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'monument':
        return Icons.account_balance;
      case 'nature':
        return Icons.park;
      case 'food':
        return Icons.restaurant;
      case 'adventure':
        return Icons.terrain;
      case 'cultural':
        return Icons.theater_comedy;
      case 'shopping':
        return Icons.shopping_bag;
      case 'nightlife':
        return Icons.nightlife;
      case 'spiritual':
        return Icons.temple_hindu;
      case 'photography':
        return Icons.camera_alt;
      default:
        return Icons.place;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'monument':
        return Colors.brown;
      case 'nature':
        return Colors.green;
      case 'food':
        return Colors.orange;
      case 'adventure':
        return Colors.red;
      case 'cultural':
        return Colors.purple;
      case 'shopping':
        return Colors.pink;
      case 'nightlife':
        return Colors.indigo;
      case 'spiritual':
        return Colors.amber.shade800;
      case 'photography':
        return Colors.teal;
      default:
        return AppConfig.primaryColor;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'hotel':
        return Colors.blue;
      case 'activity':
        return Colors.green;
      case 'restaurant':
        return Colors.orange;
      case 'transport':
        return Colors.purple;
      default:
        return AppConfig.primaryColor;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'hotel':
        return Icons.hotel;
      case 'activity':
        return Icons.local_activity;
      case 'restaurant':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_car;
      default:
        return Icons.place;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'hotel':
        return 'HOTEL';
      case 'activity':
        return 'ACTIVITY';
      case 'restaurant':
        return 'RESTAURANT';
      case 'transport':
        return 'TRANSPORT';
      default:
        return 'SUGGESTION';
    }
  }

  bool _handleSuggestionSwipe(
      int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_currentSuggestions.isEmpty ||
        previousIndex >= _currentSuggestions.length) {
      return true;
    }

    final suggestion = _currentSuggestions[previousIndex];

    if (direction == CardSwiperDirection.right) {
      // Swiped right - add to stage-specific collection
      _acceptedSuggestions.add(suggestion['id'] ?? suggestion['title'] ?? '');
      _showSwipeFeedback('Added! ❤️', Colors.green);

      // Only proceed with multi-stage workflow if in full itinerary mode
      if (_isFullItineraryMode) {
        // Add to appropriate stage collection based on NEW order: hotels → transport → destinations
        if (_currentSwipeStage == 'hotels') {
          _acceptedAccommodation.add(suggestion);

          // Allow user to select 1-3 hotels
          // Auto-proceed only when:
          // 1. User selected 3 hotels (max reached), OR
          // 2. User reached the last card (ran out of options)
          if (_acceptedAccommodation.length >= 3) {
            // Max hotels selected, auto-advance
            Future.delayed(const Duration(milliseconds: 800), () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              _proceedToTransportStage();
            });
          } else if (currentIndex == null ||
              currentIndex >= _currentSuggestions.length - 1) {
            // Reached last card, proceed with whatever they selected (1-2 hotels)
            if (_acceptedAccommodation.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 800), () {
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                _proceedToTransportStage();
              });
            }
          }
        } else if (_currentSwipeStage == 'transport') {
          _acceptedTransport.add(suggestion);

          // Allow user to select 1-2 transport options
          // Auto-proceed when:
          // 1. User selected 2 transport (max for comparison), OR
          // 2. User reached the last card
          if (_acceptedTransport.length >= 2) {
            // Max transport selected, auto-advance
            Future.delayed(const Duration(milliseconds: 800), () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              _proceedToDestinationsStage();
            });
          } else if (currentIndex == null ||
              currentIndex >= _currentSuggestions.length - 1) {
            // Reached last card, proceed with whatever they selected (1 transport)
            if (_acceptedTransport.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 800), () {
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                _proceedToDestinationsStage();
              });
            }
          }
        } else if (_currentSwipeStage == 'destinations') {
          _acceptedDestinations.add(suggestion);

          // Allow unlimited destinations until user runs out of cards
          // Generate itinerary when user reaches the last card
          if (currentIndex == null ||
              currentIndex >= _currentSuggestions.length - 1) {
            // Minimum 2 destinations required for a proper trip
            if (_acceptedDestinations.length >= 2) {
              Future.delayed(const Duration(milliseconds: 800), () {
                _generateFinalItinerary();
              });
            } else {
              // Show message to select at least 2 destinations
              _showSwipeFeedback(
                  'Select at least 2 destinations!', Colors.orange);
            }
          }
        }
      }
    } else {
      // Swiped left - rejected
      _rejectedSuggestions.add(suggestion['id'] ?? suggestion['title'] ?? '');
      _showSwipeFeedback('Skipped 👎', Colors.red);
    }

    return true;
  }

  // Stage 2: Proceed to Transport selection
  Future<void> _proceedToTransportStage() async {
    // Note: dialog is already closed by _finishCurrentStage or auto-swipe handler

    // Parse and update transport preferences from user's messages
    _parseAndUpdateTransportPreferences();

    setState(() {
      _currentSwipeStage = 'transport';
      _isTyping = true;
      _messages.add({
        'sender': 'triplix',
        'message':
            '✅ Awesome! You\'ve selected ${_acceptedAccommodation.length} hotel(s)!\n\n'
                '🚗 Step 2/3: Now let\'s choose your transport\n\n'
                '👉 Swipe RIGHT on up to 2 transport options (for comparison)\n'
                '👈 Swipe LEFT to skip\n'
                '💡 Selecting 2 helps you compare and choose the best!',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
    });
    _scrollToBottom();

    // Generate transport suggestions from AI
    setState(() => _isTyping = true);
    final transportOptions = await _generateTransportSuggestions();

    setState(() {
      _isTyping = false;
      _messages.add({
        'sender': 'triplix',
        'message': 'Swipe through these transport options:',
        'type': 'suggestions',
        'suggestions': transportOptions,
        'timestamp': DateTime.now().toString(),
      });
      _currentSuggestions = transportOptions;
    });
    _scrollToBottom();
  }

  // Parse user messages to extract and update transport preferences
  void _parseAndUpdateTransportPreferences() {
    final prefsProvider = context.read<UserPreferencesProvider>();

    // Combine all user messages and additional query
    final allUserText =
        '${_messages.where((msg) => msg['sender'] == 'user').map((msg) => msg['message'].toString().toLowerCase()).join(' ')} ${_additionalQueryController.text.toLowerCase()} ${_queryController.text.toLowerCase()}';

    print('🔍 Parsing transport preferences from: "$allUserText"');

    List<String> detectedTransport = [];

    // Check for flight/air preferences
    if (allUserText.contains('flight') ||
        allUserText.contains('fly') ||
        allUserText.contains('air') ||
        allUserText.contains('plane') ||
        allUserText.contains('airplane')) {
      detectedTransport.add('air');
      print('✈️ Detected: Flight preference');
    }

    // Check for train preferences
    if (allUserText.contains('train') ||
        allUserText.contains('rail') ||
        allUserText.contains('railway') ||
        allUserText.contains('rajdhani') ||
        allUserText.contains('shatabdi') ||
        allUserText.contains('express') ||
        allUserText.contains('vande bharat')) {
      detectedTransport.add('train');
      print('🚂 Detected: Train preference');
    }

    // Check for road/bus preferences
    if (allUserText.contains('bus') ||
        allUserText.contains('road') ||
        allUserText.contains('car') ||
        allUserText.contains('drive') ||
        allUserText.contains('taxi') ||
        allUserText.contains('volvo') ||
        allUserText.contains('coach')) {
      detectedTransport.add('road');
      print('🚌 Detected: Road/Bus preference');
    }

    // Update preferences if any transport was detected
    if (detectedTransport.isNotEmpty) {
      print('✅ Updating transport preferences to: $detectedTransport');
      prefsProvider.updateTransport(detectedTransport);
    } else {
      print(
          'ℹ️ No specific transport preferences detected, showing all options');
    }
  }

  // Stage 3: Proceed to Destinations selection
  Future<void> _proceedToDestinationsStage() async {
    // Note: dialog is already closed by _finishCurrentStage or auto-swipe handler

    setState(() {
      _currentSwipeStage = 'destinations';
      _isTyping = true;
      _messages.add({
        'sender': 'triplix',
        'message':
            '✅ Perfect! You\'ve selected ${_acceptedTransport.length} transport option(s)!\n\n'
                '📍 Step 3/3: Finally, let\'s pick your destinations\n\n'
                '👉 Swipe RIGHT on places you want to visit (select multiple!)\n'
                '👈 Swipe LEFT to skip\n'
                '⚠️ Minimum 2 destinations required for itinerary',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
    });
    _scrollToBottom();

    // Fetch seasonal activities from AI
    final destinationOptions = await _fetchSeasonalActivities();

    setState(() {
      _isTyping = false;
      _messages.add({
        'sender': 'triplix',
        'message': 'Swipe through these amazing destinations:',
        'type': 'suggestions',
        'suggestions': destinationOptions,
        'timestamp': DateTime.now().toString(),
      });
      _currentSuggestions = destinationOptions;
    });
    _scrollToBottom();
  }

  // Stage 4: Generate Final Itinerary based on all swipes
  Future<void> _generateFinalItinerary() async {
    // Close the swipe overlay
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    setState(() {
      _isTyping = true;
      _messages.add({
        'sender': 'triplix',
        'message': '🎉 Awesome! You\'ve completed all selections!\n\n'
            '📋 Hotels: ${_acceptedAccommodation.length}\n'
            '🚗 Transport: ${_acceptedTransport.length}\n'
            '📍 Destinations: ${_acceptedDestinations.length}\n\n'
            'Let me create your personalized itinerary using AI...',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
    });
    _scrollToBottom();

    try {
      final prefsProvider = context.read<UserPreferencesProvider>();
      final userPrefs = prefsProvider.preferences;
      final days = _endDate!.difference(_startDate!).inDays + 1;

      // Call AI to generate complete itinerary
      final itineraryResponse = await _pythonADK.sendToManager(
        message:
            'Create a detailed $days-day itinerary from ${_fromLocationController.text} to ${_toLocationController.text}',
        context: {
          'from': _fromLocationController.text,
          'to': _toLocationController.text,
          'stay_city': _stayCityController.text,
          'start_date': _startDate!.toIso8601String(),
          'end_date': _endDate!.toIso8601String(),
          'duration_days': days,
          'budget': userPrefs.budget ?? 0,
          'travelers': userPrefs.numberOfPeople ?? 1,
          'selected_hotels':
              _acceptedAccommodation.map((h) => h['title']).toList(),
          'selected_transport':
              _acceptedTransport.map((t) => t['title']).toList(),
          'selected_destinations':
              _acceptedDestinations.map((d) => d['title']).toList(),
          'preferences': {
            'activities': userPrefs.selectedActivities,
            'dietary': userPrefs.selectedDietary,
            'accommodation': userPrefs.selectedAccommodation,
          },
        },
        page: 'home',
      );

      setState(() {
        _isTyping = false;
        final itineraryText = itineraryResponse['response'] ??
            'Here is your personalized itinerary!';
        _lastGeneratedItinerary = itineraryText;
        final itinerary = itineraryResponse['itinerary'];
        if (itinerary is Map<String, dynamic>) {
          final state = itinerary['state'];
          if (state is Map<String, dynamic>) {
            _lastGeneratedItineraryData = state;
          }
        }
        _messages.add({
          'sender': 'triplix',
          'message': itineraryText,
          'type': 'text',
          'is_itinerary': true,
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'triplix',
          'message':
              'I\'ve noted all your preferences! Your itinerary is ready to be finalized.',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();
    }
  }

  // ─── QR Trip Share ───
  void _showQRShareDialog(String itineraryText) {
    // Build a compact trip summary for QR (QR has data limits)
    final from = _fromLocationController.text;
    final to = _toLocationController.text;
    final startDate = _startDate != null
        ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
        : '';
    final endDate = _endDate != null
        ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
        : '';
    final days = (_startDate != null && _endDate != null)
        ? _endDate!.difference(_startDate!).inDays + 1
        : 0;

    // Compact QR data (keep under ~2000 chars for reliable scanning)
    final qrData = 'TRIPLIX ITINERARY\n'
        '━━━━━━━━━━━━━━━\n'
        '📍 $from → $to\n'
        '📅 $startDate - $endDate ($days days)\n'
        '👥 $_travelers travelers\n'
        '🏨 Hotels: ${_acceptedAccommodation.map((h) => h['title']).join(', ')}\n'
        '🚗 Transport: ${_acceptedTransport.map((t) => t['title']).join(', ')}\n'
        '📍 Places: ${_acceptedDestinations.map((d) => d['title']).join(', ')}\n'
        '━━━━━━━━━━━━━━━\n'
        'Powered by Triplix AI';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppConfig.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flight_takeoff,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '$from → $to',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$startDate - $endDate • $days days',
                style: const TextStyle(
                    color: AppConfig.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              // QR Code
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppConfig.borderColor, width: 2),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppConfig.primaryColor,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppConfig.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan to view trip details',
                style: TextStyle(color: AppConfig.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Trip summary chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _buildTripChip(
                      Icons.hotel, '${_acceptedAccommodation.length} Hotels'),
                  _buildTripChip(Icons.directions_car,
                      '${_acceptedTransport.length} Transport'),
                  _buildTripChip(
                      Icons.place, '${_acceptedDestinations.length} Places'),
                  _buildTripChip(Icons.people, '$_travelers Travelers'),
                ],
              ),
              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _shareItineraryText(itineraryText);
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share Full'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConfig.primaryColor,
                        side: const BorderSide(color: AppConfig.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppConfig.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppConfig.primaryColor),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppConfig.primaryColor,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _openItineraryTimeline(String itineraryText) {
    final from = _fromLocationController.text.trim();
    final to = _toLocationController.text.trim();
    final title = (from.isNotEmpty && to.isNotEmpty)
        ? '$from to $to'
        : 'My Trip Itinerary';

    final dateRange = _buildDateRangeLabel();
    final days = _buildTimelineDays(itineraryText);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripItineraryScreen(
          tripTitle: title,
          dateRange: dateRange,
          days: days,
        ),
      ),
    );
  }

  String _buildDateRangeLabel() {
    if (_startDate != null && _endDate != null) {
      return '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - '
          '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}';
    }
    return 'Dates not set';
  }

  List<Map<String, String>> _buildTimelineDays(String itineraryText) {
    final List<Map<String, String>> days = [];

    final regex = RegExp(
      r'(?im)^\s*(?:\*\*)?(day\s*\d+)(?:\*\*)?\s*[:\-]?\s*(.*)$',
    );
    final matches = regex.allMatches(itineraryText).toList();

    if (matches.isNotEmpty) {
      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        final dayLabel = _toTitleCase(match.group(1) ?? 'Day ${i + 1}');
        final titleText = (match.group(2) ?? '').trim();

        final start = match.end;
        final end = (i < matches.length - 1)
            ? matches[i + 1].start
            : itineraryText.length;
        final body = itineraryText.substring(start, end).trim();

        final desc = _cleanItinerarySnippet(body);
        days.add({
          'date': dayLabel,
          'title': titleText.isNotEmpty ? titleText : 'Plan',
          'desc': desc.isNotEmpty ? desc : 'Activities planned for this day',
        });
      }
    }

    if (days.isEmpty && _acceptedDestinations.isNotEmpty) {
      for (int i = 0; i < _acceptedDestinations.length; i++) {
        final destination = _acceptedDestinations[i];
        days.add({
          'date': 'Day ${i + 1}',
          'title': destination['title']?.toString() ?? 'Destination',
          'desc': destination['description']?.toString() ??
              'Explore local highlights and attractions.',
        });
      }
    }

    if (days.isEmpty) {
      return [
        {
          'date': 'Day 1',
          'title': 'Arrival & Orientation',
          'desc': 'Check-in and explore the nearby area.',
        },
      ];
    }

    return days;
  }

  String _cleanItinerarySnippet(String text) {
    return text
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'^[-•\d\.)\s]+', multiLine: true), '')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _toTitleCase(String input) {
    final parts = input.split(RegExp(r'\s+'));
    return parts
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  void _shareItineraryText(String itineraryText) {
    final from = _fromLocationController.text;
    final to = _toLocationController.text;
    final shareText = '✈️ My Trip: $from → $to\n'
        'Planned with Triplix AI\n\n'
        '$itineraryText';
    Share.share(shareText);
  }

  // Get button text based on current stage
  String _getFinishButtonText() {
    switch (_currentSwipeStage) {
      case 'hotels':
        final count = _acceptedAccommodation.length;
        if (count == 0) {
          return 'Skip Hotels - Continue';
        } else if (count == 1) {
          return 'Done with 1 Hotel - Continue';
        } else {
          return 'Done with $count Hotels - Continue';
        }
      case 'transport':
        final count = _acceptedTransport.length;
        if (count == 0) {
          return 'Skip Transport - Continue';
        } else if (count == 1) {
          return 'Done with 1 Transport - Continue';
        } else {
          return 'Done with $count Transport - Continue';
        }
      case 'destinations':
        final count = _acceptedDestinations.length;
        if (count < 2) {
          return 'Select at least 2 destinations';
        } else {
          return 'Done with $count Destinations - Generate Itinerary';
        }
      default:
        return 'Finish Selection';
    }
  }

  // Finish current stage and proceed to next
  void _finishCurrentStage() {
    // Close the swipe overlay
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Proceed based on current stage
    if (_currentSwipeStage == 'hotels') {
      if (_acceptedAccommodation.isEmpty) {
        // Show warning but allow to continue
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No hotels selected. Proceeding to transport...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _proceedToTransportStage();
    } else if (_currentSwipeStage == 'transport') {
      if (_acceptedTransport.isEmpty) {
        // Show warning but allow to continue
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('⚠️ No transport selected. Proceeding to destinations...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      _proceedToDestinationsStage();
    } else if (_currentSwipeStage == 'destinations') {
      if (_acceptedDestinations.length < 2) {
        // Don't allow to proceed with less than 2 destinations
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('❌ Please select at least 2 destinations for your trip!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        _generateFinalItinerary();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _generateTransportSuggestions() async {
    // Get source and destination cities for AI transport generation
    final prefsProvider = context.read<UserPreferencesProvider>();
    final fromCity = _fromLocationController.text.isNotEmpty
        ? _fromLocationController.text
        : 'Delhi'; // Use from location input or default
    final toCity = _toLocationController.text.isNotEmpty
        ? _toLocationController.text
        : (_stayCityController.text.isNotEmpty
            ? _stayCityController.text
            : prefsProvider.preferences.destination ?? 'Jaipur');

    final budget = prefsProvider.preferences.budget;
    final selectedTransport = prefsProvider.preferences.selectedTransport;

    print('🚗 Calling AI transport API: $fromCity → $toCity, Budget: $budget');
    print('🎯 User selected transport modes: $selectedTransport');

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/transport/search'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'from_city': fromCity,
          'to_city': toCity,
          'budget': budget,
          'transport_preferences': selectedTransport,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final suggestions = (data['suggestions'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();

        print('✅ Got ${suggestions.length} AI-generated transport options');

        // Filter based on user preferences
        final filtered =
            _filterTransportByPreferences(suggestions, selectedTransport);
        print('✅ After filtering: ${filtered.length} matching options');
        return filtered;
      } else {
        print('⚠️ API returned ${response.statusCode}, using fallback');
        return _getFallbackTransport(fromCity, toCity, selectedTransport);
      }
    } catch (e) {
      print('❌ Error calling transport API: $e');
      return _getFallbackTransport(fromCity, toCity, selectedTransport);
    }
  }

  // Filter transport options based on user preferences
  List<Map<String, dynamic>> _filterTransportByPreferences(
      List<Map<String, dynamic>> options, List<String> preferences) {
    if (preferences.isEmpty) {
      // No preferences selected, show all
      return options;
    }

    // Normalize preferences to lowercase for matching
    final normalizedPrefs = preferences.map((p) => p.toLowerCase()).toList();

    return options.where((option) {
      final title = (option['title'] as String?)?.toLowerCase() ?? '';
      final description =
          (option['description'] as String?)?.toLowerCase() ?? '';
      final optionType = (option['type'] as String?)?.toLowerCase() ?? '';

      // Check if option matches any selected preference
      for (final pref in normalizedPrefs) {
        // Map preferences to transport types
        if (pref.contains('flight') || pref.contains('air')) {
          if (optionType == 'flight' ||
              title.contains('✈️') ||
              title.contains('flight') ||
              title.contains('indigo') ||
              title.contains('air india') ||
              title.contains('spicejet') ||
              title.contains('vistara')) {
            return true;
          }
        }

        if (pref.contains('train') ||
            pref.contains('rail') ||
            pref.contains('express') ||
            pref.contains('rajdhani') ||
            pref.contains('shatabdi') ||
            pref.contains('vande bharat')) {
          if (optionType == 'train' ||
              title.contains('🚂') ||
              title.contains('train') ||
              title.contains('express') ||
              title.contains('railway')) {
            return true;
          }
        }

        if (pref.contains('road') ||
            pref.contains('bus') ||
            pref.contains('car') ||
            pref.contains('taxi') ||
            pref.contains('volvo') ||
            pref.contains('coach')) {
          if (optionType == 'bus' ||
              title.contains('🚌') ||
              title.contains('bus') ||
              title.contains('🚗') ||
              title.contains('car') ||
              title.contains('taxi') ||
              title.contains('volvo')) {
            return true;
          }
        }

        // Direct string matching for other preferences
        if (title.contains(pref) || description.contains(pref)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _getFallbackTransport(
      String fromCity, String toCity, List<String> preferences) {
    // Fallback transport options when AI fails
    final allOptions = [
      {
        'id': 'flight_1',
        'type': 'transport',
        'title': '✈️ IndiGo 6E-2031',
        'description':
            '$fromCity → $toCity\nDirect flight • 2h 15min\nDeparture: 06:30 AM\n₹8,500 - ₹12,000 per person',
        'price': 10000,
        'image':
            'https://images.unsplash.com/photo-1436491865332-7a61a109db05?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'carrier': 'IndiGo',
          'flight_number': '6E-2031',
          'departure': '06:30 AM',
          'arrival': '08:45 AM',
          'duration': '2h 15min',
          'type': 'Direct'
        }
      },
      {
        'id': 'flight_2',
        'type': 'transport',
        'title': '✈️ Air India AI-7821',
        'description':
            '$fromCity → $toCity\nDirect flight • 2h 10min\nDeparture: 02:15 PM\n₹7,200 - ₹10,500 per person',
        'price': 8500,
        'image':
            'https://images.unsplash.com/photo-1569154941061-e231b4725ef1?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'carrier': 'Air India',
          'flight_number': 'AI-7821',
          'departure': '02:15 PM',
          'arrival': '04:25 PM',
          'duration': '2h 10min',
          'type': 'Direct'
        }
      },
      {
        'id': 'train_1',
        'type': 'transport',
        'title': '🚂 Rajdhani Express 12432',
        'description':
            '$fromCity → $toCity\n2AC/3AC available • 18-20 hours\nDeparture: 05:30 PM\n₹2,800 - ₹4,200 per person',
        'price': 3500,
        'image':
            'https://images.unsplash.com/photo-1540746238299-83c4b1673953?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'train_name': 'Rajdhani Express',
          'train_number': '12432',
          'departure': '05:30 PM',
          'arrival': '11:45 AM +1',
          'duration': '18h 15min',
          'class': '2AC/3AC'
        }
      },
      {
        'id': 'train_2',
        'type': 'transport',
        'title': '🚂 Shatabdi Express 12010',
        'description':
            '$fromCity → $toCity\nChair Car/Executive • 15-17 hours\nDeparture: 06:00 AM\n₹1,800 - ₹3,500 per person',
        'price': 2500,
        'image':
            'https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'train_name': 'Shatabdi Express',
          'train_number': '12010',
          'departure': '06:00 AM',
          'arrival': '09:15 PM',
          'duration': '15h 15min',
          'class': 'CC/EC'
        }
      },
      {
        'id': 'train_3',
        'type': 'transport',
        'title': '🚂 Duronto Express 12213',
        'description':
            '$fromCity → $toCity\nNon-stop train • 16-18 hours\nDeparture: 11:30 PM\n₹2,200 - ₹3,800 per person',
        'price': 3000,
        'image':
            'https://images.unsplash.com/photo-1532105956626-9569c03602f6?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'train_name': 'Duronto Express',
          'train_number': '12213',
          'departure': '11:30 PM',
          'arrival': '05:45 PM +1',
          'duration': '18h 15min',
          'class': 'Sleeper/3AC'
        }
      },
      {
        'id': 'bus_1',
        'type': 'transport',
        'title': '🚌 Volvo Multi-Axle AC',
        'description':
            '$fromCity → $toCity\nLuxury sleeper bus • 20-22 hours\nDeparture: 06:00 PM\n₹1,500 - ₹2,800 per person',
        'price': 2000,
        'image':
            'https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=800&h=600&fit=crop',
        'stage': 'transport',
        'details': {
          'operator': 'Redbus/RSRTC',
          'bus_type': 'Volvo Multi-Axle AC Sleeper',
          'departure': '06:00 PM',
          'arrival': '02:00 PM +1',
          'duration': '20h',
          'amenities': 'WiFi, Charging, Blankets'
        }
      },
    ];

    // Filter based on user preferences
    return _filterTransportByPreferences(allOptions, preferences);
  }

  /// Fetch seasonal activities from AI backend (replaces hardcoded lists)
  Future<List<Map<String, dynamic>>> _fetchSeasonalActivities() async {
    final city = _toLocationController.text.trim();
    final days = _endDate != null && _startDate != null
        ? _endDate!.difference(_startDate!).inDays + 1
        : 3;

    int maxDestinations;
    if (days <= 2) {
      maxDestinations = 6;
    } else if (days <= 5) {
      maxDestinations = 10;
    } else if (days <= 10) {
      maxDestinations = 15;
    } else {
      maxDestinations = 20;
    }

    print(
        '🎯 Fetching seasonal activities for $city, $days days, max $maxDestinations');

    try {
      final result = await _pythonADK.getSeasonalActivities(
        city: city,
        travelDate: _startDate?.toIso8601String(),
        days: days,
        count: maxDestinations,
      );

      if (result['success'] == true) {
        final activities = (result['activities'] as List)
            .map<Map<String, dynamic>>((a) => Map<String, dynamic>.from(a))
            .toList();
        if (activities.isNotEmpty) {
          print('✅ Got ${activities.length} AI-generated seasonal activities');
          return activities;
        }
      }
    } catch (e) {
      print('❌ Seasonal activities API failed: $e');
    }

    // Fallback: real place recommendations per city
    print('⚠️ Using fallback activities for $city');
    final cityLower = city.toLowerCase();
    final Map<String, List<Map<String, String>>> cityPlaces = {
      'delhi': [
        {
          'title': 'Red Fort',
          'desc': 'Iconic Mughal-era fort & UNESCO World Heritage Site',
          'image':
              'https://images.unsplash.com/photo-1587474260584-136574528ed5?w=800&h=600&fit=crop'
        },
        {
          'title': 'Qutub Minar',
          'desc': 'Tallest brick minaret in the world, built in 1193',
          'image':
              'https://images.unsplash.com/photo-1548013146-72479768bada?w=800&h=600&fit=crop'
        },
        {
          'title': 'India Gate',
          'desc': 'War memorial & popular evening gathering spot',
          'image':
              'https://images.unsplash.com/photo-1597040663342-45b6ba68fa0b?w=800&h=600&fit=crop'
        },
        {
          'title': 'Chandni Chowk',
          'desc': 'Bustling old Delhi market with famous street food',
          'image':
              'https://images.unsplash.com/photo-1567157577867-05ccb1388e13?w=800&h=600&fit=crop'
        },
        {
          'title': 'Lotus Temple',
          'desc': 'Stunning flower-shaped Bahá\'í House of Worship',
          'image':
              'https://images.unsplash.com/photo-1622547748225-3fc4abd2cca0?w=800&h=600&fit=crop'
        },
      ],
      'mumbai': [
        {
          'title': 'Gateway of India',
          'desc': 'Historic arch monument overlooking the Arabian Sea',
          'image':
              'https://images.unsplash.com/photo-1570168007204-dfb528c6958f?w=800&h=600&fit=crop'
        },
        {
          'title': 'Marine Drive',
          'desc': 'Scenic 3.6 km waterfront promenade – Queen\'s Necklace',
          'image':
              'https://images.unsplash.com/photo-1567157577867-05ccb1388e13?w=800&h=600&fit=crop'
        },
        {
          'title': 'Elephanta Caves',
          'desc': 'Ancient rock-cut cave temples on Elephanta Island',
          'image':
              'https://images.unsplash.com/photo-1595658658481-d53d3f999875?w=800&h=600&fit=crop'
        },
        {
          'title': 'Chhatrapati Shivaji Terminus',
          'desc': 'UNESCO-listed Victorian Gothic railway station',
          'image':
              'https://images.unsplash.com/photo-1529253355930-ddbe423a2ac7?w=800&h=600&fit=crop'
        },
        {
          'title': 'Juhu Beach',
          'desc': 'Famous beach known for street food & sunset views',
          'image':
              'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop'
        },
      ],
      'jaipur': [
        {
          'title': 'Hawa Mahal',
          'desc': 'Palace of Winds with 953 small windows',
          'image':
              'https://images.unsplash.com/photo-1599661046289-e31897846e41?w=800&h=600&fit=crop'
        },
        {
          'title': 'Amber Fort',
          'desc': 'Majestic hilltop fort with Sheesh Mahal mirror palace',
          'image':
              'https://images.unsplash.com/photo-1477587458883-47145ed94245?w=800&h=600&fit=crop'
        },
        {
          'title': 'City Palace',
          'desc': 'Royal residence blending Rajasthani & Mughal architecture',
          'image':
              'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800&h=600&fit=crop'
        },
        {
          'title': 'Jantar Mantar',
          'desc': 'UNESCO World Heritage astronomical observation site',
          'image':
              'https://images.unsplash.com/photo-1573804013941-ef7e7f457f5e?w=800&h=600&fit=crop'
        },
        {
          'title': 'Nahargarh Fort',
          'desc': 'Hilltop fort with panoramic views of the Pink City',
          'image':
              'https://images.unsplash.com/photo-1599661046827-dacff0c0f09a?w=800&h=600&fit=crop'
        },
      ],
      'goa': [
        {
          'title': 'Basilica of Bom Jesus',
          'desc': 'UNESCO World Heritage church with sacred relics',
          'image':
              'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=800&h=600&fit=crop'
        },
        {
          'title': 'Calangute Beach',
          'desc': 'Queen of Beaches – vibrant nightlife & water sports',
          'image':
              'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop'
        },
        {
          'title': 'Fort Aguada',
          'desc': '17th-century Portuguese fort with lighthouse & sea views',
          'image':
              'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=800&h=600&fit=crop'
        },
        {
          'title': 'Dudhsagar Falls',
          'desc': 'Stunning four-tiered waterfall on the Mandovi River',
          'image':
              'https://images.unsplash.com/photo-1432405972618-c6b0cfba8428?w=800&h=600&fit=crop'
        },
        {
          'title': 'Anjuna Flea Market',
          'desc': 'Vibrant Wednesday market with handicrafts & food',
          'image':
              'https://images.unsplash.com/photo-1555529669-e69e7aa0ba9a?w=800&h=600&fit=crop'
        },
      ],
      'bangalore': [
        {
          'title': 'Lalbagh Botanical Garden',
          'desc': 'Historic 240-acre garden with a glass house & lake',
          'image':
              'https://images.unsplash.com/photo-1585320806297-9794b3e4eeae?w=800&h=600&fit=crop'
        },
        {
          'title': 'Bangalore Palace',
          'desc': 'Tudor-style palace inspired by Windsor Castle',
          'image':
              'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800&h=600&fit=crop'
        },
        {
          'title': 'Cubbon Park',
          'desc': 'Sprawling 300-acre green lung in the heart of the city',
          'image':
              'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=800&h=600&fit=crop'
        },
        {
          'title': 'ISKCON Temple',
          'desc': 'Stunning hilltop temple with ornate architecture',
          'image':
              'https://images.unsplash.com/photo-1561361513-2d000a50f0dc?w=800&h=600&fit=crop'
        },
        {
          'title': 'Commercial Street',
          'desc': 'Bustling shopping hub with bargains & local eats',
          'image':
              'https://images.unsplash.com/photo-1555529669-e69e7aa0ba9a?w=800&h=600&fit=crop'
        },
      ],
    };

    // Find matching city or use generic real places
    List<Map<String, String>> places = [];
    for (final key in cityPlaces.keys) {
      if (cityLower.contains(key) || key.contains(cityLower)) {
        places = cityPlaces[key]!;
        break;
      }
    }
    if (places.isEmpty) {
      places = [
        {
          'title': 'City Heritage Walk',
          'desc': 'Explore historic landmarks & architecture of $city',
          'image':
              'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800&h=600&fit=crop'
        },
        {
          'title': 'Local Street Food Tour',
          'desc': 'Taste authentic local delicacies & hidden gems',
          'image':
              'https://images.unsplash.com/photo-1567337710282-00832b415979?w=800&h=600&fit=crop'
        },
        {
          'title': 'Scenic Viewpoint',
          'desc': 'Best panoramic views & photo spots in $city',
          'image':
              'https://images.unsplash.com/photo-1506012787146-f92b2d7d6d96?w=800&h=600&fit=crop'
        },
        {
          'title': 'Cultural Museum',
          'desc': 'Discover art, history & heritage of the region',
          'image':
              'https://images.unsplash.com/photo-1554907984-15263bfd63bd?w=800&h=600&fit=crop'
        },
        {
          'title': 'Local Market & Bazaar',
          'desc': 'Shop for handicrafts, souvenirs & local specialties',
          'image':
              'https://images.unsplash.com/photo-1555529669-e69e7aa0ba9a?w=800&h=600&fit=crop'
        },
      ];
    }

    final count =
        maxDestinations > places.length ? places.length : maxDestinations;
    return List.generate(
      count,
      (i) => {
        'id': 'place_${i + 1}',
        'type': 'destination',
        'title': places[i]['title']!,
        'description': places[i]['desc']!,
        'image': places[i]['image']!,
        'stage': 'destinations',
      },
    );
  }

  void _handleReplacementResponse(
      bool wantsReplacement, Map<String, dynamic> removedItem) async {
    if (wantsReplacement) {
      setState(() {
        _isTyping = true;
        _messages.add({
          'sender': 'user',
          'message': 'Yes, show me alternatives',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();

      try {
        // Call AI to get replacement suggestions
        final replacement = await _pythonADK.sendToManager(
          message: 'Find alternatives for ${removedItem['title']}',
          context: {
            'page': 'home',
            'action': 'find_replacement',
            'removed_item': removedItem,
            'type': 'destination',
          },
          page: 'home',
        );

        final replacementSuggestions =
            replacement['suggestions'] as List<dynamic>? ?? [];

        setState(() {
          _isTyping = false;
          if (replacementSuggestions.isNotEmpty) {
            _messages.add({
              'sender': 'triplix',
              'message': 'Here are some great alternatives for you!',
              'type': 'suggestions',
              'suggestions': replacementSuggestions,
              'timestamp': DateTime.now().toString(),
            });
            _currentSuggestions =
                replacementSuggestions.cast<Map<String, dynamic>>();
          } else {
            _messages.add({
              'sender': 'triplix',
              'message':
                  'I apologize, but I couldn\'t find suitable alternatives at the moment. Would you like to try different criteria?',
              'type': 'text',
              'timestamp': DateTime.now().toString(),
            });
          }
        });
        _scrollToBottom();
      } catch (e) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'sender': 'triplix',
            'message':
                'I had trouble finding alternatives. Please try again or let me know your preferences.',
            'type': 'text',
            'timestamp': DateTime.now().toString(),
          });
        });
        _scrollToBottom();
      }
    } else {
      setState(() {
        _messages.add({
          'sender': 'user',
          'message': 'No, thanks',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
        _messages.add({
          'sender': 'triplix',
          'message': 'No problem! Continue exploring other destinations.',
          'type': 'text',
          'timestamp': DateTime.now().toString(),
        });
      });
      _scrollToBottom();
    }
  }

  void _confirmSelection(String type, Map<String, dynamic> selectedOption) {
    setState(() {
      _messages.add({
        'sender': 'user',
        'message': 'I choose: ${selectedOption['title']}',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
      _messages.add({
        'sender': 'triplix',
        'message':
            'Excellent choice! "${selectedOption['title']}" has been added to your itinerary. Let\'s continue with your planning!',
        'type': 'text',
        'timestamp': DateTime.now().toString(),
      });
    });
    _scrollToBottom();

    // Move to next stage
    if (type == 'transport') {
      _currentSwipeStage = 'accommodation';
      // Show accommodation suggestions
      Future.delayed(const Duration(milliseconds: 800), () {
        setState(() {
          _messages.add({
            'sender': 'triplix',
            'message':
                'Now let\'s find you the perfect accommodation! Swipe right on 2 options you like.',
            'type': 'suggestions',
            'suggestions': _generateStageSpecificSuggestions('accommodation'),
            'timestamp': DateTime.now().toString(),
          });
          _currentSuggestions =
              _generateStageSpecificSuggestions('accommodation');
        });
        _scrollToBottom();
      });
    } else if (type == 'accommodation') {
      _currentSwipeStage = 'destinations';
      // Show destination suggestions
      Future.delayed(const Duration(milliseconds: 800), () {
        setState(() {
          _messages.add({
            'sender': 'triplix',
            'message':
                'Great! Now let\'s explore destinations. I\'ll show you 10 amazing places. Swipe left if you\'re not interested!',
            'type': 'suggestions',
            'suggestions': _generateStageSpecificSuggestions('destinations'),
            'timestamp': DateTime.now().toString(),
          });
          _currentSuggestions =
              _generateStageSpecificSuggestions('destinations');
        });
        _scrollToBottom();
      });
    }
  }

  List<Map<String, dynamic>> _generateStageSpecificSuggestions(String stage) {
    switch (stage) {
      case 'transport':
        return [
          {
            'id': 'transport_1',
            'type': 'transport',
            'title': 'Private Car with Driver',
            'description':
                'Comfortable AC sedan with experienced driver for city tours and airport transfers',
            'price': 2500,
            'rating': 4.5,
          },
          {
            'id': 'transport_2',
            'type': 'transport',
            'title': 'Express Train First Class',
            'description':
                'High-speed rail with comfortable seating, meals included, and scenic route views',
            'price': 1800,
            'rating': 4.6,
          },
          {
            'id': 'transport_3',
            'type': 'transport',
            'title': 'Domestic Flight Economy',
            'description':
                'Direct flight with major airline, checked baggage included, fastest option',
            'price': 4500,
            'rating': 4.7,
          },
          {
            'id': 'transport_4',
            'type': 'transport',
            'title': 'Luxury Coach Bus',
            'description':
                'Premium bus service with reclining seats, entertainment, and refreshments',
            'price': 1200,
            'rating': 4.3,
          },
          {
            'id': 'transport_5',
            'type': 'transport',
            'title': 'Bike Rental Package',
            'description':
                'Self-drive motorcycle rental with helmet, insurance, and roadside assistance',
            'price': 800,
            'rating': 4.4,
          },
        ];

      case 'accommodation':
        return [
          {
            'id': 'hotel_1',
            'type': 'hotel',
            'title': 'Luxury Beach Resort',
            'description':
                '5-star beachfront resort with private villas, spa, and infinity pool',
            'price': 12500,
            'rating': 4.8,
          },
          {
            'id': 'hotel_2',
            'type': 'hotel',
            'title': 'Heritage Palace Hotel',
            'description':
                'Restored 18th-century palace with royal suites and cultural performances',
            'price': 8500,
            'rating': 4.7,
          },
          {
            'id': 'hotel_3',
            'type': 'hotel',
            'title': 'Mountain View Resort',
            'description':
                'Scenic hillside property with valley views and adventure sports',
            'price': 6500,
            'rating': 4.6,
          },
          {
            'id': 'hotel_4',
            'type': 'hotel',
            'title': 'Business Class Hotel',
            'description':
                'Modern business hotel in city center with conference facilities',
            'price': 5500,
            'rating': 4.5,
          },
          {
            'id': 'hotel_5',
            'type': 'hotel',
            'title': 'Budget Boutique Inn',
            'description':
                'Cozy boutique hotel with comfortable rooms and complimentary breakfast',
            'price': 3500,
            'rating': 4.4,
          },
        ];

      case 'destinations':
        return [
          {
            'id': 'destination_1',
            'type': 'destination',
            'title': 'City Heritage Walk',
            'description':
                'Guided walking tour through historic forts, markets, and colonial architecture',
            'price': 800,
            'rating': 4.6,
          },
          {
            'id': 'destination_2',
            'type': 'destination',
            'title': 'Beach Paradise',
            'description':
                'Pristine beaches with water sports, seafood shacks, and stunning sunset views',
            'price': 500,
            'rating': 4.8,
          },
          {
            'id': 'destination_3',
            'type': 'destination',
            'title': 'Mountain Adventure Trail',
            'description':
                'Trekking route through pine forests, waterfalls, and panoramic viewpoints',
            'price': 1200,
            'rating': 4.7,
          },
          {
            'id': 'destination_4',
            'type': 'destination',
            'title': 'Ancient Temple Complex',
            'description':
                'UNESCO heritage site with intricate carvings, spiritual ambiance, and history',
            'price': 300,
            'rating': 4.9,
          },
          {
            'id': 'destination_5',
            'type': 'destination',
            'title': 'Wildlife Safari Park',
            'description':
                'Jungle safari with chances to spot tigers, elephants, and exotic birds',
            'price': 2500,
            'rating': 4.8,
          },
          {
            'id': 'destination_6',
            'type': 'destination',
            'title': 'Local Food Market Tour',
            'description':
                'Culinary journey through bustling markets, street food, and cooking classes',
            'price': 600,
            'rating': 4.5,
          },
          {
            'id': 'destination_7',
            'type': 'destination',
            'title': 'Art Gallery District',
            'description':
                'Contemporary art galleries, street murals, and artisan workshops',
            'price': 400,
            'rating': 4.4,
          },
          {
            'id': 'destination_8',
            'type': 'destination',
            'title': 'Sunset Cruise',
            'description':
                'Relaxing boat ride with live music, dinner, and spectacular coastal views',
            'price': 1800,
            'rating': 4.7,
          },
          {
            'id': 'destination_9',
            'type': 'destination',
            'title': 'Adventure Theme Park',
            'description':
                'Thrilling rides, water slides, and family-friendly entertainment',
            'price': 1500,
            'rating': 4.6,
          },
          {
            'id': 'destination_10',
            'type': 'destination',
            'title': 'Spa & Wellness Retreat',
            'description':
                'Rejuvenating spa treatments, yoga sessions, and meditation in tranquil gardens',
            'price': 3500,
            'rating': 4.8,
          },
        ];

      default:
        return [];
    }
  }

  void _showSwipeFeedback(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _generateInitialSuggestions() {
    // Generate initial suggestions: 5 hotels, 5 transport, 10 destinations
    final suggestions = <Map<String, dynamic>>[];

    // Add 5 hotels
    suggestions.addAll([
      {
        'id': 'hotel_1',
        'type': 'hotel',
        'title': 'Luxury Beach Resort',
        'description':
            '5-star beachfront resort with private villas, spa, and infinity pool overlooking the Arabian Sea',
        'price': 12500,
        'rating': 4.8,
      },
      {
        'id': 'hotel_2',
        'type': 'hotel',
        'title': 'Heritage Palace Hotel',
        'description':
            'Restored 18th-century palace with royal suites, traditional dining, and cultural performances',
        'price': 8500,
        'rating': 4.7,
      },
      {
        'id': 'hotel_3',
        'type': 'hotel',
        'title': 'Mountain View Resort',
        'description':
            'Scenic hillside property with valley views, adventure sports, and organic farm-to-table restaurant',
        'price': 6500,
        'rating': 4.6,
      },
      {
        'id': 'hotel_4',
        'type': 'hotel',
        'title': 'Business Class Hotel',
        'description':
            'Modern business hotel in city center with conference facilities, gym, and rooftop bar',
        'price': 5500,
        'rating': 4.5,
      },
      {
        'id': 'hotel_5',
        'type': 'hotel',
        'title': 'Budget Boutique Inn',
        'description':
            'Cozy boutique hotel with comfortable rooms, local charm, and complimentary breakfast',
        'price': 3500,
        'rating': 4.4,
      },
    ]);

    // Add 5 transport options
    suggestions.addAll([
      {
        'id': 'transport_1',
        'type': 'transport',
        'title': 'Private Car with Driver',
        'description':
            'Comfortable AC sedan with experienced driver for city tours and airport transfers',
        'price': 2500,
        'rating': 4.5,
      },
      {
        'id': 'transport_2',
        'type': 'transport',
        'title': 'Express Train First Class',
        'description':
            'High-speed rail with comfortable seating, meals included, and scenic route views',
        'price': 1800,
        'rating': 4.6,
      },
      {
        'id': 'transport_3',
        'type': 'transport',
        'title': 'Domestic Flight Economy',
        'description':
            'Direct flight with major airline, checked baggage included, fastest option',
        'price': 4500,
        'rating': 4.7,
      },
      {
        'id': 'transport_4',
        'type': 'transport',
        'title': 'Luxury Coach Bus',
        'description':
            'Premium bus service with reclining seats, entertainment, and refreshments',
        'price': 1200,
        'rating': 4.3,
      },
      {
        'id': 'transport_5',
        'type': 'transport',
        'title': 'Bike Rental Package',
        'description':
            'Self-drive motorcycle rental with helmet, insurance, and roadside assistance',
        'price': 800,
        'rating': 4.4,
      },
    ]);

    // Add 10 destinations
    suggestions.addAll([
      {
        'id': 'destination_1',
        'type': 'destination',
        'title': 'City Heritage Walk',
        'description':
            'Guided walking tour through historic forts, markets, and colonial architecture',
        'price': 800,
        'rating': 4.6,
      },
      {
        'id': 'destination_2',
        'type': 'destination',
        'title': 'Beach Paradise',
        'description':
            'Pristine beaches with water sports, seafood shacks, and stunning sunset views',
        'price': 500,
        'rating': 4.8,
      },
      {
        'id': 'destination_3',
        'type': 'destination',
        'title': 'Mountain Adventure Trail',
        'description':
            'Trekking route through pine forests, waterfalls, and panoramic viewpoints',
        'price': 1200,
        'rating': 4.7,
      },
      {
        'id': 'destination_4',
        'type': 'destination',
        'title': 'Ancient Temple Complex',
        'description':
            'UNESCO heritage site with intricate carvings, spiritual ambiance, and history',
        'price': 300,
        'rating': 4.9,
      },
      {
        'id': 'destination_5',
        'type': 'destination',
        'title': 'Wildlife Safari Park',
        'description':
            'Jungle safari with chances to spot tigers, elephants, and exotic birds',
        'price': 2500,
        'rating': 4.8,
      },
      {
        'id': 'destination_6',
        'type': 'destination',
        'title': 'Local Food Market Tour',
        'description':
            'Culinary journey through bustling markets, street food, and cooking classes',
        'price': 600,
        'rating': 4.5,
      },
      {
        'id': 'destination_7',
        'type': 'destination',
        'title': 'Art Gallery District',
        'description':
            'Contemporary art galleries, street murals, and artisan workshops',
        'price': 400,
        'rating': 4.4,
      },
      {
        'id': 'destination_8',
        'type': 'destination',
        'title': 'Sunset Cruise',
        'description':
            'Relaxing boat ride with live music, dinner, and spectacular coastal views',
        'price': 1800,
        'rating': 4.7,
      },
      {
        'id': 'destination_9',
        'type': 'destination',
        'title': 'Adventure Theme Park',
        'description':
            'Thrilling rides, water slides, and family-friendly entertainment',
        'price': 1500,
        'rating': 4.6,
      },
      {
        'id': 'destination_10',
        'type': 'destination',
        'title': 'Spa & Wellness Retreat',
        'description':
            'Rejuvenating spa treatments, yoga sessions, and meditation in tranquil gardens',
        'price': 3500,
        'rating': 4.8,
      },
    ]);

    return suggestions;
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppConfig.primaryColor.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Triplix is typing',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppConfig.primaryColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder tabs
class BudgetTab extends StatefulWidget {
  const BudgetTab({super.key});

  @override
  State<BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends State<BudgetTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PythonADKService _pythonADK = PythonADKService();

  double _totalBudget = 0;
  int _groupSize = 1;
  bool _isBudgetSet = false;
  bool _isTyping = false;

  // Budget allocation percentages
  final Map<String, double> _allocation = {
    'Accommodation': 30,
    'Transportation': 20,
    'Food & Dining': 15,
    'Activities': 15,
    'Shopping': 10,
    'Emergency': 10,
  };

  // Tracked expenses
  final List<Map<String, dynamic>> _expenses = [];

  // Chat messages
  final List<Map<String, String>> _chatMessages = [
    {
      'sender': 'ai',
      'message': '👋 Hi! I\'m your AI Budget Manager.\n\n'
          'I can help you:\n'
          '• Set & distribute your travel budget\n'
          '• Track expenses in real-time\n'
          '• Split costs among your group\n'
          '• Suggest savings & smart spending tips\n\n'
          'Start by telling me your total budget, e.g. "My budget is ₹50,000 for 3 people"',
    },
  ];

  // Category icons & colors
  final Map<String, IconData> _categoryIcons = {
    'Accommodation': Icons.hotel,
    'Transportation': Icons.directions_car,
    'Food & Dining': Icons.restaurant,
    'Activities': Icons.local_activity,
    'Shopping': Icons.shopping_bag,
    'Emergency': Icons.health_and_safety,
  };

  final Map<String, Color> _categoryColors = {
    'Accommodation': const Color(0xFF1e3a8a),
    'Transportation': const Color(0xFFea580c),
    'Food & Dining': const Color(0xFF10b981),
    'Activities': const Color(0xFF8b5cf6),
    'Shopping': const Color(0xFFec4899),
    'Emergency': const Color(0xFF64748b),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    // Load budget from preferences if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = context.read<UserPreferencesProvider>().preferences;
      if (prefs.budget != null && prefs.budget! > 0) {
        setState(() {
          _totalBudget = prefs.budget!.toDouble();
          _groupSize = prefs.numberOfPeople ?? 1;
          _isBudgetSet = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _amountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double get _totalSpent =>
      _expenses.fold(0, (sum, e) => sum + (e['amount'] as double));
  double get _remaining => _totalBudget - _totalSpent;
  double get _perPerson =>
      _groupSize > 0 ? _totalBudget / _groupSize : _totalBudget;
  double get _spentPerPerson =>
      _groupSize > 0 ? _totalSpent / _groupSize : _totalSpent;

  Map<String, double> get _spentByCategory {
    final map = <String, double>{};
    for (final e in _expenses) {
      final cat = e['category'] as String;
      map[cat] = (map[cat] ?? 0) + (e['amount'] as double);
    }
    return map;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendChatMessage(String message) async {
    if (message.trim().isEmpty) return;
    _chatController.clear();

    setState(() {
      _chatMessages.add({'sender': 'user', 'message': message});
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // Send to AI manager with budget context
      final response = await _pythonADK.sendToManager(
        message: message,
        context: {
          'page': 'budget',
          'action': 'budget_chat',
          'budget_info': {
            'total_budget': _totalBudget,
            'group_size': _groupSize,
            'total_spent': _totalSpent,
            'remaining': _remaining,
            'per_person': _perPerson,
            'expenses': _expenses,
            'allocation': _allocation,
            'spent_by_category': _spentByCategory,
          },
        },
        page: 'budget',
      );

      final aiReply =
          response['response'] ?? 'I\'ll help you with your budget!';

      // Check if AI detected a budget setup command
      _tryParseBudgetFromMessage(message);
      // Check if AI detected an expense
      final expenseBefore = _expenses.length;
      _tryParseExpenseFromMessage(message);
      final expenseAdded = _expenses.length > expenseBefore;

      setState(() {
        _isTyping = false;
        // Show expense card in chat if expense was added
        if (expenseAdded) {
          final lastExp = _expenses.last;
          _chatMessages.add({
            'sender': 'ai',
            'message': '✅ **Expense Recorded**\n\n'
                '📂 Category: ${lastExp['category']}\n'
                '💰 Amount: ₹${(lastExp['amount'] as double).toStringAsFixed(0)}\n'
                '📝 Description: ${lastExp['description']}\n\n'
                '━━━━━━━━━━━━━━━━━━━━\n'
                '💰 Total Budget: ₹${_totalBudget.toStringAsFixed(0)}\n'
                '💸 Total Spent: ₹${_totalSpent.toStringAsFixed(0)}\n'
                '✅ Remaining: ₹${_remaining.toStringAsFixed(0)}\n'
                '📊 Expenses logged: ${_expenses.length}',
          });
        } else {
          _chatMessages.add({'sender': 'ai', 'message': aiReply});
        }
        // Show budget set card
        if (_isBudgetSet && expenseBefore == 0 && !expenseAdded) {
          // Budget was just set, already handled by aiReply
        }
      });
    } catch (e) {
      // Fallback: handle locally
      _tryParseBudgetFromMessage(message);
      final expenseBefore = _expenses.length;
      _tryParseExpenseFromMessage(message);
      final expenseAdded = _expenses.length > expenseBefore;

      setState(() {
        _isTyping = false;
        if (expenseAdded) {
          final lastExp = _expenses.last;
          _chatMessages.add({
            'sender': 'ai',
            'message': '✅ **Expense Recorded**\n\n'
                '📂 Category: ${lastExp['category']}\n'
                '💰 Amount: ₹${(lastExp['amount'] as double).toStringAsFixed(0)}\n'
                '📝 Description: ${lastExp['description']}\n\n'
                '━━━━━━━━━━━━━━━━━━━━\n'
                '💰 Total Budget: ₹${_totalBudget.toStringAsFixed(0)}\n'
                '💸 Total Spent: ₹${_totalSpent.toStringAsFixed(0)}\n'
                '✅ Remaining: ₹${_remaining.toStringAsFixed(0)}\n'
                '📊 Expenses logged: ${_expenses.length}',
          });
        } else {
          _chatMessages.add({
            'sender': 'ai',
            'message': _generateLocalResponse(message),
          });
        }
      });
    }
    _scrollToBottom();
  }

  void _tryParseBudgetFromMessage(String message) {
    final budgetMatch = RegExp(r'(?:budget|total|rs\.?|₹)\s*[:\s]*(\d[\d,]*)',
            caseSensitive: false)
        .firstMatch(message);
    if (budgetMatch != null) {
      final amount = double.tryParse(budgetMatch.group(1)!.replaceAll(',', ''));
      if (amount != null && amount > 0) {
        final peopleMatch = RegExp(r'(\d+)\s*(?:people|person|travelers|pax)',
                caseSensitive: false)
            .firstMatch(message);
        setState(() {
          _totalBudget = amount;
          if (peopleMatch != null) {
            _groupSize = int.tryParse(peopleMatch.group(1)!) ?? _groupSize;
          }
          _isBudgetSet = true;
        });
      }
    }
  }

  void _tryParseExpenseFromMessage(String message) {
    // Pattern 1: "spent 2000 on hotel" / "paid 500 for lunch"
    final expenseMatch = RegExp(
            r'(?:spent|paid|expense|cost|charged)\s*(?:rs\.?|₹)?\s*(\d[\d,]*)\s*(?:on|for)\s+(.+)',
            caseSensitive: false)
        .firstMatch(message);
    // Pattern 2: "1000 rs for accommodation" / "₹2000 for food" / "1000 for hotel"
    final altMatch = RegExp(
            r'(?:rs\.?|₹)?\s*(\d[\d,]*)\s*(?:rs\.?|₹|rupees?)?\s*(?:on|for)\s+(.+)',
            caseSensitive: false)
        .firstMatch(message);

    final match = expenseMatch ?? altMatch;
    if (match != null) {
      final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
      final desc = match.group(2)!.trim();
      if (amount != null && amount > 0) {
        final category = _inferCategory(desc);
        setState(() {
          _expenses.add({
            'amount': amount,
            'description': desc,
            'category': category,
            'date': DateTime.now().toIso8601String(),
          });
        });
      }
    }
  }

  String _inferCategory(String description) {
    final d = description.toLowerCase();
    if (d.contains('hotel') ||
        d.contains('room') ||
        d.contains('stay') ||
        d.contains('resort') ||
        d.contains('hostel')) {
      return 'Accommodation';
    }
    if (d.contains('flight') ||
        d.contains('train') ||
        d.contains('bus') ||
        d.contains('taxi') ||
        d.contains('cab') ||
        d.contains('uber') ||
        d.contains('ola') ||
        d.contains('travel')) {
      return 'Transportation';
    }
    if (d.contains('food') ||
        d.contains('restaurant') ||
        d.contains('lunch') ||
        d.contains('dinner') ||
        d.contains('breakfast') ||
        d.contains('eat') ||
        d.contains('cafe') ||
        d.contains('meal')) {
      return 'Food & Dining';
    }
    if (d.contains('ticket') ||
        d.contains('entry') ||
        d.contains('tour') ||
        d.contains('activity') ||
        d.contains('park') ||
        d.contains('museum') ||
        d.contains('trek')) {
      return 'Activities';
    }
    if (d.contains('shop') ||
        d.contains('souvenir') ||
        d.contains('market') ||
        d.contains('buy') ||
        d.contains('gift')) {
      return 'Shopping';
    }
    return 'Emergency';
  }

  String _generateLocalResponse(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('budget') &&
        (msg.contains('set') ||
            msg.contains('total') ||
            RegExp(r'\d').hasMatch(msg))) {
      if (_isBudgetSet) {
        return '✅ Budget updated!\n\n'
            '💰 Total: ₹${_totalBudget.toStringAsFixed(0)}\n'
            '👥 Group: $_groupSize people\n'
            '👤 Per person: ₹${_perPerson.toStringAsFixed(0)}\n\n'
            'You can now add expenses like "Spent ₹3000 on hotel" or ask me to redistribute your budget.';
      }
    }
    if (msg.contains('summary') ||
        msg.contains('status') ||
        msg.contains('how much')) {
      return '📊 Budget Summary\n\n'
          '💰 Total: ₹${_totalBudget.toStringAsFixed(0)}\n'
          '💸 Spent: ₹${_totalSpent.toStringAsFixed(0)} (${(_totalBudget > 0 ? _totalSpent / _totalBudget * 100 : 0).toStringAsFixed(1)}%)\n'
          '✅ Remaining: ₹${_remaining.toStringAsFixed(0)}\n'
          '👤 Spent per person: ₹${_spentPerPerson.toStringAsFixed(0)}\n\n'
          '${_remaining < 0 ? '⚠️ You\'re over budget!' : _remaining < _totalBudget * 0.1 ? '⚠️ Less than 10% budget remaining!' : '✅ Budget is on track!'}';
    }
    if (msg.contains('spent') ||
        msg.contains('paid') ||
        msg.contains('expense')) {
      if (_expenses.isNotEmpty) {
        return '✅ Expense recorded!\n\n'
            '📊 Total spent: ₹${_totalSpent.toStringAsFixed(0)} of ₹${_totalBudget.toStringAsFixed(0)}\n'
            '💰 Remaining: ₹${_remaining.toStringAsFixed(0)}';
      }
    }
    if (msg.contains('split') ||
        msg.contains('divide') ||
        msg.contains('per person')) {
      return '👥 Group Split ($_groupSize people)\n\n'
          '💰 Total budget: ₹${_totalBudget.toStringAsFixed(0)}\n'
          '👤 Per person: ₹${_perPerson.toStringAsFixed(0)}\n'
          '💸 Spent per person: ₹${_spentPerPerson.toStringAsFixed(0)}\n'
          '✅ Remaining per person: ₹${(_remaining / _groupSize).toStringAsFixed(0)}';
    }
    if (msg.contains('tip') ||
        msg.contains('save') ||
        msg.contains('suggest')) {
      return '💡 Smart Budget Tips:\n\n'
          '1. Book accommodations during off-peak hours for 10-20% savings\n'
          '2. Use local transport (auto-rickshaw, metro) instead of cabs\n'
          '3. Eat at local dhabas for authentic food at 50% less\n'
          '4. Book attractions online in advance for discounts\n'
          '5. Keep 10% as emergency reserve\n\n'
          'Want me to analyze your spending pattern?';
    }
    return 'I can help you manage your budget! Try:\n\n'
        '• "Set budget ₹50000 for 3 people"\n'
        '• "Spent ₹5000 on hotel"\n'
        '• "Show budget summary"\n'
        '• "Split expenses per person"\n'
        '• "Give me saving tips"';
  }

  void _addExpenseDialog() {
    String selectedCategory = 'Food & Dining';
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Expense',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: _allocation.keys
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Row(
                            children: [
                              Icon(_categoryIcons[cat],
                                  size: 18, color: _categoryColors[cat]),
                              const SizedBox(width: 8),
                              Text(cat),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (val) =>
                    setDialogState(() => selectedCategory = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text);
                if (amount != null && amount > 0) {
                  setState(() {
                    _expenses.add({
                      'amount': amount,
                      'description': descController.text.isEmpty
                          ? selectedCategory
                          : descController.text,
                      'category': selectedCategory,
                      'date': DateTime.now().toIso8601String(),
                    });
                  });
                  _amountController.clear();
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryColor),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget Manager',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'AI Chat'),
            Tab(icon: Icon(Icons.pie_chart_outline), text: 'Overview'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Expenses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatTab(),
          _buildOverviewTab(),
          _buildExpensesTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 2
          ? FloatingActionButton(
              onPressed: _addExpenseDialog,
              backgroundColor: AppConfig.primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  // ─── AI Chat Tab ───
  Widget _buildChatTab() {
    return Column(
      children: [
        // Budget summary bar
        if (_isBudgetSet)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: AppConfig.primaryGradient,
            ),
            child: Row(
              children: [
                _buildMiniStat('Budget', '₹${_formatAmount(_totalBudget)}'),
                _buildMiniStat('Spent', '₹${_formatAmount(_totalSpent)}'),
                _buildMiniStat('Left', '₹${_formatAmount(_remaining)}'),
                if (_groupSize > 1)
                  _buildMiniStat('Per Head', '₹${_formatAmount(_perPerson)}'),
              ],
            ),
          ),
        // Chat messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _chatMessages.length && _isTyping) {
                return _buildTypingIndicator();
              }
              final msg = _chatMessages[index];
              final isAi = msg['sender'] == 'ai';
              return _buildChatBubble(msg['message']!, isAi);
            },
          ),
        ),
        // Quick action chips
        if (_isBudgetSet)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildQuickChip('📊 Summary', 'Show budget summary'),
                _buildQuickChip('👥 Split', 'Split expenses per person'),
                _buildQuickChip('💡 Tips', 'Give saving tips'),
                _buildQuickChip('🏨 Add Hotel', 'Spent ₹ on hotel'),
                _buildQuickChip('🍜 Add Food', 'Spent ₹ on food'),
              ],
            ),
          ),
        // Chat input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  offset: Offset(0, -2))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: _isBudgetSet
                        ? 'Track expenses, ask for tips...'
                        : 'Set your budget to get started...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: _sendChatMessage,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppConfig.primaryColor,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _sendChatMessage(_chatController.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String message) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: () => _sendChatMessage(message),
        backgroundColor: AppConfig.primaryColor.withValues(alpha: 0.08),
        side: BorderSide(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
      ),
    );
  }

  Widget _buildChatBubble(String message, bool isAi) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : AppConfig.primaryColor,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: isAi ? const Radius.circular(4) : null,
            bottomRight: isAi ? null : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isAi ? AppConfig.textPrimary : Colors.white,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              3,
              (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppConfig.primaryColor.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  )),
        ),
      ),
    );
  }

  // ─── Overview Tab ───
  Widget _buildOverviewTab() {
    if (!_isBudgetSet) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64,
                color: AppConfig.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('No budget set yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppConfig.textSecondary)),
            const SizedBox(height: 8),
            const Text('Go to AI Chat tab to set your budget',
                style: TextStyle(color: AppConfig.textTertiary)),
          ],
        ),
      );
    }

    final utilization =
        _totalBudget > 0 ? (_totalSpent / _totalBudget * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main budget card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppConfig.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: AppConfig.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Budget',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text('${utilization.toStringAsFixed(1)}% used',
                        style: TextStyle(
                            color: utilization > 80
                                ? Colors.redAccent
                                : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('₹${_formatAmount(_totalBudget)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (utilization / 100).clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(utilization > 90
                        ? Colors.redAccent
                        : utilization > 70
                            ? Colors.amber
                            : Colors.greenAccent),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildBudgetStat('Spent', '₹${_formatAmount(_totalSpent)}',
                        Colors.white),
                    _buildBudgetStat(
                        'Remaining',
                        '₹${_formatAmount(_remaining)}',
                        _remaining < 0 ? Colors.redAccent : Colors.greenAccent),
                    if (_groupSize > 1)
                      _buildBudgetStat('Per Person',
                          '₹${_formatAmount(_perPerson)}', Colors.white),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Category breakdown
          const Text('Category Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._allocation.entries.map((entry) {
            final cat = entry.key;
            final allocPercent = entry.value;
            final allocated = _totalBudget * allocPercent / 100;
            final spent = _spentByCategory[cat] ?? 0;
            final catUtil = allocated > 0 ? (spent / allocated * 100) : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_categoryIcons[cat],
                          color: _categoryColors[cat], size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(cat,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14))),
                      Text(
                          '₹${_formatAmount(spent)} / ₹${_formatAmount(allocated)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: catUtil > 100
                                  ? Colors.red
                                  : AppConfig.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (catUtil / 100).clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: (_categoryColors[cat] ?? Colors.grey)
                          .withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(catUtil > 100
                          ? Colors.red
                          : _categoryColors[cat] ?? Colors.grey),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBudgetStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Expenses Tab ───
  Widget _buildExpensesTab() {
    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long,
                size: 64,
                color: AppConfig.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('No expenses yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppConfig.textSecondary)),
            const SizedBox(height: 8),
            const Text('Tap + to add or tell the AI chatbot',
                style: TextStyle(color: AppConfig.textTertiary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expenses.length,
      itemBuilder: (context, index) {
        final e = _expenses[_expenses.length - 1 - index]; // newest first
        final cat = e['category'] as String;
        final date = DateTime.tryParse(e['date'] ?? '');
        final dateStr = date != null
            ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
            : '';

        return Dismissible(
          key: Key('expense_$index'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) =>
              setState(() => _expenses.removeAt(_expenses.length - 1 - index)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: (_categoryColors[cat] ?? Colors.grey)
                    .withValues(alpha: 0.1),
                child: Icon(_categoryIcons[cat] ?? Icons.receipt,
                    color: _categoryColors[cat], size: 20),
              ),
              title: Text(e['description'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('$cat • $dateStr',
                  style: const TextStyle(
                      fontSize: 12, color: AppConfig.textSecondary)),
              trailing: Text('₹${_formatAmount(e['amount'] as double)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppConfig.primaryColor)),
            ),
          ),
        );
      },
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final TripPhotoService _photoService = TripPhotoService();

  @override
  void initState() {
    super.initState();
    _photoService.addListener(_onPhotoUpdate);
  }

  @override
  void dispose() {
    _photoService.removeListener(_onPhotoUpdate);
    super.dispose();
  }

  void _onPhotoUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _capturePhoto() async {
    await _photoService.capturePhoto();
  }

  Future<void> _pickFromGallery() async {
    await _photoService.pickMultiple();
  }

  bool _isLoadingDemo = false;

  Future<void> _loadDemoPhotos() async {
    setState(() => _isLoadingDemo = true);
    await _photoService.loadDemoPhotos();
    setState(() => _isLoadingDemo = false);
  }

  void _playReel() {
    final approved = _photoService.approvedPhotos;
    if (approved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No approved photos yet. Add some travel photos first!')),
      );
      return;
    }
    // Sort by quality score descending for best reel
    approved.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripReelScreen(photos: approved),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final all = _photoService.photos;
    final approved = _photoService.approvedPhotos;
    final rejected = _photoService.rejectedPhotos;
    final pending = _photoService.pendingPhotos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Reel',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (all.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_fill, size: 28),
              tooltip: 'Play Reel',
              onPressed: _playReel,
            ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration:
                const BoxDecoration(gradient: AppConfig.primaryGradient),
            child: Row(
              children: [
                _buildStatChip(Icons.photo_library, '${all.length}', 'Total'),
                _buildStatChip(
                    Icons.check_circle, '${approved.length}', 'Approved'),
                _buildStatChip(Icons.cancel, '${rejected.length}', 'Filtered'),
                _buildStatChip(
                    Icons.hourglass_top, '${pending.length}', 'Analyzing'),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _capturePhoto,
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library, size: 20),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: approved.isEmpty ? null : _playReel,
                    icon: const Icon(Icons.slideshow, size: 20),
                    label: const Text('Play Reel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // AI info card
          if (all.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 64,
                          color: AppConfig.primaryColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      const Text('AI-Powered Trip Reel',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                        'Capture or upload your trip photos. AI will automatically filter out documents, blurry images, and bad photos — keeping only the best travel moments for your highlight reel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppConfig.textSecondary,
                            fontSize: 14,
                            height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isLoadingDemo ? null : _loadDemoPhotos,
                        icon: _isLoadingDemo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_fix_high),
                        label: Text(_isLoadingDemo
                            ? 'Loading demo photos...'
                            : 'Load Demo Reel (India Trip)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Loads 10 sample photos (8 travel + 2 documents)\nAI will approve travel photos & filter out documents',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppConfig.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Photo grid
          if (all.isNotEmpty)
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: all.length,
                itemBuilder: (context, index) {
                  final photo = all[index];
                  return _buildPhotoTile(photo);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(TripPhoto photo) {
    final isApproved = photo.status == PhotoStatus.approved;
    final isRejected = photo.status == PhotoStatus.rejected;
    final isPending = photo.status == PhotoStatus.pending;

    return GestureDetector(
      onTap: () => _showPhotoDetail(photo),
      onLongPress: () => _showPhotoActions(photo),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(photo.bytes, fit: BoxFit.cover),
          ),
          // Status overlay for rejected
          if (isRejected)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: Icon(Icons.block, color: Colors.red, size: 32),
                ),
              ),
            ),
          // Pending spinner
          if (isPending)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                ),
              ),
            ),
          // Status badge
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isApproved
                    ? AppConfig.successColor
                    : isRejected
                        ? AppConfig.errorColor
                        : AppConfig.warningColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isApproved
                    ? Icons.check
                    : isRejected
                        ? Icons.close
                        : Icons.hourglass_top,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
          // Quality score
          if (photo.qualityScore > 0)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${photo.qualityScore.toInt()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  void _showPhotoDetail(TripPhoto photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.memory(photo.bytes,
                  fit: BoxFit.cover, width: double.infinity, height: 300),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo.aiCaption.isNotEmpty)
                    Text(photo.aiCaption,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        photo.status == PhotoStatus.approved
                            ? Icons.check_circle
                            : Icons.cancel,
                        color: photo.status == PhotoStatus.approved
                            ? AppConfig.successColor
                            : AppConfig.errorColor,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        photo.status == PhotoStatus.approved
                            ? 'Approved for Reel'
                            : photo.status == PhotoStatus.rejected
                                ? 'Filtered Out'
                                : 'Analyzing...',
                        style: TextStyle(
                          color: photo.status == PhotoStatus.approved
                              ? AppConfig.successColor
                              : AppConfig.errorColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (photo.qualityScore > 0)
                        Text('Quality: ${photo.qualityScore.toInt()}%',
                            style: const TextStyle(
                                color: AppConfig.textSecondary)),
                    ],
                  ),
                  if (photo.rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Reason: ${photo.rejectionReason}',
                        style: const TextStyle(
                            color: AppConfig.textSecondary, fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (photo.status == PhotoStatus.rejected)
                        TextButton.icon(
                          onPressed: () {
                            _photoService.overrideStatus(
                                photo.id, PhotoStatus.approved);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.add_circle, size: 18),
                          label: const Text('Include in Reel'),
                        ),
                      if (photo.status == PhotoStatus.approved)
                        TextButton.icon(
                          onPressed: () {
                            _photoService.overrideStatus(
                                photo.id, PhotoStatus.rejected);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.remove_circle,
                              size: 18, color: Colors.red),
                          label: const Text('Exclude',
                              style: TextStyle(color: Colors.red)),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoActions(TripPhoto photo) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Material(
        color: Theme.of(ctx).colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Photo'),
                onTap: () {
                  _photoService.removePhoto(photo.id);
                  Navigator.pop(ctx);
                },
              ),
              if (photo.status == PhotoStatus.rejected)
                ListTile(
                  leading: const Icon(Icons.check_circle,
                      color: AppConfig.successColor),
                  title: const Text('Override: Include in Reel'),
                  onTap: () {
                    _photoService.overrideStatus(
                        photo.id, PhotoStatus.approved);
                    Navigator.pop(ctx);
                  },
                ),
              if (photo.status == PhotoStatus.approved)
                ListTile(
                  leading:
                      const Icon(Icons.cancel, color: AppConfig.errorColor),
                  title: const Text('Override: Exclude from Reel'),
                  onTap: () {
                    _photoService.overrideStatus(
                        photo.id, PhotoStatus.rejected);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
