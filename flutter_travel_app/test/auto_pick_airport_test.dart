import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/screens/search_flights_screen.dart';
import 'package:flutter_travel_app/services/python_adk_service.dart';

void main() {
  // The exact shapes the live service returns, checked against it.
  const blr = AirportOption(
      code: 'BLR', name: 'Kempegowda International Airport', city: 'Bangalore');
  const jai =
      AirportOption(code: 'JAI', name: 'Jaipur Airport', city: 'Jaipur');
  const bom = AirportOption(
      code: 'BOM',
      name: 'Chhatrapati Shivaji International Airport',
      city: 'Mumbai');
  const nmi = AirportOption(
      code: 'NMI', name: 'Navi Mumbai International Airport', city: 'Mumbai');
  const rpr = AirportOption(
      code: 'RPR', name: 'Swami Vivekananda Airport', city: 'Raipur');

  test('a city with one airport is chosen without asking', () {
    // The complaint: this box already said Bangalore and still made you tap
    // BLR underneath it.
    expect(
        shouldAutoPickAirport(
            typed: 'Bangalore, Karnataka, India',
            found: [blr],
            untouched: true),
        isTrue);
    expect(
        shouldAutoPickAirport(
            typed: 'Jaipur, Rajasthan, India', found: [jai], untouched: true),
        isTrue);
  });

  test('two airports stay a question', () {
    // Mumbai really is BOM or NMI and only the traveller knows which.
    expect(
        shouldAutoPickAirport(
            typed: 'Mumbai, Maharashtra, India',
            found: [bom, nmi],
            untouched: true),
        isFalse);
  });

  test('something being typed is never chosen for you', () {
    // Mid-word the first hit is a guess at an unfinished thought.
    expect(
        shouldAutoPickAirport(
            typed: 'Bang', found: [blr], untouched: false),
        isFalse);
  });

  test('a different city is a substitution and must be shown', () {
    // Bhilai has no airport and flights use Raipur. That changes which city
    // somebody flies to, so it is never slipped in silently.
    expect(
        shouldAutoPickAirport(
            typed: 'Bhilai, Chhattisgarh, India',
            found: [rpr],
            untouched: true),
        isFalse);
  });

  test('nothing found is nothing to choose', () {
    expect(
        shouldAutoPickAirport(typed: 'Bangalore', found: [], untouched: true),
        isFalse);
  });

  test('case and spacing do not decide it', () {
    expect(
        shouldAutoPickAirport(
            typed: '  bangalore ,  Karnataka ', found: [blr], untouched: true),
        isTrue);
  });
}
