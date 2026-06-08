import 'dart:convert';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class RouteInfo {
  final String origin;
  final String destination;
  final String distance;
  final String duration;
  final int distanceMeters;
  final int durationSeconds;
  final String mode;
  final List<LatLng> polylinePoints;
  final List<RouteStep> steps;
  final LatLng originLatLng;
  final LatLng destinationLatLng;

  RouteInfo({
    required this.origin,
    required this.destination,
    required this.distance,
    required this.duration,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.mode,
    required this.polylinePoints,
    required this.steps,
    required this.originLatLng,
    required this.destinationLatLng,
  });
}

class RouteStep {
  final String instruction;
  final String distance;
  final String duration;
  final String travelMode;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.travelMode,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      instruction: json['instruction'] ?? '',
      distance: json['distance'] ?? '',
      duration: json['duration'] ?? '',
      travelMode: json['travel_mode'] ?? 'driving',
    );
  }
}

class MapsService {
  static final MapsService _instance = MapsService._internal();
  factory MapsService() => _instance;
  MapsService._internal();

  final String _baseUrl = AppConfig.baseUrl;

  /// Fetch route directions from the backend
  Future<RouteInfo> getDirections({
    required String origin,
    required String destination,
    String mode = 'driving',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/maps/directions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'origin': origin,
              'destination': destination,
              'mode': mode,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final polylinePoints =
              _decodePolyline(data['overview_polyline'] ?? '');

          // Derive origin/destination LatLng from polyline endpoints
          final originLatLng = polylinePoints.isNotEmpty
              ? polylinePoints.first
              : const LatLng(28.6139, 77.2090);
          final destinationLatLng = polylinePoints.isNotEmpty
              ? polylinePoints.last
              : const LatLng(19.0760, 72.8777);

          final steps = (data['steps'] as List?)
                  ?.map((s) => RouteStep.fromJson(s as Map<String, dynamic>))
                  .toList() ??
              [];

          return RouteInfo(
            origin: data['origin'] ?? origin,
            destination: data['destination'] ?? destination,
            distance: data['distance'] ?? '',
            duration: data['duration'] ?? '',
            distanceMeters: data['distance_meters'] ?? 0,
            durationSeconds: data['duration_seconds'] ?? 0,
            mode: data['mode'] ?? mode,
            polylinePoints: polylinePoints,
            steps: steps,
            originLatLng: originLatLng,
            destinationLatLng: destinationLatLng,
          );
        } else {
          throw Exception(data['message'] ?? 'No route found');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get directions: $e');
    }
  }

  /// Decode Google Maps encoded polyline string into LatLng list
  List<LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return [];

    List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decode latitude
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      // Decode longitude
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  /// Calculate bounds that contain all polyline points
  LatLngBounds boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
