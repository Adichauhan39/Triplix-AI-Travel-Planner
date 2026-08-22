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

  final TextEditingController _question = TextEditingController();
  bool _asking = false;
  String? _answer;
  bool _answerFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  /// Sends the question along with what we already know about the place, so
  /// hours, address and rating are answered from data rather than recalled.
  Future<void> _ask() async {
    final text = _question.text.trim();
    if (text.isEmpty || _asking) return;
    setState(() {
      _asking = true;
      _answer = null;
      _answerFailed = false;
    });

    final place = _place ?? const {};
    final reply = await _adk.askAboutPlace(
      place: (place['name'] ?? widget.name).toString(),
      city: widget.city,
      question: text,
      facts: {
        if (place['address'] != null) 'address': place['address'],
        if (place['rating'] != null) 'rating': place['rating'],
        if (place['total_ratings'] != null)
          'total_ratings': place['total_ratings'],
        if (place['opening_hours'] != null)
          'opening_hours': place['opening_hours'],
        if (place['phone'] != null) 'phone': place['phone'],
        if (place['website'] != null) 'website': place['website'],
      },
    );
    if (!mounted) return;
    setState(() {
      _asking = false;
      _answer = reply;
      _answerFailed = reply == null;
    });
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

  /// The one line from Google's seven that applies to today.
  ///
  /// Each line reads "Monday: 9:00 AM - 6:00 PM", so it is matched by the
  /// weekday name rather than by position -- Google does not always start
  /// the list on the same day.
  String? _todayHours(List<dynamic> hours) {
    if (hours.isEmpty) return null;
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final today = names[DateTime.now().weekday - 1];
    for (final line in hours) {
      final text = line.toString();
      if (text.startsWith(today)) return 'Today: ${text.substring(today.length + 2).trim()}';
    }
    return null;
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

          // Today only. Google returns all seven days, but six of them are
          // about a day the user is not standing there on -- it filled the
          // sheet and buried the reviews underneath it.
          if (_todayHours(hours) != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.schedule, size: 15, color: Colors.grey[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_todayHours(hours)!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[800])),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),
          const Text('Ask about this place',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _question,
                  enabled: !_asking,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    hintText: 'e.g. is there parking?',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _asking
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _ask,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      style: IconButton.styleFrom(
                          backgroundColor: AppConfig.primaryColor),
                    ),
            ],
          ),
          if (_answer != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(_answer!,
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
            const SizedBox(height: 4),
            // Said plainly. The answer is grounded in Google Places data and
            // a web search, but it is still assembled by a model, and the
            // reader deserves to know which parts of this sheet are checked
            // facts and which are not.
            Text('Answered using Google data and a web search — check '
                'anything important.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
          ],
          if (_answerFailed) ...[
            const SizedBox(height: 8),
            Text("Couldn't answer that just now — check the server is running.",
                style: TextStyle(fontSize: 12, color: Colors.orange[800])),
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
                    // No reviewer name. It identifies a stranger the user
                    // will never meet and pushes the thing they came to read
                    // -- the rating and what was said -- down the sheet.
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
