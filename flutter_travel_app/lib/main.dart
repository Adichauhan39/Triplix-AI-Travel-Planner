import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

// App-level configuration, feature screens, state providers, and API bootstrap.
import 'config/app_config.dart';
import 'screens/shared_trip_screen.dart';
import 'screens/home_screen.dart';
import 'screens/search_hotels_screen.dart';
import 'screens/swipe_screen.dart';
import 'screens/trip_plan_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/swipeable_hotels_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/hotel_results_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/destination_preferences_screen.dart';
import 'screens/budget_preferences_screen.dart';
import 'screens/transport_preferences_screen.dart';
import 'screens/additional_context_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/account_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/post_login_verification_screen.dart';
import 'middleware/auth_guard.dart';
import 'models/hotel.dart';
import 'providers/app_provider.dart';
import 'providers/user_preferences_provider.dart';
import 'providers/hotel_shortlist_provider.dart';
import 'providers/booked_trip_provider.dart';
import 'providers/export_job_provider.dart';
import 'providers/trip_plan_provider.dart';
import 'services/local_store.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

void main() async {
  // Ensures plugins/channels are ready before async initialization.
  WidgetsFlutterBinding.ensureInitialized();

  // Load API keys/secrets from .env (falls back to --dart-define values in
  // AppConfig if this file is missing, e.g. in a CI build).
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('.env load error: $e');
  }

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Initialize Hive for local storage
  try {
    await Hive.initFlutter();
  } catch (e) {
    debugPrint('Hive init error: $e');
  }

  // Initialize API service
  try {
    // Starts/refreshes backend session state used by the app services.
    await ApiService().initSession();
  } catch (e) {
    debugPrint('API service init error: $e');
  }

  // Restore the demo-account session flag (if any) so AuthGuard still lets
  // a previously-demo-logged-in user through after an app restart.
  try {
    await AuthService.loadDemoSessionFlag();
  } catch (e) {
    debugPrint('Demo session flag load error: $e');
  }

  // Opened before the first frame so the app starts on the user's existing
  // trip. Restoring after runApp would show an empty screen that fills in a
  // moment later, which reads as data being lost and then found.
  await LocalStore.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Global app UI/feature state.
        ChangeNotifierProvider(create: (_) => AppProvider()),
        // User travel profile and onboarding selections.
        // ..restore(): the device's copy is read as each provider is created,
        // so the first frame already has the saved trip.
        ChangeNotifierProvider(
            create: (_) => UserPreferencesProvider()..restore()),
        // Hotels saved for comparison before booking.
        ChangeNotifierProvider(create: (_) => HotelShortlistProvider()),
        // What the user says they've booked on partner sites — the only
        // signal we get, since the redirect never reports back.
        ChangeNotifierProvider(create: (_) => BookedTripProvider()..restore()),
        ChangeNotifierProvider(create: (_) => TripPlanProvider()..restore()),
        // A film or PDF being built on the server. App-level, because the
        // render keeps going while the person walks around the app -- and the
        // "it is ready" message has to find them wherever they ended up.
        ChangeNotifierProvider(
            create: (_) => ExportJobProvider()..restore()),
      ],
      child: GetMaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // Theme is centralized so screens stay visually consistent.
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
          // Auth and entry routes.
          GetPage(
              name: '/',
              page: () => const SelectionArea(child: WelcomeScreen())),
          GetPage(
              name: '/auth',
              page: () {
                final args = Get.arguments;
                final tab = args is Map && args['tab'] == 'signup'
                    ? AuthTab.signup
                    : AuthTab.login;
                final openTerms = args is Map && args['openTerms'] == true;
                return SelectionArea(
                  child: AuthScreen(
                    initialTab: tab,
                    openTermsOnStart: openTerms,
                  ),
                );
              }),
          // A trip opened from a shared link. The id is part of the path, so
          // the link survives being pasted into a chat -- a query string gets
          // mangled by some clients, and this is a link people forward.
          GetPage(
              name: '/trip/:id',
              page: () => SelectionArea(
                    child: SharedTripScreen(
                      tripId: Get.parameters['id'] ?? '',
                    ),
                  )),
          GetPage(
              name: '/login',
              page: () => const SelectionArea(
                  child: AuthScreen(initialTab: AuthTab.login))),
          GetPage(
              name: '/onboarding-loading',
              page: () =>
                  const SelectionArea(child: PostLoginVerificationScreen())),
          GetPage(
              name: '/signup',
              page: () => const SelectionArea(
                  child: AuthScreen(initialTab: AuthTab.signup))),
          GetPage(
              name: '/terms',
              page: () => const SelectionArea(
                      child: AuthScreen(
                    initialTab: AuthTab.login,
                    openTermsOnStart: true,
                  ))),
          GetPage(
              name: '/account',
              page: () => const SelectionArea(child: AccountScreen()),
              middlewares: [AuthGuard()]),

          // Main experience routes.
          GetPage(
              name: '/home',
              page: () => const SelectionArea(child: HomeScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/onboarding',
              page: () => const SelectionArea(child: OnboardingScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/destination-preferences',
              page: () =>
                  const SelectionArea(child: DestinationPreferencesScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/budget-preferences',
              page: () => const SelectionArea(child: BudgetPreferencesScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/transport-preferences',
              page: () =>
                  const SelectionArea(child: TransportPreferencesScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/additional-context',
              page: () => const SelectionArea(child: AdditionalContextScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/ai-assistant',
              page: () => const SelectionArea(child: AiAssistantScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/search-hotels',
              page: () => const SelectionArea(child: SearchHotelsScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/hotel-results',
              page: () => const SelectionArea(child: HotelResultsScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/swipe',
              page: () => const SelectionArea(child: SwipeScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/trip-plan',
              page: () => const SelectionArea(child: TripPlanScreen()),
              middlewares: [AuthGuard()]),
          GetPage(
              name: '/bookings',
              page: () => const SelectionArea(child: BookingsScreen()),
              middlewares: [AuthGuard()]),

          // Utility routes that require runtime arguments.
          GetPage(
            name: '/swipeable-hotels',
            page: () {
              final args = Get.arguments as Map<String, dynamic>?;
              final hotels = args?['hotels'] as List<dynamic>? ?? [];
              return SelectionArea(
                child: SwipeableHotelsScreen(
                  hotels: hotels.cast<Hotel>(),
                ),
              );
            },
            middlewares: [AuthGuard()],
          ),
          GetPage(
              name: '/cart',
              page: () => const SelectionArea(child: CartScreen()),
              middlewares: [AuthGuard()]),
        ],
        builder: (context, child) => child ?? const SizedBox(),
      ),
    );
  }
}
