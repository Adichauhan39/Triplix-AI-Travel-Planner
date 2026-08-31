import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Service to communicate with Python ADK Backend
/// Integrates Flutter frontend with Python Google ADK multi-agent system
class PythonADKService {
  // Python FastAPI backend URL
  static const String _baseUrl = AppConfig.baseUrl;

  // API endpoints
  static const String _agentEndpoint = '/api/agent';
  static const String _managerEndpoint = '/api/manager';
  static const String _replanEndpoint = '/api/itinerary/replan';
  static const String _hotelEndpoint = '/api/hotel/search';
  static const String _flightEndpoint = '/api/flight/search';

  /// Aviasales-backed flight search. Note the plural path — distinct from
  /// _flightEndpoint above, which points at an agent-style route.
  static const String _flightFaresEndpoint = '/api/flights/search';
  static const String _travelEndpoint = '/api/travel/search';
  static const String _destinationEndpoint = '/api/destination/info';

  /// Check if Python backend is running
  Future<bool> isBackendAvailable() async {
    try {
      final response = await http
          .get(
            Uri.parse(_baseUrl),
          )
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      print('Python backend not available: $e');
      return false;
    }
  }

  /// Send request to swipe page
  Future<Map<String, dynamic>> sendToSwipe({
    required String city,
    String category = 'attractions', // attractions, hotels, restaurants
  }) async {
    return sendToManager(
      message: 'Show me swipeable $category in $city',
      context: {'city': city, 'category': category},
      page: 'swipe',
    );
  }

  /// Send request to bookings page
  Future<Map<String, dynamic>> sendToBookings({
    String action = 'view', // view, create, modify, cancel
    Map<String, dynamic>? bookingDetails,
  }) async {
    String message = 'Show me my bookings';
    if (action == 'create' && bookingDetails != null) {
      message = 'Create a booking with details: ${json.encode(bookingDetails)}';
    }

    return sendToManager(
      message: message,
      context: {'action': action, 'booking_details': bookingDetails},
      page: 'bookings',
    );
  }

  /// Send request to budget page
  Future<Map<String, dynamic>> sendToBudget({
    double? totalBudget,
    int? numPeople,
    String action = 'view', // view, set, track, split
  }) async {
    String message = 'Show me budget information';
    if (action == 'set' && totalBudget != null && numPeople != null) {
      message = 'Set budget of ₹$totalBudget for $numPeople people';
    }

    return sendToManager(
      message: message,
      context: {
        'action': action,
        'total_budget': totalBudget,
        'num_people': numPeople
      },
      page: 'budget',
    );
  }

  /// Send request to profile page
  Future<Map<String, dynamic>> sendToProfile({
    String action = 'view', // view, update, history
    Map<String, dynamic>? preferences,
  }) async {
    String message = 'Show my profile information';
    if (action == 'update' && preferences != null) {
      message = 'Update my preferences: ${json.encode(preferences)}';
    }

    return sendToManager(
      message: message,
      context: {'action': action, 'preferences': preferences},
      page: 'profile',
    );
  }

  /// Send request to ADK agent for general conversation (not itinerary generation)
  Future<Map<String, dynamic>> sendToAgent({
    required String message,
    Map<String, dynamic>? context,
    String page = 'home',
  }) async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📤 [PythonADK] Sending AGENT request to Python backend');
      print('   URL: $_baseUrl$_agentEndpoint');
      print('   Message: "$message"');
      print('   Page: $page');

      final requestBody = {
        'message': message,
        'context': context ?? {},
        'page': page,
      };

