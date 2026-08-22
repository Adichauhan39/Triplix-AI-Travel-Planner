import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_travel_app/models/confirmed_booking.dart';
import 'package:flutter_travel_app/providers/booked_trip_provider.dart';
import 'package:flutter_travel_app/services/local_store.dart';

ConfirmedBooking flight(String? number, {int day = 24, String? time}) =>
    ConfirmedBooking(
      kind: BookingKind.flight,
      title: 'Bangalore to Raipur',
      startDate: DateTime(2026, 8, day),
      flightNumber: number,
      departureTime: time,
      flightIsRealFlight: number != null,
    );

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('the same flight confirmed twice is listed once', () {
    final provider = BookedTripProvider()
      ..add(flight('6E 405'))
      ..add(flight('6E 405'));
    expect(provider.flights, hasLength(1));
  });

  test('spacing and case do not create a duplicate', () {
    final provider = BookedTripProvider()
      ..add(flight('6E 405'))
      ..add(flight('6e405'));
    expect(provider.flights, hasLength(1));
  });

  test('a later confirmation corrects an earlier blank one', () {
    final provider = BookedTripProvider()
      ..add(flight(null))
      ..add(flight('6E 405', time: '07:40'));
    expect(provider.flights, hasLength(1));
    expect(provider.flights.single.flightNumber, '6E 405');
    expect(provider.flights.single.departureTime, '07:40');
  });

  test('two different flights on one day both survive', () {
    final provider = BookedTripProvider()
      ..add(flight('6E 405'))
      ..add(flight('6E 986'));
    expect(provider.flights, hasLength(2));
  });

  test('the same flight number on another day is a separate leg', () {
    final provider = BookedTripProvider()
      ..add(flight('6E 405', day: 24))
      ..add(flight('6E 405', day: 31));
    expect(provider.flights, hasLength(2));
  });

  test('one hotel per check-in date, the newer answer winning', () {
    final provider = BookedTripProvider()
      ..add(ConfirmedBooking(
        kind: BookingKind.hotel,
        title: 'Old Hotel',
        startDate: DateTime(2026, 8, 24),
        hotelName: 'Old Hotel',
      ))
      ..add(ConfirmedBooking(
        kind: BookingKind.hotel,
        title: 'Hotel Amit Park International',
        startDate: DateTime(2026, 8, 24),
        hotelName: 'Hotel Amit Park International',
      ));
    expect(provider.hotels, hasLength(1));
    expect(provider.hotels.single.hotelName, 'Hotel Amit Park International');
  });

  test('duplicates already on the device are cleaned up on restore', () async {
    // Written by the version that appended without checking.
    BookedTripProvider()
      ..add(flight('6E 405'))
      ..add(flight('6E 986'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stored = LocalStore.loadList(LocalStore.keyBookings);
    await LocalStore.save(LocalStore.keyBookings, [...stored, stored.first]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = BookedTripProvider()..restore();
    expect(after.flights, hasLength(2));
  });
}
