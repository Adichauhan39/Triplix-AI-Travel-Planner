import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../models/user_preferences.dart';
import '../providers/booked_trip_provider.dart';
import '../providers/trip_plan_provider.dart';
import '../providers/user_preferences_provider.dart';
import '../services/python_adk_service.dart';
import '../widgets/place_detail_sheet.dart';

/// The trip, day by day, built from the activities the user chose.
///
/// Shown rather than asked for: the plan is assembled from what onboarding
/// already collected — destination, dates and selected activities — so the
/// user opens this screen to a finished trip instead of another form. The
/// prompt box at the bottom is how they change it.
class TripPlanScreen extends StatefulWidget {
  const TripPlanScreen({super.key});

  @override
  State<TripPlanScreen> createState() => _TripPlanScreenState();
}

class _TripPlanScreenState extends State<TripPlanScreen> {
  final TextEditingController _requestController = TextEditingController();
  final PythonADKService _adk = PythonADKService();

  static final DateFormat _dayLabel = DateFormat('EEE, d MMM');

  bool _applying = false;
  String? _error;

  /// Photo, rating and hours for each place in the plan, keyed by its title.
  ///
  /// Fetched for the whole plan in one request so a day shows what it is
  /// without the user opening each place in turn. Empty until it arrives;
  /// the rows render fine without it and fill in when it lands.
  Map<String, Map<String, dynamic>> _summaries = {};
  String _summarisedFor = '';

