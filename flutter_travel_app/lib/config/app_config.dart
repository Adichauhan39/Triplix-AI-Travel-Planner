import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // API Configuration
  // Default points to local backend on port 8001 for development.
  // Override for production builds with:
  //   --dart-define=API_BASE_URL=https://triplix-server-lzmvxvmz5q-uc.a.run.app
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String apiVersion = 'v1';

  // Captcha Configuration
  static const String recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '',
  );

  // Google Maps / Places API key. Read from .env at runtime (see
  // GOOGLE_MAPS_API_KEY in .env.example); falls back to a --dart-define of
  // the same name for CI/build environments without a bundled .env file.
  static String get googleMapsApiKey {
    if (dotenv.isInitialized) {
      final fromEnv = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    }
    return const String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  }

  // Booking.com affiliate "aid" param for redirect links (see
  // services/affiliate_links.dart). Empty until you sign up for the
  // Booking.com Affiliate Partner Program — redirects work with no aid,
  // they just won't be credited to an account until this is set.
  static String get bookingComAffiliateId {
    if (dotenv.isInitialized) {
      final fromEnv = dotenv.env['BOOKING_AFFILIATE_ID'];
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    }
    return const String.fromEnvironment('BOOKING_AFFILIATE_ID');
  }

  // TravelPayouts publisher "marker" ID for redirect links (see
  // services/affiliate_links.dart). This is your TravelPayouts account ID —
  // shown as "ID" in the account sidebar.
  static String get travelpayoutsMarkerId {
    if (dotenv.isInitialized) {
      final fromEnv = dotenv.env['TRAVELPAYOUTS_MARKER_ID'];
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    }
    return const String.fromEnvironment('TRAVELPAYOUTS_MARKER_ID');
  }

  // API Endpoints
  static const String chatEndpoint = '/chat';
  static const String hotelsEndpoint = '/hotels';
  static const String destinationsEndpoint = '/destinations';
  static const String travelEndpoint = '/travel';
  static const String swipeEndpoint = '/swipe';
  static const String budgetEndpoint = '/budget';

  // App Configuration
  static const String appName = 'Triplix - India\'s AI Travel Assistant';
  static const String appVersion = '1.0.0';

  // Colors - Exact EaseMyTrip color scheme
  static const Color primaryColor = Color.fromARGB(255, 181, 181, 183); // Deep Blue
  static const Color secondaryColor = Color(0xFFdc2626); // Red
  static const Color accentColor = Color(0xFFea580c); // Orange
  static const Color backgroundColor =
      Color(0xFFF8FAFC); // Light gray background
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color.fromARGB(255, 176, 142, 142);
  static const Color textPrimary = Color(0xFF1e293b); // Dark slate
  static const Color textSecondary = Color(0xFF64748b); // Medium gray
  static const Color textTertiary = Color(0xFF94a3b8); // Light gray
  static const Color borderColor = Color(0xFFE2E8F0); // Very light gray
  static const Color dividerColor = Color(0xFFF1F5F9);
  static const Color successColor = Color(0xFF10b981); // Green
  static const Color warningColor = Color(0xFFf59e0b); // Amber
  static const Color errorColor = Color(0xFFef4444); // Red
  static const Color infoColor = Color(0xFF3b82f6); // Blue

  // Shadows - EaseMyTrip style
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0F1e293b),
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const BoxShadow buttonShadow = BoxShadow(
    color: Color(0x1F1e3a8a),
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  // Gradient Colors - EaseMyTrip style
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1e3a8a), Color(0xFF3b82f6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFdc2626), Color(0xFFea580c)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10b981), Color(0xFF34d399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  // Font Sizes
  static const double fontSizeSmall = 12.0;
  static const double fontSizeMedium = 14.0;
  static const double fontSizeNormal = 16.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeXLarge = 24.0;
  static const double fontSizeXXLarge = 32.0;

  // Animation Durations
  static const Duration animationDurationShort = Duration(milliseconds: 200);
  static const Duration animationDurationMedium = Duration(milliseconds: 300);
  static const Duration animationDurationLong = Duration(milliseconds: 500);

  // Cache Configuration
  static const int cacheMaxAge = 3600; // 1 hour in seconds
  static const int imageCacheMaxAge = 86400; // 24 hours in seconds

  // Pagination
  static const int itemsPerPage = 20;

  // Card Swipe Configuration
  static const double swipeThreshold = 0.5;
  static const int maxSwipeCards = 10;

  // Map Configuration
  static const double defaultLatitude = 28.6139; // Delhi
  static const double defaultLongitude = 77.2090;
  static const double defaultZoom = 12.0;

  // Timeout Configuration
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
