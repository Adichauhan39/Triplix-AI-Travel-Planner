import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device's copy of the user's trip.
///
/// Device first, server second. Everything is written here the moment it
/// changes, so the app survives a restart and — more importantly — works with
/// no signal. A traveller loses connectivity exactly when the itinerary
/// matters most: at an airport, in an unfamiliar city, on a train. An app that
/// needs the network to show someone their own booking is broken at the one
/// moment it is needed.
///
/// Deliberately a thin key/value layer over JSON rather than a schema. Server
/// sync is the next step, and it can be added behind this same interface: each
/// record already carries an `updatedAt`, which is what a last-write-wins
/// merge needs. Providers call [save]/[load] and never learn where the data
/// actually lives.
class LocalStore {
  LocalStore._();

  static SharedPreferences? _prefs;

  /// Prepares storage. Call once before runApp, so the first frame can already
  /// show a restored trip instead of an empty screen that fills in a moment
  /// later.
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // Storage being unavailable must not stop the app from opening — it
      // degrades to the previous behaviour of losing state on restart.
      debugPrint('LocalStore: unavailable, running without persistence: $e');
      _prefs = null;
    }
  }

  static const String keyPreferences = 'triplix.preferences';
  static const String keyBookings = 'triplix.bookings';
  static const String keyTripPlan = 'triplix.trip_plan';

  /// The export currently rendering on the server, so leaving the screen
  /// -- or closing the app -- does not lose track of it.
  static const String keyExportJob = 'triplix.export_job';

  /// Answers to the gap questions, so the same one is not asked twice.
  static const String keyTripShape = 'triplix.trip_shape';

  /// What Explore found for a city: the resolved name and its interest
  /// categories. Saved because it is expensive to fetch and cheap to keep --
  /// re-running it on every launch would be a model call to rebuild something
  /// that has not changed.
  static const String keyExplore = 'triplix.explore';

  /// Stored under one key per record, with the time it changed.
  static Future<void> save(String key, Object? value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      if (value == null) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(
        key,
        jsonEncode({
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'data': value,
        }),
      );
    } catch (e) {
      // A failed write is not worth interrupting the user for: the value is
      // still correct in memory, and the next change will try again.
      debugPrint('LocalStore: save failed for $key: $e');
    }
  }

  /// The stored value, or null when nothing was saved or it can't be read.
  ///
  /// Unreadable data is discarded rather than surfaced. Anything stored here
  /// was written by an older version of this app, and a half-parsed trip is
  /// worse than starting fresh.
  static Map<String, dynamic>? load(String key) {
    final prefs = _prefs;
    if (prefs == null) return null;
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('LocalStore: could not read $key, discarding: $e');
      return null;
    }
  }

  /// The list form of [load], for records stored as a JSON array.
  static List<Map<String, dynamic>> loadList(String key) {
    final prefs = _prefs;
    if (prefs == null) return const [];
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('LocalStore: could not read list $key, discarding: $e');
      return const [];
    }
  }

  /// When [key] last changed, for the sync layer to compare against the
  /// server's copy. Null when nothing is stored.
  static DateTime? updatedAt(String key) {
    final prefs = _prefs;
    if (prefs == null) return null;
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DateTime.tryParse((decoded['updatedAt'] ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  /// Removes everything this app stored on the device.
  ///
  /// Needed on sign-out, and needed for a delete-my-data request — India's
  /// DPDP Act gives users that right, and the records here include flight
  /// numbers, hotels and travel dates.
  static Future<void> clearAll() async {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final key in [keyPreferences, keyBookings, keyTripPlan]) {
      await prefs.remove(key);
    }
  }
}
