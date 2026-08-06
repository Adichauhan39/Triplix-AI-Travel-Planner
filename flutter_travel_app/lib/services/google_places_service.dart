import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'google_places_web_stub.dart'
    if (dart.library.html) 'google_places_web.dart' as web;

/// City autocomplete backed by the Google Places API.
///
/// - On web: uses the Google Maps JS SDK's `AutocompleteService` (loaded via
///   `<script>` tag in `web/index.html`) so no CORS issues.
/// - On mobile/desktop: uses the Places Autocomplete REST endpoint.
class GooglePlacesService {
  GooglePlacesService({http.Client? client})
      : _client = client ?? http.Client();

  static String get _apiKey => AppConfig.googleMapsApiKey;

  final http.Client _client;

  Future<List<Map<String, String>>> autocompleteCity(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      if (kIsWeb) {
        return await web.autocompleteCitiesWeb(q);
      }
      return await _autocompleteHttp(q);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, String>>> _autocompleteHttp(String query) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeQueryComponent(query)}'
      '&types=(cities)'
      '&key=$_apiKey',
    );
    final resp = await _client.get(uri).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return const [];
    final data = json.decode(resp.body);
    if (data is! Map<String, dynamic>) return const [];
    if (data['status'] != 'OK') return const [];
    final preds = (data['predictions'] as List?) ?? const [];
    return preds.map<Map<String, String>>((p) {
      final structured = (p is Map && p['structured_formatting'] is Map)
          ? p['structured_formatting'] as Map
          : const {};
      final city = (structured['main_text'] ?? '').toString();
      final country = (structured['secondary_text'] ?? '').toString();
      final desc = (p is Map ? (p['description'] ?? '') : '').toString();
      return {
        'city': city,
        'country': country,
        'description': desc,
      };
    }).toList();
  }
}