      final response = await http
          .post(
        Uri.parse('$_baseUrl$_agentEndpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      print('📥 [PythonADK] Response: ${response.statusCode}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'response': data['response'],
          'agent': data['agent'],
          'data': data['data'],
          'suggestions': data['suggestions'],
          'show_suggestions': data['show_suggestions'],
          'source': 'python_adk',
        };
      } else {
        return {
          'success': false,
          'error': 'Backend error: ${response.statusCode}',
          'response': 'Sorry, I encountered an error. Please try again.',
          'source': 'python_adk',
        };
      }
    } catch (e) {
      print('❌ [PythonADK] Error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'response': 'I\'m having trouble connecting. Error: $e',
        'source': 'python_adk',
      };
    }
  }

  /// Send request to ADK manager agent with page context
  Future<Map<String, dynamic>> sendToManager({
    required String message,
    Map<String, dynamic>? context,
    String page = 'home', // home, swipe, bookings, budget, profile
  }) async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📤 [PythonADK] Sending MANAGER request to Python backend');
      print('   URL: $_baseUrl$_managerEndpoint');
      print('   Message: "$message"');
      print('   Page: $page');
      print('   Context keys: ${context?.keys.toList() ?? []}');

      final requestBody = {
        'message': message,
        'context': context ?? {},
        'page': page,
      };

      print(
          '   Request body: ${json.encode(requestBody).substring(0, 200)}...');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final response = await http
          .post(
        Uri.parse(
            '$_baseUrl$_managerEndpoint'), // Changed from _agentEndpoint to _managerEndpoint
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      )
          .timeout(
        const Duration(
            seconds:
                120), // Increased to 120 seconds for AI itinerary generation
        onTimeout: () {
          print('⏰ [PythonADK] Request timed out after 120 seconds');
          throw Exception(
              'Request timeout - AI is taking longer than expected');
        },
      );

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📥 [PythonADK] Response received');
      print('   Status code: ${response.statusCode}');
      print('   Response length: ${response.body.length} bytes');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ [PythonADK] Success! Response keys: ${data.keys.toList()}');
        return {
          'success': true,
          'response': data['response'],
          'agent': data['agent'],
          'data': data['data'],
          'itinerary': data['itinerary'],
          'replan': data['replan'],
          'is_dynamic_replan': data['is_dynamic_replan'],
          'page': data['page'],
          'source': 'python_adk',
        };
      } else {
        print('❌ [PythonADK] Backend error: ${response.statusCode}');
        print('   Body: ${response.body}');
        return {
          'success': false,
          'error': 'Backend error: ${response.statusCode}',
          'response': 'Sorry, I encountered an error. Please try again.',
          'source': 'python_adk',
        };
      }
    } catch (e, stackTrace) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('❌ [PythonADK] Error calling Python backend:');
      print('   Error type: ${e.runtimeType}');
      print('   Error: $e');
      print('   Stack trace:');
      print(stackTrace.toString().split('\n').take(5).join('\n'));
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return {
        'success': false,
        'error': 'Failed to connect to Python backend: ${e.toString()}',
        'response':
            'I\'m having trouble connecting to my AI brain. Error: ${e.toString()}',
        'source': 'python_adk',
      };
    }
  }

  /// Explicitly trigger dynamic itinerary replanning based on weather/disruptions.
  Future<Map<String, dynamic>> replanItinerary({
    required String message,
    Map<String, dynamic>? context,
  }) async {
    try {
      final requestBody = {
        'message': message,
        'context': context ?? {},
        'page': 'home',
      };

      final response = await http
          .post(
            Uri.parse('$_baseUrl$_replanEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'] ?? true,
          'response': data['response'],
          'agent': data['agent'],
          'data': data['data'],
          'itinerary': data['itinerary'],
          'replan': data['replan'],
          'source': 'python_adk',
        };
      }

      return {
        'success': false,
        'error': 'Backend error: ${response.statusCode}',
        'response': 'Sorry, I could not re-plan the itinerary right now.',
        'source': 'python_adk',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'response': 'I\'m having trouble re-planning your itinerary. Error: $e',
        'source': 'python_adk',
      };
    }
  }

  /// Search hotels via Python ADK hotel_booking agent
  Future<Map<String, dynamic>> searchHotels({
    required String city,
    double? minPrice,
    double? maxPrice,
    String? roomType,
    String? ambiance,
    List<String>? amenities,
    String? specialRequest,
  }) async {
    try {
      print(
          '🔍 HOTEL SEARCH: Always using Manager Agent endpoint with intelligent routing');
      print('   📊 Backend will decide: CSV (free) or AI agent (when needed)');

      // Build natural language message
      final messageParts = <String>[];
      messageParts.add('Find hotels in $city');

      if (maxPrice != null) {
        messageParts.add('under ₹${maxPrice.toStringAsFixed(0)}');
      }
      if (roomType != null && roomType.isNotEmpty) {
        messageParts.add('with $roomType room');
      }
      if (ambiance != null && ambiance.isNotEmpty) {
        messageParts.add('$ambiance ambiance');
      }
      if (amenities != null && amenities.isNotEmpty) {
        messageParts.add('with ${amenities.join(", ")}');
      }
      if (specialRequest != null && specialRequest.isNotEmpty) {
        messageParts.add('Special: $specialRequest');
      }

      final message = messageParts.join('. ');

      print('   📨 Query: "$message"');
      print('   📡 POST request to: $_baseUrl$_hotelEndpoint');

      final response = await http.post(
        Uri.parse('$_baseUrl$_hotelEndpoint'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: json.encode({
          'message': message,
          'context': {
            'city': city,
            'budget':
                maxPrice ?? 25000, // Backend expects 'budget', not 'max_price'
            'min_price': minPrice ?? 0,
            'max_price': maxPrice ?? 100000,
            'room_type': roomType,
            'ambiance': ambiance,
            'amenities': amenities,
          },
        }),
      );

      print('   📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hotelCount = (data['hotels'] as List?)?.length ?? 0;
        final aiUsed = data['ai_used'] ?? false;

        if (aiUsed) {
          print('✅ SEARCH COMPLETE: $hotelCount hotels via Manager Agent (AI)');
          print('   💰 Cost: AI tokens used');
          print('   🤖 Reason: ${data['reason_for_ai']}');
        } else {
          print('✅ SEARCH COMPLETE: $hotelCount hotels via CSV database');
          print('   💰 Cost: Free (no AI used)');
        }

        // Limit hotels to maximum 5
        final allHotels = (data['hotels'] as List?) ?? [];
        final limitedHotels = allHotels.take(5).toList();

        return {
          'success': true,
          'response': data['overall_advice'] ?? 'Hotels found successfully',
          'agent': aiUsed ? 'web_hotel_search (Manager Agent)' : 'csv_database',
          'ai_used': aiUsed,
          'data': {
            'hotels': limitedHotels,
          },
          'source': 'python_adk',
        };
      } else {
        print('❌ Search failed with status ${response.statusCode}');
        return {
          'success': false,
          'error': 'Hotel search failed: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Error in search: ${e.toString()}');
      return {
        'success': false,
        'error': 'Error: ${e.toString()}',
      };
    }
  }

  /// Scheduled flights on a route, for identifying a flight already booked.
  ///
  /// Backed by Gemini with Google Search grounding, so the flight numbers come
  /// from booking sites rather than the model's memory — ungrounded replies are
  /// discarded server-side. Used only when Aviasales has no cached fares for
  /// the date, which on regional Indian routes is most of the time.
  ///
  /// These are recognition aids, not availability: never show them as bookable
  /// or priced. Returns [] on any failure.
  Future<List<Map<String, dynamic>>> flightSchedule({
    required String originIata,
    required String destinationIata,
    required String isoDate,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/flights/schedule').replace(
        queryParameters: {
          'origin': originIata,
          'destination': destinationIata,
          'date': isoDate,
        },
      );
      // 90s, not 50. The server now runs one grounded lookup per airline, so
      // a busy trunk route is far slower than a regional one: BOM-DEL measured
      // 31s and returned 59 flights, where BLR-RPR took 7s. The server caps
      // each airline at 45s, so 50s here could time out a request that was
      // about to succeed — and the user would see "no flights" for a route
      // that has plenty. The wait only happens once per route and date;
      // afterwards the server answers from cache.
      final response =
          await http.get(uri).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        debugPrint('flightSchedule: HTTP ${response.statusCode} for $uri');
        return const [];
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      return ((data['flights'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      // Was swallowed silently, which made a timeout indistinguishable from a
      // route with no flights.
      debugPrint('flightSchedule failed: $e');
      return const [];
    }
  }

  /// Real hotel names matching a partial (and possibly misspelled) query,
  /// for the "which hotel did you book?" confirmation.
  ///
  /// Backed by Google Places, not a language model — every suggestion has to
  /// be a property that actually exists, and Places' fuzzy matching already
  /// handles typos ("hotal citi lite" finds "Hotel City Lite").
  ///
  /// Returns `null` when the lookup itself failed (server down, timeout, bad
  /// status) and an empty list when it succeeded but matched nothing. Callers
  /// must keep these apart: telling someone to "check the spelling" because
  /// our own request failed is worse than saying nothing.
  /// The plan as a shareable file: 'pdf' or 'mp4'.
  ///
  /// Returns the raw bytes, or null on failure so the caller can say so
  /// rather than sharing an empty file. Generous timeout because the video
  /// path downloads a photo per place and then runs ffmpeg.
  Future<List<int>?> exportPlan({
    required List<Map<String, dynamic>> days,
    required String format,
    String destination = '',
    bool includePhotos = true,
  }) async {
    if (days.isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/itinerary/export'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'days': days,
              'format': format,
              'destination': destination,
              'include_photos': includePhotos,
            }),
          )
          .timeout(const Duration(seconds: 180));
      if (response.statusCode != 200) {
        debugPrint('exportPlan: HTTP ${response.statusCode}');
        return null;
      }
      // An error comes back as JSON rather than a file, so a body that
      // starts with '{' is a failure however healthy the status code looks.
      if (response.bodyBytes.isNotEmpty && response.bodyBytes.first == 0x7B) {
        debugPrint('exportPlan: server returned an error payload');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('exportPlan failed: $e');
      return null;
    }
  }

  /// Queues an export and returns its job id straight away.
  ///
  /// The render takes one to three and a half minutes, which is longer than
  /// [exportPlan] will wait: a five-day film could not be exported at all,
  /// because the request timed out at 180s while the server was still working.
  /// Polling replaces one long request with many short ones, and gives us a
  /// figure to show while it runs.
  Future<Map<String, dynamic>?> startExport({
    required List<Map<String, dynamic>> days,
    required String format,
    String destination = '',
    bool includePhotos = true,
  }) async {
    if (days.isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/itinerary/export'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'days': days,
              'format': format,
              'destination': destination,
              'include_photos': includePhotos,
              'mode': 'async',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('startExport: HTTP ${response.statusCode}');
        return null;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['status'] != 'success' || body['job_id'] == null) {
        debugPrint('startExport: ${body['message']}');
        return null;
      }
      return body;
    } catch (e) {
      debugPrint('startExport failed: $e');
      return null;
    }
  }

  /// How far along a queued export is: state, progress (0–1) and a stage line.
  Future<Map<String, dynamic>?> exportStatus(String jobId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/itinerary/export/status/$jobId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['status'] == 'success' ? body : null;
    } catch (e) {
      debugPrint('exportStatus failed: $e');
      return null;
    }
  }

  /// The finished file for a job, or null if it is not ready.
  Future<List<int>?> fetchExport(String jobId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/itinerary/export/file/$jobId'))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      // An error comes back as JSON rather than a file, so a body that starts
      // with '{' is a failure however healthy the status code looks.
      if (response.bodyBytes.isNotEmpty && response.bodyBytes.first == 0x7B) {
        debugPrint('fetchExport: server returned an error payload');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('fetchExport failed: $e');
      return null;
    }
  }

  /// The whole trip on one map, pinned and coloured by day.
  ///
  /// Returns the image itself rather than a URL: the Maps key stays on the
  /// server, so the browser is handed a picture and never something it could
  /// be billed for.
  Future<List<int>?> tripMap(List<Map<String, dynamic>> days) async {
    if (days.isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/trip/map'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'days': days}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      // An error comes back as JSON rather than an image.
      if (response.bodyBytes.isNotEmpty && response.bodyBytes.first == 0x7B) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('tripMap failed: $e');
      return null;
    }
  }

  /// How far a typed place is from the city being visited, in km.
  ///
  /// Returns null when neither can be located, which is not the same as
  /// "close by" -- the caller has to keep those apart.
  Future<double?> distanceFromCity({
    required String text,
    required String city,
  }) async {
    if (text.trim().isEmpty || city.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/place/check'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'text': text, 'city': city}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['found'] != true) return null;
      return (body['km'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('distanceFromCity failed: $e');
      return null;
    }
  }

  /// Pulls a departure out of something the traveller typed.
  ///
  /// Returns null when the message is not about leaving, which is the common
  /// case -- the prompt box is mostly used for "move the palace to Day 2".
  Future<Map<String, dynamic>?> extractDeparture({
    required String text,
    String city = '',
  }) async {
    if (text.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/trip/departure'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'text': text, 'city': city}),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final departure = body['departure'];
      return departure is Map<String, dynamic> ? departure : null;
    } catch (e) {
      debugPrint('extractDeparture failed: $e');
      return null;
    }
  }

  /// Answers a question about one place.
  ///
  /// [facts] should carry what we already know about it, so the common
  /// questions are answered from Google Places data rather than from the
  /// model's memory. Returns null on failure so the caller can say so
  /// instead of showing a blank answer.
  Future<String?> askAboutPlace({
    required String place,
    required String question,
    String city = '',
    Map<String, dynamic> facts = const {},
  }) async {
    if (question.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/places/ask'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'place': place,
              'city': city,
              'question': question.trim(),
              'facts': facts,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint('askAboutPlace: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      final answer = (data['answer'] ?? '').toString().trim();
      return answer.isEmpty ? null : answer;
    } catch (e) {
      debugPrint('askAboutPlace failed: $e');
      return null;
    }
  }

  /// A running order for each day, keyed by date.
  ///
  /// The days sent should carry any fixed points we know -- a confirmed
  /// flight time, the distance from the airport -- and each place's hours for
  /// that date, so the reply is arranged around facts rather than invented
  /// around nothing.
  Future<Map<String, List<String>>?> daySchedules({
    required List<Map<String, dynamic>> days,
    String destination = '',
  }) async {
    if (days.isEmpty) return const {};
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/itinerary/schedule'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'days': days, 'destination': destination}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint('daySchedules: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      final raw = (data['notes'] as Map?) ?? const {};
      return raw.map((key, value) => MapEntry(
            key.toString(),
            (value as List).map((e) => e.toString()).toList(),
          ));
    } catch (e) {
      debugPrint('daySchedules failed: $e');
      return null;
    }
  }

  /// Real places in [city] that are not already in the plan.
  ///
  /// [interests] steers the results toward what the user actually likes, and
  /// [exclude] carries the names already on the itinerary so nothing is
  /// offered twice. Returns null on failure so the caller can say so.
  Future<List<Map<String, dynamic>>?> discoverPlaces({
    required String city,
    List<String> interests = const [],
    List<String> exclude = const [],
    int limit = 3,
  }) async {
    if (city.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/places/discover'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'city': city,
              'interests': interests,
              'exclude': exclude,
              'limit': limit,
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        debugPrint('discoverPlaces: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      return ((data['places'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('discoverPlaces failed: $e');
      return null;
    }
  }

  /// A photo, rating and today's hours for several places at once.
  ///
  /// One request for a whole day, so the itinerary can show what each place is
  /// without the user opening them one by one. Cheaper than [placeDetails] per
  /// item: a single search per place rather than the two calls reviews need.
  Future<Map<String, Map<String, dynamic>>?> placeSummaries({
    required String city,
    required List<String> names,
  }) async {
    if (names.isEmpty) return const {};
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/places/summaries'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'city': city, 'names': names}),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        debugPrint('placeSummaries: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final raw = (data['summaries'] as Map?) ?? const {};
      return raw.map((key, value) => MapEntry(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ));
    } catch (e) {
      debugPrint('placeSummaries failed: $e');
      return null;
    }
  }

  /// Everything Google knows about a place: photos, rating, reviews, hours,
  /// coordinates and a Maps link.
  ///
  /// Returns null when the lookup fails, so the caller can say so rather than
  /// showing an empty sheet that looks like the place has no information.
  Future<Map<String, dynamic>?> placeDetails({
    required String name,
    String city = '',
  }) async {
    if (name.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/places/details'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'name': name, 'city': city}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('placeDetails: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      return data['place'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('placeDetails failed: $e');
      return null;
    }
  }

  /// Applies a typed request to a day-by-day plan, returning the new days.
  ///
  /// Returns null on failure so the caller can keep showing the plan the user
  /// already has rather than replacing it with nothing.
  Future<List<Map<String, dynamic>>?> adjustPlan({
    required List<Map<String, dynamic>> days,
    required String request,
    String destination = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/itinerary/adjust'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'days': days,
              'request': request,
              'destination': destination,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint('adjustPlan: HTTP ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') {
        debugPrint('adjustPlan: ${data['message']}');
        return null;
      }
      return ((data['days'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('adjustPlan failed: $e');
      return null;
    }
  }

  /// Airports whose city, name or code matches [query].
  ///
  /// Backed by the cached airport dataset rather than a model or Places, so it
  /// is a local lookup on the server and fast enough for every keystroke.
  /// Returns null on failure so the caller can tell a broken lookup from a
  /// city that genuinely has no airport.
  Future<List<AirportOption>?> searchAirports(String query) async {
    if (query.trim().length < 2) return const [];
    try {
      final uri = Uri.parse('$_baseUrl/api/airport/search')
          .replace(queryParameters: {'q': query.trim(), 'limit': '6'});
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('searchAirports: HTTP ${response.statusCode} for $uri');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      return ((data['airports'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((a) => AirportOption(
                code: (a['code'] ?? '').toString(),
                name: (a['name'] ?? '').toString(),
                city: (a['city'] ?? '').toString(),
              ))
          .where((a) => a.code.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('searchAirports failed: $e');
      return null;
    }
  }

  /// The bookable airport for [city], substituting the nearest one when the
  /// city has no airport of its own — Bilaspur resolves to Raipur, 108km away.
  ///
  /// Needed because AffiliateLinks.iataCodeFor only knows the 37 cities in the
  /// app's own picker, so anywhere else produced no code and sent the user to
  /// the Aviasales homepage with an empty search. The server has the full
  /// airport dataset, so it answers this properly.
  ///
  /// Returns null if the lookup fails and an empty-IATA result if the city
  /// can't be resolved at all; callers fall back to their built-in map.
  Future<AirportResolution?> resolveAirport(String city) async {
    if (city.trim().isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl/api/airport/resolve')
          .replace(queryParameters: {'city': city});
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('resolveAirport: HTTP ${response.statusCode} for $uri');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['resolved'] != true) return null;
      return AirportResolution(
        iata: (data['iata'] ?? '').toString(),
        airportName: (data['airport_name'] ?? '').toString(),
        city: (data['city'] ?? '').toString(),
        substituted: data['substituted'] == true,
        distanceKm: (data['distance_km'] as num?)?.round() ?? 0,
      );
    } catch (e) {
      debugPrint('resolveAirport failed: $e');
      return null;
    }
  }

  Future<List<Map<String, String>>?> searchHotelNames({
    required String query,
    String city = '',
    int limit = 6,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/places/hotels').replace(
        queryParameters: {
          'query': query,
          if (city.isNotEmpty) 'city': city,
          'limit': '$limit',
        },
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('searchHotelNames: HTTP ${response.statusCode} for $uri');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      return ((data['hotels'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((h) => {
                'name': (h['name'] ?? '').toString(),
                'address': (h['address'] ?? '').toString(),
              })
          .where((h) => h['name']!.isNotEmpty)
          .toList();
    } catch (e) {
      // Logged rather than swallowed — this failing silently is what made a
      // broken lookup look like a spelling mistake.
      debugPrint('searchHotelNames failed: $e');
      return null;
    }
  }

  /// Real bookable fares from Aviasales, via the backend's Travelpayouts
  /// integration.
  ///
  /// The backend serves Aviasales results only — it will not substitute CSV
  /// or AI-generated flights — so an empty list genuinely means "no fare
  /// available for this route and date", not "the search failed". Callers
  /// should show an empty state rather than retrying against another source.
  ///
  /// Returns `{success, flights, message}`. Each flight carries a
  /// `booking_url` deep link to that specific fare on Aviasales.
  Future<Map<String, dynamic>> searchFlightFares({
    required String from,
    required String to,
    required DateTime departureDate,
    DateTime? returnDate,
    int passengers = 1,
    String travelClass = 'economy',
  }) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_flightFaresEndpoint'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'from_city': from,
              'to_city': to,
              'departure_date': iso(departureDate),
              if (returnDate != null) 'return_date': iso(returnDate),
              'passengers': passengers,
              'flight_class': travelClass,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return {
          'success': false,
          'flights': <Map<String, dynamic>>[],
          'message': 'Search failed (${response.statusCode}). Please try again.',
        };
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? const [];
      final flights = results.cast<Map<String, dynamic>>();

      // Which airport each city resolved to. Present on the top-level response
      // when there are no fares, and on each result when there are — read both
      // so the caller can explain a substituted airport either way.
      Map<String, dynamic>? airportInfo(String key) {
        final top = data[key];
        if (top is Map<String, dynamic>) return top;
        if (flights.isNotEmpty && flights.first[key] is Map<String, dynamic>) {
          return flights.first[key] as Map<String, dynamic>;
        }
        return null;
      }

      return {
        'success': true,
        'flights': flights,
        'message': data['message'] ?? '',
        'originAirport': airportInfo('origin_airport_info'),
        'destinationAirport': airportInfo('destination_airport_info'),
      };
    } catch (e) {
      return {
        'success': false,
        'flights': <Map<String, dynamic>>[],
        'message': 'Could not reach the flight service. Check your connection.',
      };
    }
  }

  /// Search flights via Python ADK travel_booking agent
  Future<Map<String, dynamic>> searchFlights({
    required String from,
    required String to,
    DateTime? departureDate,
    String? travelClass,
  }) async {
    try {
      final message = 'Find flights from $from to $to';

      final response = await http.post(
        Uri.parse('$_baseUrl$_flightEndpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': message,
          'context': {
            'from': from,
            'to': to,
            'departure_date': departureDate?.toIso8601String(),
            'travel_class': travelClass,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Limit flights to maximum 5
        final allFlights = (data['flights'] as List?) ?? [];
        final limitedFlights = allFlights.take(5).toList();

        // Also limit trains to maximum 5 if present
        final allTrains = (data['trains'] as List?) ?? [];
        final limitedTrains = allTrains.take(5).toList();

        return {
          'success': true,
          'response': data['response'],
          'agent': 'travel_booking',
          'flights': limitedFlights,
          'trains': limitedTrains,
          'source': 'python_adk',
        };
      } else {
        return {
          'success': false,
          'error': 'Flight search failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get destination info via Python ADK destination_info agent
  Future<Map<String, dynamic>> getDestinationInfo({
    required String city,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$_destinationEndpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': city,
          'context': {'city': city},
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Limit destinations to maximum 10
        final allDestinations = (data['destinations'] as List?) ?? [];
        final limitedDestinations = allDestinations.take(10).toList();

        return {
          'success': true,
          'response': data['response'],
          'agent': 'destination_info',
          'destinations': limitedDestinations,
          'source': 'python_adk',
        };
      } else {
        return {
          'success': false,
          'error': 'Destination info failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<List<Map<String, String>>> getDestinationSuggestions({
    required String query,
    int limit = 8,
    bool preferPlaces = false,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/destination/suggestions').replace(
        queryParameters: {
          'query': query,
          'limit': '$limit',
          'prefer_places': preferPlaces.toString(),
        },
      );

      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json'
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final data = json.decode(response.body);
      final suggestions = List<Map<String, dynamic>>.from(
        data['suggestions'] ?? const [],
      );

      return suggestions
          .map(
            (suggestion) => {
              'city': (suggestion['city'] ?? '').toString(),
              'country': (suggestion['country'] ?? '').toString(),
              'description': (suggestion['description'] ?? '').toString(),
              'famous_for': (suggestion['famous_for'] ?? '').toString(),
            },
          )
          .toList();
    } catch (e) {
      print('Destination suggestions error: $e');
      return [];
    }
  }

  /// Get AI-generated destination-specific interests and activities
  Future<Map<String, dynamic>> getDestinationInterests({
    required String city,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/destination/interests'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'city': city}),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['status'] == 'success',
          'city': data['city'] ?? city,
          'categories': data['categories'] ?? [],
        };
      } else {
        return {'success': false, 'categories': []};
      }
    } catch (e) {
      print('Destination interests error: $e');
      return {'success': false, 'categories': []};
    }
  }

  /// Batch-fetches one real photo per activity keyword for a city (e.g.
  /// "Fort" -> a real fort photo), so onboarding's interest chips can show
  /// images instead of plain text. Returns an empty map on any failure —
  /// callers should treat that as "no images available" rather than an
  /// error, since the chips still work fine as plain text without images.
  Future<Map<String, String>> getActivityImages({
    required String city,
    required List<String> activities,
  }) async {
    if (activities.isEmpty) return {};
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/destination/activity-images'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'city': city, 'activities': activities}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['images'] is Map) {
          return Map<String, String>.from(data['images']);
        }
      }
      return {};
    } catch (e) {
      print('Activity images error: $e');
      return {};
    }
  }

  /// Check if a city name is ambiguous and return disambiguation options
  Future<Map<String, dynamic>> disambiguateCity({
    required String city,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/destination/disambiguate'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'city': city}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['status'] == 'success',
          'ambiguous': data['ambiguous'] ?? false,
          'options': data['options'] ?? [],
        };
      } else {
        return {'success': false, 'ambiguous': false, 'options': []};
      }
    } catch (e) {
      print('Disambiguate city error: $e');
      return {'success': false, 'ambiguous': false, 'options': []};
    }
  }

  /// Get seasonal activities and attractions for a destination
  Future<Map<String, dynamic>> getSeasonalActivities({
    required String city,
    String? travelDate,
    int days = 3,
    int count = 10,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/activities/seasonal'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'city': city,
              'travel_date': travelDate ?? '',
              'days': days,
              'count': count,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['status'] == 'success',
          'activities': data['activities'] ?? [],
          'month': data['month'] ?? '',
          'season_info': data['season_info'] ?? '',
        };
      } else {
        return {'success': false, 'activities': []};
      }
    } catch (e) {
      print('Seasonal activities error: $e');
      return {'success': false, 'activities': []};
    }
  }

  /// Search travel options (flights, trains, buses, car rentals, taxis, bikes)
  Future<Map<String, dynamic>> searchTravel(
      Map<String, dynamic> requestData) async {
    try {
      print(
          '🚗 TRAVEL SEARCH: ${requestData['mode']} from ${requestData['from_city']}');

      final response = await http.post(
        Uri.parse('$_baseUrl$_travelEndpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final resultCount = (data['results'] as List?)?.length ?? 0;
        final aiUsed = data['ai_used'] ?? false;

        if (aiUsed) {
          print(
              '✅ SEARCH COMPLETE: $resultCount ${requestData['mode']} options via AI');
        } else {
          print(
              '✅ SEARCH COMPLETE: $resultCount ${requestData['mode']} options via CSV');
        }

        return {
          'success': true,
          'status': data['status'] ?? 'success',
          'powered_by': data['powered_by'] ?? 'Unknown',
          'ai_used': aiUsed,
          'results': data['results'] ?? [],
          'count': resultCount,
          'source': 'python_adk',
        };
      } else {
        print('❌ Travel search failed with status ${response.statusCode}');
        return {
          'success': false,
          'error': 'Travel search failed: ${response.statusCode}',
          'status': 'error',
        };
      }
    } catch (e) {
      print('❌ Error in travel search: ${e.toString()}');
      return {
        'success': false,
        'error': 'Error: ${e.toString()}',
        'status': 'error',
      };
    }
  }
}

/// Which airport a city's flights actually depart from.
///
/// [substituted] is the part that matters to the user: when true the city has
/// no airport of its own and [iata] belongs to one [distanceKm] away, which
/// they should be told before they book rather than discover on the day.
class AirportResolution {
  const AirportResolution({
    required this.iata,
    required this.airportName,
    required this.substituted,
    required this.distanceKm,
    this.city = '',
  });

  final String iata;
  final String airportName;
  final bool substituted;
  final int distanceKm;

  /// The airport's own city, which is not the city that was searched when
  /// [substituted] is true: Bhilai resolves to RPR, whose city is Raipur.
  final String city;
}

/// One airport offered in the From/To pickers.
///
/// [city] is what the user is looking for; [name] and [code] disambiguate the
/// cities that have two, like Mumbai's BOM and NMI.
class AirportOption {
  const AirportOption({
    required this.code,
    required this.name,
    required this.city,
  });

  final String code;
  final String name;
  final String city;

  /// What goes in the field once picked, e.g. "Mumbai (BOM)".
  String get label => city.isEmpty ? code : '$city ($code)';
}