  /// Set when the summaries request failed, so missing photos and ratings
  /// read as a problem to fix rather than as places Google knows nothing
  /// about. Grey boxes with no explanation are indistinguishable from a
  /// genuinely photo-less plan.
  bool _summariesFailed = false;

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  /// Rebuilds the plan whenever the trip's inputs change.
  ///
  /// This used to run once in initState, which is wrong for this screen: the
  /// Trip tab is built when the home screen first loads, so anyone who filled
  /// in onboarding afterwards -- or changed their dates later -- kept looking
  /// at "No trip yet" until the app was restarted.
  ///
  /// Scheduled after the frame because writing to one provider while building
  /// from another throws "setState during build". TripPlanProvider ignores a
  /// rebuild whose inputs match what it already holds, so this is safe on
  /// every build and won't discard edits the user has made.
  void _syncPlan(UserPreferences prefs) {
    final start = prefs.checkInDate;
    final end = prefs.checkOutDate;
    if (start == null || end == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TripPlanProvider>().buildFromSelection(
            destination: prefs.destination ?? '',
            start: start,
            end: end,
            activities: prefs.selectedActivities,
          );
    });
  }

  /// Names the input that is actually missing, so an empty screen explains
  /// itself instead of listing everything the user might need to do.
  String _missingInputMessage() {
    final prefs = context.read<UserPreferencesProvider>().preferences;
    if (prefs.checkInDate == null || prefs.checkOutDate == null) {
      return 'Add your travel dates in Plan your trip, and your day-by-day '
          'itinerary appears here.';
    }
    if ((prefs.destination ?? '').isEmpty) {
      return 'Choose where you are going, and your day-by-day itinerary '
          'appears here.';
    }
    return 'Pick a few things to do in Plan your trip, and they will be '
        'spread across your days here.';
  }

  /// Loads the photo/rating/hours for every place currently in the plan.
  ///
  /// Keyed on the plan's contents, so it re-runs when the plan changes and
  /// does nothing when it hasn't -- including on every rebuild of this screen.
  Future<void> _loadSummaries(TripPlan plan) async {
    final names = plan.days
        .expand((d) => d.items.map((i) => i.title))
        .where((t) => t.trim().isNotEmpty)
        .toSet()
        .toList();
    final signature = '${plan.destination}|${names.join('|')}';
    if (names.isEmpty || signature == _summarisedFor) return;
    _summarisedFor = signature;

    final found = await _adk.placeSummaries(
        city: plan.destination, names: names);
    if (!mounted) return;
    if (found == null) {
      // Retried on the next plan change: clearing the signature means a
      // restarted server is picked up without reopening the screen.
      _summarisedFor = '';
      setState(() => _summariesFailed = true);
      return;
    }
    setState(() {
      _summariesFailed = false;
      _summaries = {..._summaries, ...found};
    });
  }

  Future<void> _applyRequest() async {
    final request = _requestController.text.trim();
    final plan = context.read<TripPlanProvider>().plan;
    if (request.isEmpty || plan == null) return;

    setState(() {
      _applying = true;
      _error = null;
    });

    final updated = await _adk.adjustPlan(
      days: plan.toJson(),
      request: request,
      destination: plan.destination,
    );
    if (!mounted) return;

    setState(() {
      _applying = false;
      if (updated == null) {
        // The plan on screen is left exactly as it was. Replacing it with
        // nothing because a request failed would lose the user's own picks.
        _error = "Couldn't apply that change — check the server is running.";
      } else {
        _requestController.clear();
        context
            .read<TripPlanProvider>()
            .replaceDays(updated.map(PlanDay.fromJson).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: a trip filled in after this screen was built has to
    // appear without the user restarting the app.
    final prefs = context.watch<UserPreferencesProvider>().preferences;
    _syncPlan(prefs);

    // The confirmed flight and hotel, when there are any. A trip with none
    // renders exactly as before: nothing is invented to fill the space.
    final booked = context.watch<BookedTripProvider>();
    final plan = context.watch<TripPlanProvider>().plan;
    if (plan != null && !plan.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadSummaries(plan));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(plan?.destination.isNotEmpty == true
            ? 'Your trip to ${plan!.destination.split(',').first}'
            : 'Your trip'),
        centerTitle: true,
      ),
      body: plan == null || plan.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                Expanded(child: _buildDays(plan, booked)),
                _buildRequestBar(),
              ],
            ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No trip yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Text(
                _missingInputMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );

  Widget _buildDays(TripPlan plan, BookedTripProvider booked) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      itemCount: plan.days.length + (_summariesFailed ? 1 : 0),
      itemBuilder: (context, rawIndex) {
        if (_summariesFailed && rawIndex == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.image_not_supported_outlined,
                    size: 18, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Photos and ratings could not be loaded — check the '
                    'server is running, then reopen this tab.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          );
        }
        final index = rawIndex - (_summariesFailed ? 1 : 0);
        final day = plan.days[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppConfig.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Day ${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Text(_dayLabel.format(day.date),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[700])),
                  ],
                ),
                _daySummary(day, booked),
                const SizedBox(height: 10),

                // What the user actually booked, on the day it happens.
                // Only rendered when it exists — an itinerary that shows a
                // flight nobody confirmed is a guess, and this app does not
                // guess about bookings.
                ..._bookedRowsFor(day.date, booked),
                // An empty day is shown as empty rather than hidden — it is a
                // true statement about the trip, and a missing Day 3 would
                // misrepresent how long they are staying.
                if (day.items.isEmpty)
                  Text('Nothing planned yet',
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[500]))
                else
                  for (final item in day.items)
                    // Tappable: a plan that only lists names is a list, not
                    // something you can travel with. Opening a place shows
                    // its photos, rating, reviews, hours and map position -
                    // all from Google for that specific place.
                    InkWell(
                      onTap: () => PlaceDetailSheet.show(
                        context,
                        name: item.title,
                        city: plan.destination,
                      ),
                      child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _thumbnail(item.title),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                _subtitleFor(item.title),
                              ],
                            ),
                          ),
                          // Marked, because we haven't checked it exists —
                          // the user's own picks came from real Places
                          // results, a suggested one did not.
                          if (item.addedByAssistant)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('suggested',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.amber.shade900)),
                            ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 16, color: Colors.grey[400]),
                        ],
                      ),
                    ),
                    ),

                // Two or more stops with known positions make a route worth
                // opening; one stop is just a pin, and the place sheet
                // already offers that.
                if (_mappableStops(day) > 1) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openDayRoute(day),
                      icon: const Icon(Icons.directions, size: 16),
                      label: Text(
                          'Route for this day · ${_mappableStops(day)} stops'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// A one-line description of the day, built only from facts already held.
  ///
  /// No estimated distances or durations: a straight line between two
  /// coordinates is not a road, and this line would be the most-read text on
  /// the screen. It says how many places there are, whether a booked leg
  /// falls on this day, and -- the part worth having -- whether any of those
  /// places is closed on this particular date.
  Widget _daySummary(PlanDay day, BookedTripProvider booked) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final parts = <String>[];

    if (booked.flights.any((f) => sameDay(f.startDate, day.date))) {
      parts.add('Flight day');
    }
    if (booked.hotels.any((h) => sameDay(h.startDate, day.date))) {
      parts.add('Check-in');
    }

    final count = day.items.length;
    if (count > 0) parts.add(count == 1 ? '1 place' : '$count places');

    final closed = day.items
        .where((i) => _isClosedOn(i.title, day.date))
        .map((i) => i.title)
        .toList();

    if (parts.isEmpty && closed.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isNotEmpty)
            Text(parts.join('  ·  '),
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          // The warning that actually saves a trip: turning up somewhere on
          // the one day of the week it does not open.
          for (final name in closed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: Colors.orange[800]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('$name is closed on this day',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[800])),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Whether Google lists [title] as closed on [date]'s weekday.
  ///
  /// Only true when we actually have the hours and the line says closed --
  /// a place we know nothing about is never reported as shut.
  bool _isClosedOn(String title, DateTime date) {
    final hours = (_summaries[title]?['hours'] as List?) ?? const [];
    if (hours.isEmpty) return false;
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final weekday = names[date.weekday - 1];
    for (final line in hours) {
      final text = line.toString();
      if (text.startsWith(weekday)) {
        return text.toLowerCase().contains('closed');
      }
    }
    return false;
  }

  /// Opens the day's stops as a route in Google Maps.
  ///
  /// The distances and times come from Google rather than from us. A
  /// straight line between two coordinates is not a road, and printing "4 km"
  /// for a drive that is really nine would be a made-up number on a screen
  /// whose whole point is that it is true. Google's own route is free,
  /// accurate, traffic-aware, and opens in the app people navigate with.
  Future<void> _openDayRoute(PlanDay day) async {
    final stops = day.items
        .map((i) => _summaries[i.title])
        .whereType<Map<String, dynamic>>()
        .where((s) => s['lat'] != null && s['lng'] != null)
        .map((s) => '${s['lat']},${s['lng']}')
        .toList();
    if (stops.isEmpty) return;

    // Maps takes the last stop as the destination and the rest as waypoints.
    final params = <String, String>{
      'api': '1',
      'destination': stops.last,
      'travelmode': 'driving',
      if (stops.length > 1) 'origin': stops.first,
      if (stops.length > 2)
        'waypoints': stops.sublist(1, stops.length - 1).join('|'),
    };
    await launchUrl(Uri.https('www.google.com', '/maps/dir/', params),
        mode: LaunchMode.externalApplication);
  }

  /// How many of a day's stops we have coordinates for.
  int _mappableStops(PlanDay day) => day.items
      .map((i) => _summaries[i.title])
      .whereType<Map<String, dynamic>>()
      .where((s) => s['lat'] != null && s['lng'] != null)
      .length;

  /// Flight and hotel entries that fall on [date].
  ///
  /// A flight lands on its own date. A hotel spans the stay, so it appears
  /// once as a check-in on the first night rather than repeating on every
  /// day, which would bury the actual plan under the same line six times.
  List<Widget> _bookedRowsFor(DateTime date, BookedTripProvider booked) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final rows = <Widget>[];

    for (final flight in booked.flights) {
      if (!sameDay(flight.startDate, date)) continue;
      final number = flight.flightNumber;
      final time = flight.departureTime;
      rows.add(_bookedRow(
        icon: Icons.flight_takeoff,
        title: number == null || number.isEmpty
            ? flight.title
            : '${flight.title} · $number',
        // "Time not recorded" rather than a plausible-looking default: the
        // user pressed "I don't have it yet", and inventing 09:00 here would
        // put a departure on their itinerary that nobody ever confirmed.
        subtitle: time == null || time.isEmpty
            ? 'Booked · time not recorded'
            : 'Departs $time',
        verified: flight.flightIsRealFlight,
      ));
    }

    for (final hotel in booked.hotels) {
      if (!sameDay(hotel.startDate, date)) continue;
      rows.add(_bookedRow(
        icon: Icons.hotel,
        title: hotel.hotelName ?? hotel.title,
        subtitle: hotel.endDate == null
            ? 'Check in'
            : 'Check in · until ${_dayLabel.format(hotel.endDate!)}',
        verified: hotel.hotelNameIsRealPlace,
      ));
    }

    if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
    return rows;
  }

  Widget _bookedRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool verified,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppConfig.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
        border: Border.all(
            color: AppConfig.primaryColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppConfig.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              ],
            ),
          ),
          // The same distinction the booking flow draws: a flight tapped from
          // the real schedule is not the same as a number typed from memory.
          if (!verified)
            Tooltip(
              message: 'As you typed it — we could not check this',
              child: Icon(Icons.help_outline,
                  size: 15, color: Colors.orange[700]),
            ),
        ],
      ),
    );
  }

  /// The place's own photo, or a grey box.
  ///
  /// Never a stand-in image: a stock photo of somewhere else looks exactly
  /// like the real thing, and the whole plan is meant to be true.
  Widget _thumbnail(String title) {
    final photo = (_summaries[title]?['photo'] ?? '').toString();
    final placeholder = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
      ),
      child: Icon(Icons.place_outlined, size: 20, color: Colors.grey[500]),
    );
    if (photo.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
      child: Image.network(photo,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder),
    );
  }

  /// Rating and today's hours, when we have them.
  Widget _subtitleFor(String title) {
    final summary = _summaries[title];
    if (summary == null) return const SizedBox.shrink();

    final rating = (summary['rating'] as num?)?.toDouble() ?? 0;
    final count = (summary['total_ratings'] as num?)?.toInt() ?? 0;
    final hours = (summary['hours'] as List?) ?? const [];
    final today = _todayHours(hours);

    final parts = <String>[
      if (rating > 0) '$rating ★ ($count)',
      if (today != null) today,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(parts.join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.grey[700])),
    );
  }

  /// Today's line from Google's seven, matched by weekday name because the
  /// list does not always start on the same day.
  String? _todayHours(List<dynamic> hours) {
    if (hours.isEmpty) return null;
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final today = names[DateTime.now().weekday - 1];
    for (final line in hours) {
      final text = line.toString();
      if (text.startsWith(today)) {
        return text.substring(today.length + 2).trim();
      }
    }
    return null;
  }

  Widget _buildRequestBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: Colors.orange[800]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange[800])),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _requestController,
                  enabled: !_applying,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _applyRequest(),
                  decoration: InputDecoration(
                    hintText: 'e.g. move the palace to Day 2',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _applying
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _applyRequest,
                      icon: const Icon(Icons.arrow_upward),
                      style: IconButton.styleFrom(
                        backgroundColor: AppConfig.primaryColor,
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
