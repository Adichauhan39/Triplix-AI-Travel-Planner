import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/hotel.dart';

/// Builds outbound redirect links to third-party booking sites, since this
/// app doesn't process bookings itself — it hands off to a partner and
/// (once an affiliate ID is configured) earns a referral commission.
class AffiliateLinks {
  AffiliateLinks._();

  /// Aviasales hotels, via the TravelPayouts short link generated in the
  /// TravelPayouts dashboard. The marker/attribution is already baked into
  /// the short link itself, so nothing needs appending and nothing needs
  /// reading from .env for this one.
  ///
  /// Aviasales forwards hotel bookings on to Booking.com itself (with its own
  /// aid attached) — that downstream hop is Aviasales' business, not ours.
  ///
  /// Trade-off: a short link is a fixed destination, so the hotel the user
  /// tapped (and the dates/guests they picked) can't be carried through — they
  /// land on the Aviasales hotels page and search again there. Swap this for a
  /// full https://www.aviasales.com/hotels?... URL with your marker appended if
  /// you want to preselect the hotel and dates.
  static Uri aviasalesHotelSearch({
    required Hotel hotel,
    DateTime? checkIn,
    DateTime? checkOut,
    int guests = 2,
  }) {
    return Uri.parse('https://aviasales.tpo.li/ntQoEoPm');
  }

  // IATA airport codes for the cities this app's search UI offers. Aviasales
  // deep links need a 3-letter code, not a free-text city name; unmapped
  // cities fall back to the unfiltered Aviasales homepage further down.
  static const Map<String, String> _iataCodes = {
    'mumbai': 'BOM',
    'delhi': 'DEL',
    'goa': 'GOI',
    'bangalore': 'BLR',
    'bengaluru': 'BLR',
    'jaipur': 'JAI',
    'kolkata': 'CCU',
    'chennai': 'MAA',
    'hyderabad': 'HYD',
    'pune': 'PNQ',
    'ahmedabad': 'AMD',
    'kochi': 'COK',
    'lucknow': 'LKO',
    'indore': 'IDR',
    'surat': 'STV',
    'nagpur': 'NAG',
  };

  /// Looks up the IATA code for a city name from [_iataCodes] (case/
  /// whitespace insensitive, ignores anything after a comma e.g.
  /// "Mumbai, India"). Returns null if the city isn't in the map.
  static String? iataCodeFor(String city) {
    final key = city.split(',').first.trim().toLowerCase();
    return _iataCodes[key];
  }

  /// Cities with a known IATA code, for building a flight-city picker that's
  /// guaranteed to produce a real (not homepage-fallback) Aviasales link.
  static const List<String> flightCities = [
    'Mumbai',
    'Delhi',
    'Goa',
    'Bangalore',
    'Jaipur',
    'Kolkata',
    'Chennai',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
    'Kochi',
    'Lucknow',
    'Indore',
    'Surat',
    'Nagpur',
  ];

  /// Wraps [destination] in TravelPayouts' tracking redirect
  /// (tp.media/r) so the click is attributed to this account before
  /// bouncing on to the real site. campaign_id/p/trs identify the
  /// Aviasales program + link tool inside this TravelPayouts account (see
  /// TRAVELPAYOUTS_MARKER_ID in .env for the account-level marker).
  static Uri _travelpayoutsWrap(Uri destination, {required int programId}) {
    return Uri.https('tp.media', '/r', {
      'campaign_id': '100',
      'marker': AppConfig.travelpayoutsMarkerId,
      'p': '$programId',
      'trs': '556043',
      'u': destination.toString(),
    });
  }

  /// Aviasales flight search, wrapped in a TravelPayouts tracking link.
  /// [originCity]/[destinationCity] must resolve to a known IATA code (see
  /// iataCodeFor) — falls back to the plain (still-tracked) Aviasales
  /// homepage if either city isn't mapped, since Aviasales' search URL
  /// requires airport codes rather than free-text city names.
  static Uri aviasalesFlightSearch({
    required String originCity,
    required String destinationCity,
    required DateTime departDate,
    DateTime? returnDate,
    int passengers = 1,
  }) {
    final originIata = iataCodeFor(originCity);
    final destinationIata = iataCodeFor(destinationCity);

    if (originIata == null || destinationIata == null) {
      return _travelpayoutsWrap(
        Uri.parse('https://www.aviasales.com'),
        programId: 4114,
      );
    }

    final departCode = DateFormat('ddMM').format(departDate);
    final returnCode =
        returnDate != null ? DateFormat('ddMM').format(returnDate) : '';
    final route =
        '$originIata$departCode$destinationIata$returnCode$passengers';

    return _travelpayoutsWrap(
      Uri.parse('https://www.aviasales.com/search/$route'),
      programId: 4114,
    );
  }

  /// Opens [uri] in an in-app browser tab (Chrome Custom Tabs on Android,
  /// SFSafariViewController on iOS) rather than handing off to an installed
  /// native app. This matters for commission: some affiliate programs (e.g.
  /// MakeMyTrip via EarnKaro) explicitly don't pay out for bookings made
  /// inside the merchant's own app, and LaunchMode.externalApplication can
  /// get intercepted by an installed app via Android App Links / iOS
  /// Universal Links. inAppBrowserView is a web context only, so it can't be
  /// claimed by a native app the way an external-app launch can.
  static Future<void> open(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }
}
