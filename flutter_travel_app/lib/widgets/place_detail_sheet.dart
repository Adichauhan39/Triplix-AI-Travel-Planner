import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/python_adk_service.dart';

/// What a place in the itinerary actually is: photos, rating, reviews, hours
/// and where it sits on the map.
///
/// Every field here comes from Google Places for that specific place. Nothing
/// is generated, and nothing is filled in with a stand-in — a section is
/// simply absent when Google has no answer for it. A plausible-looking review
/// or a stock photo would be worse than a shorter sheet.
class PlaceDetailSheet extends StatefulWidget {
  const PlaceDetailSheet({super.key, required this.name, required this.city});

  final String name;
  final String city;

  static Future<void> show(BuildContext context,
      {required String name, required String city}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlaceDetailSheet(name: name, city: city),
    );
  }

  @override
  State<PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<PlaceDetailSheet> {
  final PythonADKService _adk = PythonADKService();

  Map<String, dynamic>? _place;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final place = await _adk.placeDetails(name: widget.name, city: widget.city);
    if (!mounted) return;
    setState(() {
      _place = place;
      _failed = place == null;
      _loading = false;
    });
  }

  /// Opens the place in Google Maps rather than drawing a route here.
  ///
  /// Google's own link gives real driving directions with live traffic, for
  /// free, in the app people already navigate with. Computing a route in-app
  /// would mean paying per request for a worse version of it.
  Future<void> _openInMaps() async {
    final url = (_place?['google_maps_url'] ?? '').toString();
    final lat = _place?['lat'];
    final lng = _place?['lng'];
    final target = url.isNotEmpty
        ? Uri.parse(url)
        : Uri.https('www.google.com', '/maps/search/',
            {'api': '1', 'query': '$lat,$lng'});
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  /// Seven lines of opening hours reduced to what a traveller acts on: the
  /// usual hours, and which days it is shut.
  ///
  /// "Monday: Closed / Tuesday: 9 to 5 / Wednesday: 9 to 5 ..." is seven
  /// lines to read the same fact seven times. Days that share hours are
  /// collapsed, and closed days are named separately because that is the one
  /// entry that can ruin a day's plan.
  ///
  /// Falls back to the raw lines when the hours genuinely differ by day, since
  /// summarising those would hide a real difference.
  static String? _hoursSummary(List<dynamic> lines) {
    if (lines.isEmpty) return null;

    final closedDays = <String>[];
    final openTimes = <String, List<String>>{};

    for (final raw in lines) {
      final text = raw.toString();
      final split = text.indexOf(':');
      if (split == -1) continue;
      final day = text.substring(0, split).trim();
      final hours = text.substring(split + 1).trim();
      if (hours.toLowerCase().contains('closed')) {
        closedDays.add(day);
      } else {
        openTimes.putIfAbsent(hours, () => []).add(day);
      }
    }

    if (openTimes.isEmpty) return closedDays.isEmpty ? null : 'Closed';
    if (openTimes.length > 1) return null; // genuinely varies; show it all

    final hours = openTimes.keys.first;
    if (closedDays.isEmpty) return 'Open $hours daily';
    return 'Open $hours · Closed ${closedDays.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            : _failed
                ? _buildFailed()
                : _buildDetails(),
      ),
    );
  }

  Widget _buildFailed() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey[500]),
          const SizedBox(height: 12),
          Text(widget.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            "Couldn't load details for this place — check the server is "
            'running, then try again.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      );

  Widget _buildDetails() {
    final place = _place!;
    final photos = (place['photos'] as List?) ?? const [];
    final reviews = (place['reviews'] as List?) ?? const [];
    final hours = (place['opening_hours'] as List?) ?? const [];
    final rating = (place['rating'] as num?)?.toDouble() ?? 0;
    final ratingCount = (place['total_ratings'] as num?)?.toInt() ?? 0;
    final address = (place['address'] ?? '').toString();

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((place['name'] ?? widget.name).toString(),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (rating > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text('$rating',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text('($ratingCount ratings)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(address,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ],

          if (photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  child: Image.network(
                    photos[i].toString(),
                    width: 200,
                    height: 140,
                    fit: BoxFit.cover,
                    // A photo that won't load leaves a plain grey box rather
                    // than a stand-in image of somewhere else.
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 140,
                      color: Colors.grey[200],
                    ),
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            width: 200,
                            height: 140,
                            color: Colors.grey[200],
                          ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openInMaps,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open in Google Maps'),
            ),
          ),

          if (hours.isNotEmpty) ...[
            const SizedBox(height: 16),
            Builder(builder: (_) {
              final summary = _hoursSummary(hours);
              if (summary != null) {
                return Row(
                  children: [
                    Icon(Icons.schedule, size: 15, color: Colors.grey[700]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(summary,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[800])),
                    ),
                  ],
                );
              }
              // Hours differ by day, so every line is worth showing.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Opening hours',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final line in hours)
                    Text(line.toString(),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[800])),
                ],
              );
            }),
          ],

          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('What people say',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final review in reviews.whereType<Map>().take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The reviewer's name is dropped. It tells a traveller
                    // nothing about the place and pushes the text they came
                    // for further down.
                    Row(
                      children: [
                        const Icon(Icons.star, size: 13, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text('${review['rating'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (review['text'] ?? '').toString(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
