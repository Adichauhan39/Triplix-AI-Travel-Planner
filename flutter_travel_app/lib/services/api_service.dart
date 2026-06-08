import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/hotel.dart';
import '../models/destination.dart';
import '../models/travel_option.dart';
import '../models/booking.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String baseUrl = AppConfig.baseUrl;
  String? _sessionId;

  // Headers
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_sessionId != null) 'Session-Id': _sessionId!,
      };

  // Initialize session
  Future<void> initSession() async {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  // Chat with AI Agent
  Future<Map<String, dynamic>> sendMessage(String message) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl${AppConfig.chatEndpoint}'),
            headers: _headers,
            body: jsonEncode({
              'message': message,
              'session_id': _sessionId,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get Hotels
  Future<List<Hotel>> getHotels({
    String? city,
    double? minPrice,
    double? maxPrice,
    String? type,
    List<String>? amenities,
  }) async {
    try {
      final queryParams = {
        if (city != null) 'city': city,
        if (minPrice != null) 'min_price': minPrice.toString(),
        if (maxPrice != null) 'max_price': maxPrice.toString(),
        if (type != null) 'type': type,
        if (amenities != null) 'amenities': amenities.join(','),
      };

      final uri = Uri.parse('$baseUrl${AppConfig.hotelsEndpoint}')
          .replace(queryParameters: queryParams);

      final response = await http
          .get(uri, headers: _headers)
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body)['hotels'] ?? [];
        return data.map((json) => Hotel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load hotels');
      }
    } catch (e) {
      throw Exception('Error fetching hotels: $e');
    }
  }

  // AI-Powered Hotel Search (Gemini 2.0 Flash)
  Future<Map<String, dynamic>> searchHotelsWithAI({
    required String message,
    required String city,
    required double budget,
    String? roomType,
    List<String>? foodTypes,
    String? ambiance,
    List<String>? extras,
  }) async {
    try {
      // Use port 8001 for the lightweight AI test server
      final aiBaseUrl = AppConfig.baseUrl;

      final response = await http
          .post(
            Uri.parse('$aiBaseUrl/api/hotel/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': message,
              'context': {
                'city': city,
                'budget': budget,
                if (roomType != null) 'room_type': roomType,
                if (foodTypes != null && foodTypes.isNotEmpty)
                  'food_types': foodTypes,
                if (ambiance != null) 'ambiance': ambiance,
                if (extras != null && extras.isNotEmpty) 'extras': extras,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Parse AI response
        if (data['status'] == 'success') {
          final List<Hotel> hotels = (data['hotels'] as List)
              .map((hotelData) => Hotel.fromJson(hotelData))
              .toList();

          return {
            'status': 'success',
            'hotels': hotels,
            'count': data['count'],
            'powered_by': data['powered_by'],
            'overall_advice': data['overall_advice'] ?? data['ai_advice'],
            'location': data['location'],
          };
        } else {
          throw Exception(data['message'] ?? 'AI search failed');
        }
      } else {
        throw Exception('Failed to search hotels: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('AI Hotel Search error: $e');
    }
  }

  // Get Destinations
  Future<List<Destination>> getDestinations({
    String? locationType,
    List<String>? activities,
    String? travelStyle,
  }) async {
    try {
      final queryParams = {
        if (locationType != null) 'location_type': locationType,
        if (activities != null) 'activities': activities.join(','),
        if (travelStyle != null) 'travel_style': travelStyle,
      };

      final uri = Uri.parse('$baseUrl${AppConfig.destinationsEndpoint}')
          .replace(queryParameters: queryParams);

      final response = await http
          .get(uri, headers: _headers)
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data =
            jsonDecode(response.body)['destinations'] ?? [];
        return data.map((json) => Destination.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load destinations');
      }
    } catch (e) {
      throw Exception('Error fetching destinations: $e');
    }
  }

  // Get Travel Options
  Future<List<TravelOption>> getTravelOptions({
    required String origin,
    required String destination,
    required DateTime date,
    String? mode,
    String? travelClass,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl${AppConfig.travelEndpoint}'),
            headers: _headers,
            body: jsonEncode({
              'origin': origin,
              'destination': destination,
              'date': date.toIso8601String(),
              'mode': mode,
              'class': travelClass,
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data =
            jsonDecode(response.body)['travel_options'] ?? [];
        return data.map((json) => TravelOption.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load travel options');
      }
    } catch (e) {
      throw Exception('Error fetching travel options: $e');
    }
  }

  // Swipe Recommendations
  Future<Map<String, dynamic>> getSwipeRecommendations({
    required String type, // hotel, travel, destination, attraction
    Map<String, dynamic>? preferences,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl${AppConfig.swipeEndpoint}/recommendations'),
            headers: _headers,
            body: jsonEncode({
              'type': type,
              'preferences': preferences,
              'session_id': _sessionId,
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load recommendations');
      }
    } catch (e) {
      throw Exception('Error fetching recommendations: $e');
    }
  }

  // Handle Swipe Action
  Future<Map<String, dynamic>> handleSwipe({
    required String cardId,
    required String action, // like, dislike
    required String type,
    Map<String, dynamic>? cardData,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl${AppConfig.swipeEndpoint}/action'),
            headers: _headers,
            body: jsonEncode({
              'card_id': cardId,
              'action': action,
              'type': type,
              'card_data': cardData,
              'session_id': _sessionId,
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to process swipe');
      }
    } catch (e) {
      throw Exception('Error handling swipe: $e');
    }
  }

  // Create Booking
  Future<Booking> createBooking({
    required String type,
    required Map<String, dynamic> details,
    required DateTime checkInDate,
    DateTime? checkOutDate,
    required double totalPrice,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/booking'),
            headers: _headers,
            body: jsonEncode({
              'type': type,
              'details': details,
              'check_in_date': checkInDate.toIso8601String(),
              'check_out_date': checkOutDate?.toIso8601String(),
              'total_price': totalPrice,
              'session_id': _sessionId,
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Booking.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to create booking');
      }
    } catch (e) {
      throw Exception('Error creating booking: $e');
    }
  }

  // Get Bookings
  Future<List<Booking>> getBookings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/bookings'),
            headers: _headers,
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body)['bookings'] ?? [];
        return data.map((json) => Booking.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load bookings');
      }
    } catch (e) {
      throw Exception('Error fetching bookings: $e');
    }
  }

  // Get Budget Info
  Future<BudgetTracker> getBudgetInfo() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl${AppConfig.budgetEndpoint}'),
            headers: _headers,
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return BudgetTracker.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load budget info');
      }
    } catch (e) {
      throw Exception('Error fetching budget: $e');
    }
  }

  // Add Expense
  Future<void> addExpense({
    required String category,
    required double amount,
    required String description,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl${AppConfig.budgetEndpoint}/expense'),
            headers: _headers,
            body: jsonEncode({
              'category': category,
              'amount': amount,
              'description': description,
              'session_id': _sessionId,
            }),
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to add expense');
      }
    } catch (e) {
      throw Exception('Error adding expense: $e');
    }
  }

  // Get Preference Insights
  Future<Map<String, dynamic>> getPreferenceInsights() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl${AppConfig.swipeEndpoint}/insights'),
            headers: _headers,
          )
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load insights');
      }
    } catch (e) {
      throw Exception('Error fetching insights: $e');
    }
  }
}
