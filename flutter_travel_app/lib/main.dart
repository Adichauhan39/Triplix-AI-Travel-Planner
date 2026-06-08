import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/search_hotels_screen.dart';
import 'screens/swipe_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/swipeable_hotels_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/hotel_results_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/destination_preferences_screen.dart';
import 'screens/budget_preferences_screen.dart';
import 'screens/transport_preferences_screen.dart';
import 'screens/additional_context_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'models/hotel.dart';
import 'providers/app_provider.dart';
import 'providers/user_preferences_provider.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize API service
  await ApiService().initSession();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => UserPreferencesProvider()),
      ],
      child: GetMaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: false, // Temporarily disable Material 3 to fix icons
          primaryColor: AppConfig.primaryColor,
          scaffoldBackgroundColor: AppConfig.backgroundColor,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConfig.primaryColor,
            brightness: Brightness.light,
            primary: AppConfig.primaryColor,
            secondary: AppConfig.secondaryColor,
            tertiary: AppConfig.accentColor,
            surface: AppConfig.surfaceColor,
            error: AppConfig.errorColor,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: AppConfig.textPrimary,
            onError: Colors.white,
          ),
          fontFamily: 'Poppins',
          textTheme: GoogleFonts.poppinsTextTheme().copyWith(
            headlineLarge: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppConfig.textPrimary,
              height: 1.2,
            ),
            headlineMedium: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppConfig.textPrimary,
              height: 1.3,
            ),
            headlineSmall: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppConfig.textPrimary,
              height: 1.4,
            ),
            titleLarge: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppConfig.textPrimary,
            ),
            titleMedium: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppConfig.textPrimary,
            ),
            titleSmall: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppConfig.textPrimary,
            ),
            bodyLarge: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppConfig.textPrimary,
            ),
            bodyMedium: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppConfig.textSecondary,
            ),
            bodySmall: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppConfig.textTertiary,
            ),
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
            iconTheme: const IconThemeData(
              color: Colors.white,
              size: 24,
            ),
            actionsIconTheme: const IconThemeData(
              color: Colors.white,
              size: 24,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConfig.primaryColor,
              side: const BorderSide(color: AppConfig.primaryColor, width: 1.5),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          cardTheme: CardThemeData(
            color: AppConfig.cardColor,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppConfig.borderColor, width: 1),
            ),
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppConfig.borderColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppConfig.borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppConfig.primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppConfig.errorColor, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppConfig.errorColor, width: 2),
            ),
            hintStyle: GoogleFonts.poppins(
              color: AppConfig.textTertiary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            labelStyle: GoogleFonts.poppins(
              color: AppConfig.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            errorStyle: GoogleFonts.poppins(
              color: AppConfig.errorColor,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 8,
            selectedItemColor: AppConfig.primaryColor,
            unselectedItemColor: AppConfig.textTertiary,
            selectedLabelStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppConfig.primaryColor,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppConfig.textTertiary,
            ),
            showSelectedLabels: true,
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
          ),
        ),
        initialRoute: '/',
        getPages: [
          GetPage(name: '/', page: () => const WelcomeScreen()),
          GetPage(name: '/home', page: () => const HomeScreen()),
          GetPage(
              name: '/destination-preferences',
              page: () => const DestinationPreferencesScreen()),
          GetPage(
              name: '/budget-preferences',
              page: () => const BudgetPreferencesScreen()),
          GetPage(
              name: '/transport-preferences',
              page: () => const TransportPreferencesScreen()),
          GetPage(
              name: '/additional-context',
              page: () => const AdditionalContextScreen()),
          GetPage(name: '/ai-assistant', page: () => const AiAssistantScreen()),
          GetPage(
              name: '/search-hotels', page: () => const SearchHotelsScreen()),
          GetPage(
              name: '/hotel-results', page: () => const HotelResultsScreen()),
          GetPage(name: '/swipe', page: () => const SwipeScreen()),
          GetPage(name: '/bookings', page: () => const BookingsScreen()),
          GetPage(
            name: '/swipeable-hotels',
            page: () {
              final args = Get.arguments as Map<String, dynamic>?;
              final hotels = args?['hotels'] as List<dynamic>? ?? [];
              return SwipeableHotelsScreen(
                hotels: hotels.cast<Hotel>(),
              );
            },
          ),
          GetPage(name: '/cart', page: () => const CartScreen()),
        ],
        builder: (context, child) => child ?? const SizedBox(),
      ),
    );
  }
}
