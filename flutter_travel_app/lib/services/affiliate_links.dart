import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/hotel.dart';

/// Builds outbound redirect links to third-party booking sites, since this
/// app doesn't process bookings itself — it hands off to a partner and
/// (once an affiliate ID is configured) earns a referral commission.
class AffiliateLinks {
  AffiliateLinks._();

  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');

  /// Aviasales' hotels search, carrying the destination city.
  ///
  /// Aviasales forwards hotel bookings on to Booking.com with its own `aid`
  /// and a TravelPayouts label, passing the city through as Booking.com's
  /// `ss` parameter — so the city is the unit Aviasales works in here, not
  /// the individual property. Sending the hotel name would not survive that
  /// hop, so we send the city and the user picks the property there.
  ///
  /// Replaces an earlier fixed short link, which sent every hotel button to
  /// the same unfiltered page.
  ///
  /// NOTE: `destination` is the assumed parameter name — /hotels is a client
  /// -rendered page, so it can't be verified from the server side. If it's
  /// wrong Aviasales ignores it and shows the plain hotels page, which is
  /// exactly what the old short link did, so a bad guess costs nothing.
  static Uri aviasalesHotelSearch({
    required Hotel hotel,
    DateTime? checkIn,
    DateTime? checkOut,
    int guests = 2,
  }) =>
      aviasalesHotelSearchByCity(
        city: hotel.city,
        checkIn: checkIn,
        checkOut: checkOut,
        guests: guests,
      );

  /// Opens a throwaway connection to the hotel partner so DNS resolution and
  /// the TLS handshake are already done before the user taps "Book".
  ///
  /// The handoff crosses three hosts (search.hotellook.com →
  /// hotels-api.aviasales.ru → booking.com) and measured 5.4s cold against
  /// 2.7s warm — that gap is almost entirely connection setup on the first
  /// host. Call it when a screen that can redirect opens.
  ///
  /// Fire-and-forget: the response is irrelevant and every failure mode
  /// (offline, CORS on web, timeout) is ignored. Warming happens as a side
  /// effect of attempting the connection at all.
  /// Uses package:http rather than dart:io HttpClient so it also runs on web,
  /// where the request is blocked by CORS — but the browser still performs
  /// the DNS lookup and TLS handshake first, which is the whole point.
  static void prewarmHotelPartner() {
    unawaited(
      http
          .head(Uri.https('search.hotellook.com', '/'))
          .timeout(const Duration(seconds: 5))
          .then((_) {}, onError: (_) {}),
    );
  }

  /// Cities whose bare name resolves to the wrong place in Hotellook's fuzzy
  /// matcher. "Goa" is a state rather than a city, and both "Goa" and "Goa,
  /// India" land on Goiania, Brazil — so it's mapped to its capital, which
  /// resolves correctly. Add entries here as bad matches are found.
  static const Map<String, String> _hotelCityAliases = {
    'goa': 'Panaji',
    'north goa': 'Panaji',
    'south goa': 'Margao',
    'kerala': 'Kochi',
  };

  /// Hotel search keyed by city, for when there's no specific property to hand
  /// off — the in-app search failed, or the user just wants to browse.
  ///
  /// Uses search.hotellook.com rather than aviasales.in/hotels: the Aviasales
  /// hotels page ignores query parameters (it opened with every field blank),
  /// whereas this one carries the destination and dates through to Booking.com
  /// as `ss`/`checkin` and applies the TravelPayouts label automatically.
  /// Same partner family, same attribution, but the search is actually
  /// prefilled.
  ///
  /// The country is appended because bare city names match badly — "Bhilai"
  /// alone resolves to Santiago, Chile.
  static Uri aviasalesHotelSearchByCity({
    required String city,
    DateTime? checkIn,
    DateTime? checkOut,
    int guests = 2,
    String country = 'India',
  }) {
    // A qualified name ("Bilaspur, Himachal Pradesh, India") is passed through
    // untouched. Hotellook honours the region and it is the only thing that
    // separates same-named cities: bare "Bilaspur" resolves to the
    // Chhattisgarh one, so stripping the state would send anyone who picked
    // the Himachal Pradesh one to the wrong end of the country.
    final trimmed = city.trim();
    final String destination;
    if (trimmed.contains(',')) {
      destination = trimmed;
    } else {
      final resolved = _hotelCityAliases[trimmed.toLowerCase()] ?? trimmed;
      destination = resolved.isEmpty ? country : '$resolved, $country';
    }

    return Uri.https('search.hotellook.com', '/', {
      'destination': destination,
      'adults': '$guests',
      'currency': 'inr',
      'language': 'en',
      if (checkIn != null) 'checkIn': _isoDate.format(checkIn),
      if (checkOut != null) 'checkOut': _isoDate.format(checkOut),
      if (AppConfig.travelpayoutsMarkerId.isNotEmpty)
        'marker': AppConfig.travelpayoutsMarkerId,
    });
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
    'raipur': 'RPR',
    'bhopal': 'BHO',
    'varanasi': 'VNS',
    'amritsar': 'ATQ',
    'udaipur': 'UDR',
    'jodhpur': 'JDH',
    'patna': 'PAT',
    'guwahati': 'GAU',
    'bhubaneswar': 'BBI',
    'coimbatore': 'CJB',
    'trivandrum': 'TRV',
    'thiruvananthapuram': 'TRV',
    'srinagar': 'SXR',
    'dehradun': 'DED',
    'chandigarh': 'IXC',
    'ranchi': 'IXR',
    'vadodara': 'BDQ',
    'visakhapatnam': 'VTZ',
    'madurai': 'IXM',
    'mangalore': 'IXE',
    'leh': 'IXL',
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
    'Raipur',
    'Bhopal',
    'Varanasi',
    'Amritsar',
    'Udaipur',
    'Jodhpur',
    'Patna',
    'Guwahati',
    'Bhubaneswar',
    'Coimbatore',
    'Trivandrum',
    'Srinagar',
    'Dehradun',
    'Chandigarh',
    'Ranchi',
    'Vadodara',
    'Visakhapatnam',
    'Madurai',
    'Mangalore',
    'Leh',
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

  /// Aviasales' India storefront. Using the .in domain with market=in makes
  /// fares render in INR by default; the .com domain infers the market from
  /// the visitor and can land an Indian user on USD pricing.
  static const String _aviasalesHost = 'aviasales.in';
  static const Map<String, String> _indiaMarketParams = {
    'market': 'in',
    'currency': 'inr',
    'locale': 'en',
  };

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
        Uri.https(_aviasalesHost, '/', _indiaMarketParams),
        programId: 4114,
      );
    }

    final departCode = DateFormat('ddMM').format(departDate);
    final returnCode =
        returnDate != null ? DateFormat('ddMM').format(returnDate) : '';
    final route =
        '$originIata$departCode$destinationIata$returnCode$passengers';

    return _travelpayoutsWrap(
      Uri.https(_aviasalesHost, '/search/$route', _indiaMarketParams),
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
