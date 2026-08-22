import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_travel_app/models/confirmed_booking.dart';
import 'package:flutter_travel_app/models/trip_plan.dart';
import 'package:flutter_travel_app/providers/booked_trip_provider.dart';
import 'package:flutter_travel_app/providers/trip_plan_provider.dart';
import 'package:flutter_travel_app/providers/user_preferences_provider.dart';
import 'package:flutter_travel_app/services/local_store.dart';

/// Restarting the app is simulated by building a second provider over the same
/// storage — which is exactly what happens on a cold start.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('trip details survive a restart', () async {
    final before = UserPreferencesProvider()
      ..updateDestination('Bhilai, Chhattisgarh, India')
      ..updateDates(DateTime(2026, 9, 1), DateTime(2026, 9, 3))
      ..updateActivities(['Maitri Bagh', 'Civic Centre']);

    // Writes are fire-and-forget, so let them land before reading back.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = UserPreferencesProvider()..restore();
    expect(after.preferences.destination, before.preferences.destination);
    expect(after.preferences.checkInDate, DateTime(2026, 9, 1));
    expect(after.preferences.selectedActivities, ['Maitri Bagh', 'Civic Centre']);
  });

  test('a confirmed booking survives a restart', () async {
    BookedTripProvider().add(ConfirmedBooking(
      kind: BookingKind.flight,
      title: 'Bhopal to Raipur',
      startDate: DateTime(2026, 8, 24),
      flightNumber: '6E 7302',
      departureTime: '15:10',
      flightIsRealFlight: true,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = BookedTripProvider()..restore();
    expect(after.bookings, hasLength(1));
    expect(after.flights.single.flightNumber, '6E 7302');
    expect(after.flights.single.departureTime, '15:10');
    // The verified flag must survive, or a real flight comes back unverified.
    expect(after.flights.single.flightIsRealFlight, isTrue);
  });

  test('an unverified hotel does not come back verified', () async {
    BookedTripProvider().add(ConfirmedBooking(
      kind: BookingKind.hotel,
      title: 'amith int.',
      startDate: DateTime(2026, 8, 24),
      hotelName: 'amith int.',
      hotelNameIsRealPlace: false,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = BookedTripProvider()..restore();
    expect(after.hotels.single.hotelNameIsRealPlace, isFalse);
  });

  test('an edited plan survives a restart', () async {
    final provider = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Udaipur',
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 2),
        activities: ['City Palace', 'Lake Pichola'],
      );
    // The kind of change the prompt box makes.
    provider.replaceDays([
      PlanDay(date: DateTime(2026, 9, 1), items: const [
        PlanItem(title: 'City Palace'),
        PlanItem(title: 'Ambrai Restaurant', addedByAssistant: true),
      ]),
      PlanDay(date: DateTime(2026, 9, 2), items: const [
        PlanItem(title: 'Lake Pichola'),
      ]),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = TripPlanProvider()..restore();
    expect(after.plan!.destination, 'Udaipur');
    expect(after.plan!.days, hasLength(2));
    expect(after.plan!.activityCount, 3);
    // The suggested marker has to survive, or an unverified suggestion comes
    // back looking like the user's own choice.
    expect(after.plan!.days.first.items.last.addedByAssistant, isTrue);
  });

  test('nothing stored means nothing restored, not a crash', () async {
    expect((UserPreferencesProvider()..restore()).preferences.destination,
        isNull);
    expect((BookedTripProvider()..restore()).bookings, isEmpty);
    expect((TripPlanProvider()..restore()).plan, isNull);
  });

  test('corrupt storage is discarded rather than surfaced', () async {
    SharedPreferences.setMockInitialValues(
        {LocalStore.keyTripPlan: 'not json at all'});
    await LocalStore.init();
    expect((TripPlanProvider()..restore()).plan, isNull);
  });

  test('clearAll wipes everything, for a delete-my-data request', () async {
    UserPreferencesProvider().updateDestination('Goa');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await LocalStore.clearAll();
    expect((UserPreferencesProvider()..restore()).preferences.destination,
        isNull);
  });
}
