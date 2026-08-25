import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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

  /// A suggested running order per day, keyed by ISO date.
  ///
  /// Requested on demand rather than built with the plan: it is a model call,
  /// and most openings of this screen are someone checking their trip rather
  /// than asking for it to be scheduled.
  Map<String, List<String>> _schedules = {};
  bool _scheduling = false;
  bool _exporting = false;

  /// The day currently having places found for it, so only its own button
  /// shows a spinner rather than every day at once.
  int? _fillingDay;

  /// The day currently being scheduled, so only its button spins.
  int? _schedulingDay;

  /// A built file waiting for the user to tap once more.
  ///
  /// Browsers only allow navigator.share() while handling a user gesture, and
  /// building the file takes seconds of network and rendering -- by the time
  /// it returns, the original tap has expired and the share is refused with
  /// NotAllowedError. So the work happens on the first tap and the share on a
  /// second one, which is still inside a gesture.
  Uint8List? _exportBytes;
  String _exportFormat = 'pdf';

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

  /// Asks for a running order, handing over every fixed point we hold.
  ///
  /// The confirmed flight time and the place's opening hours are what keep
  /// this honest: without them a "schedule" is just invented clock times.
  Future<void> _suggestSchedule(TripPlan plan, BookedTripProvider booked) async {
    setState(() => _scheduling = true);
    final days = plan.days.map((day) => _dayPayload(day, booked)).toList();

    final notes =
        await _adk.daySchedules(days: days, destination: plan.destination);
    if (!mounted) return;
    setState(() {
      _scheduling = false;
      if (notes == null) {
        _error = "Couldn't build a schedule — check the server is running.";
      } else {
        _error = null;
        _schedules = notes;
      }
    });
  }

  /// One day, described for the scheduler: its fixed points and its places.
  Map<String, dynamic> _dayPayload(PlanDay day, BookedTripProvider booked) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    String iso(DateTime d) => d.toIso8601String().split('T').first;

    final fixed = <String>[];
    for (final f
        in booked.flights.where((f) => sameDay(f.startDate, day.date))) {
      final t = f.departureTime;
      fixed.add(t == null || t.isEmpty
          ? 'Flight ${f.flightNumber ?? f.title} on this day, time unknown'
          : 'Flight ${f.flightNumber ?? f.title} departs $t');
    }
    for (final h
        in booked.hotels.where((h) => sameDay(h.startDate, day.date))) {
      fixed.add('Check in at ${h.hotelName ?? h.title}');
    }
    return {
        'date': iso(day.date),
        if (fixed.isNotEmpty) 'fixed': fixed,
        'items': day.items.map((i) {
          final hours = _todayHoursFor(i.title, day.date);
          // Google's own description of the place, so a line can say what
          // there is to do there rather than just naming it. Without this the
          // model either stays vague or invents attractions.
          final about =
              (_summaries[i.title]?['description'] ?? '').toString().trim();
          return {
            // The resolved name, so the running order can say where to
            // actually go rather than repeating a category back.
            'title': _placeName(i.title),
            if (hours != null) 'hours_today': hours,
            if (about.isNotEmpty) 'about': about,
          };
        }).toList(),
    };
  }

  /// The hours line for [title] on [date]'s weekday, if we have it.
  String? _todayHoursFor(String title, DateTime date) {
    final hours = (_summaries[title]?['hours'] as List?) ?? const [];
    if (hours.isEmpty) return null;
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final weekday = names[date.weekday - 1];
    for (final line in hours) {
      final text = line.toString();
      if (text.startsWith(weekday)) {
        return text.substring(weekday.length + 2).trim();
      }
    }
    return null;
  }

  /// Builds the plan as a file and hands it to the share sheet.
  ///
  /// The day cards are assembled here from what is already on screen, so the
  /// shared file shows exactly what the user is looking at -- same photos,
  /// same ratings, same running order.
  Future<void> _sharePlan(
      TripPlan plan, BookedTripProvider booked, String format) async {
    setState(() => _exporting = true);

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    String iso(DateTime d) => d.toIso8601String().split('T').first;

    final days = plan.days.map((day) {
      final fixed = <String>[];
      for (final f
          in booked.flights.where((f) => sameDay(f.startDate, day.date))) {
        final t = f.departureTime;
        fixed.add('${f.flightNumber ?? f.title}'
            '${t == null || t.isEmpty ? '' : '  ·  $t'}');
      }
      for (final h
          in booked.hotels.where((h) => sameDay(h.startDate, day.date))) {
        fixed.add('Check in  ·  ${h.hotelName ?? h.title}');
      }
      return {
        'date_label': _dayLabel.format(day.date),
        if (fixed.isNotEmpty) 'fixed': fixed,
        'items': day.items.map((i) {
          final summary = _summaries[i.title] ?? const {};
          return {
            'title': _placeName(i.title),
            if (summary['rating'] != null) 'rating': summary['rating'],
            if (summary['photo'] != null) 'photo': summary['photo'],
            // Every photo, not just the first. The film gives each
            // place two or three angles, and sending one meant it
            // rendered the same still repeatedly -- the feature only
            // ever worked when the payload was built by hand.
            if (summary['photos'] != null) 'photos': summary['photos'],
            if (summary['description'] != null)
              'about': summary['description'],
            if (_todayHoursFor(i.title, day.date) != null)
              'hours_today': _todayHoursFor(i.title, day.date),
          };
        }).toList(),
        'notes': _schedules[iso(day.date)] ?? const <String>[],
      };
    }).toList();

    final bytes = await _adk.exportPlan(
        days: days, format: format, destination: plan.destination);
    if (!mounted) return;

    if (bytes == null) {
      setState(() {
        _exporting = false;
        _error = "Couldn't build the $format — check the server is running.";
      });
      return;
    }

    setState(() {
      _exporting = false;
      _error = null;
      _exportFormat = format;
      _exportBytes = Uint8List.fromList(bytes);
    });
  }

  /// Hands the built file to the share sheet, called straight from a tap.
  ///
  /// Nothing is awaited before the share call, so the browser still sees this
  /// as part of the user's gesture.
  Future<void> _shareBuiltFile() async {
    final bytes = _exportBytes;
    if (bytes == null) return;
    final format = _exportFormat;
    try {
      // Shared straight from memory rather than written to disk first. This
      // app runs on Flutter web, where dart:io has no filesystem at all, so
      // a temp-file route would work on mobile and silently fail in the
      // browser -- which is where it is being used today.
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: 'triplix-trip.$format',
            mimeType: format == 'pdf' ? 'application/pdf' : 'video/mp4',
          )
        ],
        text: 'My Triplix trip',
      );
      if (mounted) setState(() => _exportBytes = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Sharing is blocked here — open the app on your phone, or '
            'use a browser that allows sharing. ($e)';
        _exportBytes = null;
      });
    }
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
        actions: [
          if (plan != null && !plan.isEmpty)
            _exporting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share this trip',
                    onSelected: (format) =>
                        _sharePlan(plan, booked, format),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'pdf', child: Text('Share as PDF')),
                      PopupMenuItem(
                          value: 'mp4', child: Text('Share as video')),
                    ],
                  ),
        ],
      ),
      body: plan == null || plan.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                // Offered, not run automatically. Building the running order
                // is a model call, and most openings of this screen are
                // someone checking their trip rather than asking for it to
                // be scheduled.
                if (_schedules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _scheduling
                            ? null
                            : () => _suggestSchedule(plan, booked),
                        icon: _scheduling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.schedule, size: 18),
                        label: Text(_scheduling
                            ? 'Working out the days...'
                            : 'Suggest a running order for each day'),
                      ),
                    ),
                  ),
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
                if (day.items.isEmpty) ...[
                  Text('Nothing planned yet',
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[500])),
                  const SizedBox(height: 6),
                  // Offered where the gap is felt, rather than sending the
                  // user back to the onboarding checklist to guess which
                  // other words map to good places. Ticking one interest
                  // yields one place, so a four-day trip built from "Lake"
                  // arrived with three empty days and no way forward.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _fillingDay == null
                          ? () => _fillDay(plan, index)
                          : null,
                      icon: _fillingDay == index
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_location_alt_outlined,
                              size: 16),
                      label: Text(_fillingDay == index
                          ? 'Finding places...'
                          : 'Find things to do on this day'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ]
                else
                  for (final item in day.items)
                    // Tappable: a plan that only lists names is a list, not
                    // something you can travel with. Opening a place shows
                    // its photos, rating, reviews, hours and map position -
                    // all from Google for that specific place.
                    InkWell(
                      onTap: () => PlaceDetailSheet.show(
                        context,
                        name: _placeName(item.title),
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
                                Text(_placeName(item.title),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                _whatYouCanDo(item.title),
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
                          // Edits live behind a menu rather than a swipe:
                          // a swipe that deletes is easy to trigger by
                          // accident while scrolling a long trip.
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert,
                                size: 18, color: Colors.grey[500]),
                            tooltip: 'Change this place',
                            onSelected: (choice) => _editItem(
                                plan, index, day.items.indexOf(item), choice),
                            itemBuilder: (_) => [
                              for (var d = 0; d < plan.days.length; d++)
                                if (d != index)
                                  PopupMenuItem(
                                      value: 'move:$d',
                                      child: Text('Move to Day ${d + 1}')),
                              const PopupMenuItem(
                                  value: 'remove', child: Text('Remove')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ),

                // Two or more stops with known positions make a route worth
                // opening; one stop is just a pin, and the place sheet
                // already offers that.
                // Suggested, and labelled so. A confirmed departure is a
                // fact; "leave around 13:00" is a guess, and the two must not
                // look alike on the same card.
                if ((_schedules[day.date.toIso8601String().split('T').first] ??
                        const [])
                    .isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius:
                          BorderRadius.circular(AppConfig.radiusSmall),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Suggested running order',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700])),
                        const SizedBox(height: 6),
                        for (final line in _schedules[
                                day.date.toIso8601String().split('T').first]!)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $line',
                                style: const TextStyle(
                                    fontSize: 12, height: 1.35)),
                          ),
                      ],
                    ),
                  ),
                ],

                // Per day as well as for the whole trip: after changing
                // one day, re-running every day costs a model call each for
                // no benefit.
                // Available on a day that already has places too: an
                // itinerary is rarely finished in one pass, and adding a
                // fourth stop should not mean emptying the day first.
                if (day.items.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _fillingDay == null
                          ? () => _fillDay(plan, index)
                          : null,
                      icon: _fillingDay == index
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_location_alt_outlined,
                              size: 16),
                      label: const Text('Add a place to this day'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _schedulingDay == null
                          ? () => _suggestDaySchedule(plan, booked, index)
                          : null,
                      icon: _schedulingDay == index
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.schedule, size: 16),
                      label: Text(_schedules[
                                  day.date.toIso8601String().split('T').first]
                              ?.isNotEmpty ==
                          true
                          ? 'Redo this day\'s order'
                          : 'Plan this day'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],

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
        .map((i) => _placeName(i.title))
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

  /// Fills an empty day with real places from the destination.
  ///
  /// Everything already in the plan is excluded, and the user's own chosen
  /// interests steer the search -- someone who ticked "Lake" gets lakes and
  /// parks, not nightlife. The results are marked as suggestions, because
  /// they were offered rather than chosen.
  Future<void> _fillDay(TripPlan plan, int dayIndex) async {
    setState(() {
      _fillingDay = dayIndex;
      _error = null;
    });

    final already = plan.days
        .expand((d) => d.items.map((i) => _placeName(i.title)))
        .toSet()
        .toList();
    final interests =
        context.read<UserPreferencesProvider>().preferences.selectedActivities;

    final found = await _adk.discoverPlaces(
      city: plan.destination,
      interests: interests,
      exclude: already,
      limit: 3,
    );
    if (!mounted) return;

    if (found == null || found.isEmpty) {
      setState(() {
        _fillingDay = null;
        _error = found == null
            ? "Couldn't look for places — check the server is running."
            : 'No more places found for this city.';
      });
      return;
    }

    setState(() => _fillingDay = null);

    // Offered, not imposed. Adding all three outright would put places on
    // someone's itinerary they never agreed to, which is the distinction
    // this app keeps everywhere else.
    final chosen = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PlacePickerSheet(
        places: found,
        dayLabel: _dayLabel.format(plan.days[dayIndex].date),
        onSearch: (query) => _adk.discoverPlaces(
          city: plan.destination,
          interests: [query],
          exclude: already,
          limit: 6,
        ),
      ),
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;

    // Seeded into the summaries cache so the new rows render with their
    // photo and rating immediately, rather than blank until the next fetch.
    final names = <String>[];
    for (final place in chosen) {
      final name = (place['name'] ?? '').toString();
      if (name.isEmpty) continue;
      names.add(name);
      _summaries[name] = place;
    }

    context.read<TripPlanProvider>().addItems(dayIndex, names);
    if (!mounted) return;
    setState(() {
      // The running order described a day that has just changed.
      _schedules = {};
      _summarisedFor = '';
    });
  }

  /// Builds a running order for one day only.
  ///
  /// The whole-trip button is still there, but a day the user has just
  /// changed is the one they want re-planned, and re-running every day to
  /// fix one of them costs a model call per day for no benefit.
  Future<void> _suggestDaySchedule(
      TripPlan plan, BookedTripProvider booked, int dayIndex) async {
    setState(() {
      _schedulingDay = dayIndex;
      _error = null;
    });

    final day = plan.days[dayIndex];
    final notes = await _adk.daySchedules(
      days: [_dayPayload(day, booked)],
      destination: plan.destination,
    );
    if (!mounted) return;

    setState(() {
      _schedulingDay = null;
      if (notes == null) {
        _error = "Couldn't build the order — check the server is running.";
      } else {
        _schedules = {..._schedules, ...notes};
      }
    });
  }

  /// Applies a menu choice to one place.
  ///
  /// The running order is cleared afterwards because it described the old
  /// arrangement: leaving "09:30 head to the temple" under a day the temple
  /// has just left would be worse than showing no order at all.
  void _editItem(TripPlan plan, int dayIndex, int itemIndex, String choice) {
    final provider = context.read<TripPlanProvider>();
    if (choice == 'remove') {
      provider.removeItem(dayIndex, itemIndex);
    } else if (choice.startsWith('move:')) {
      final target = int.tryParse(choice.substring(5));
      if (target == null) return;
      provider.moveItem(dayIndex, itemIndex, target);
    } else {
      return;
    }
    setState(() {
      _schedules = {};
      // Forces the summaries to be re-checked against the new arrangement.
      _summarisedFor = '';
    });
  }

  /// The real place behind a plan entry.
  ///
  /// Onboarding collects categories -- "Nature Trail", "Temple", "Park" --
  /// not places, so a day could read "Nature Trail" while showing the photo,
  /// rating and hours of an actual named venue Google matched it to. The
  /// name is the one part that was still generic, which made the plan
  /// unusable: nobody can travel to "Nature Trail".
  String _placeName(String title) {
    final resolved = (_summaries[title]?['name'] ?? '').toString().trim();
    return resolved.isEmpty ? title : resolved;
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

  /// What the place actually is, in Google's own words.
  ///
  /// This is Google's editorial description, not a generated one: asking a
  /// model what a place is like invites a confident sentence about somewhere
  /// it has never seen, which is the one thing this app does not do.
  ///
  /// Many smaller places have no description. Those fall back to the place
  /// types Google assigns -- "Hindu temple, tourist attraction" is thin but
  /// true -- and a place with neither simply shows nothing.
  Widget _whatYouCanDo(String title) {
    final summary = _summaries[title];
    if (summary == null) return const SizedBox.shrink();

    final description = (summary['description'] ?? '').toString().trim();
    if (description.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, height: 1.3, color: Colors.grey[800]),
        ),
      );
    }

    final types = ((summary['types'] as List?) ?? const [])
        .map((t) => t.toString().replaceAll('_', ' '))
        .where((t) => t.isNotEmpty)
        .toList();
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        types.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.grey[700]),
      ),
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
          // Shown until tapped: the second gesture the browser requires.
          if (_exportBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _shareBuiltFile,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text('Your ${_exportFormat.toUpperCase()} is ready — '
                      'tap to share or save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
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

/// Lets the user choose which discovered places go on a day.
///
/// Everything found is shown with its photo, rating and description so the
/// choice is informed, and nothing is ticked to begin with -- a pre-ticked
/// list is a default dressed up as a decision, and these are places the user
/// has never seen before.
class _PlacePickerSheet extends StatefulWidget {
  const _PlacePickerSheet({
    required this.places,
    required this.dayLabel,
    required this.onSearch,
  });

  final List<Map<String, dynamic>> places;
  final String dayLabel;

  /// Looks up places matching typed text, so someone who already knows where
  /// they want to go is not restricted to what was suggested.
  final Future<List<Map<String, dynamic>>?> Function(String query) onSearch;

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final Set<int> _selected = {};
  final TextEditingController _query = TextEditingController();

  late List<Map<String, dynamic>> _shown = widget.places;
  Timer? _debounce;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _shown = widget.places;
        _selected.clear();
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() => _searching = true);
    // 400ms: each keystroke past this is a Places search, and the results
    // only become meaningful once a few characters are in.
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final found = await widget.onSearch(query);
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _searching = false;
        if (found == null) {
          _searchError = "Couldn't search — check the server is running.";
        } else {
          _searchError = found.isEmpty ? 'Nothing found for "$query".' : null;
          // Selection is indices into the visible list, so it has to reset
          // when that list changes or the wrong place would be added.
          _selected.clear();
          _shown = found;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add to ${widget.dayLabel}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Pick the ones you want, or search for somewhere specific.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 10),
          TextField(
            controller: _query,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search a place to add',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
              ),
            ),
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 8),
            Text(_searchError!,
                style: TextStyle(fontSize: 12, color: Colors.orange[800])),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < _shown.length; i++) _tile(i, _shown[i]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context)
                      .pop([for (final i in _selected) _shown[i]]),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
              ),
              child: Text(_selected.isEmpty
                  ? 'Select at least one'
                  : 'Add ${_selected.length} to this day'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(int index, Map<String, dynamic> place) {
    final selected = _selected.contains(index);
    final photo = (place['photo'] ?? '').toString();
    final rating = (place['rating'] as num?)?.toDouble() ?? 0;
    final count = (place['total_ratings'] as num?)?.toInt() ?? 0;
    final about = (place['description'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: selected
          ? AppConfig.primaryColor.withValues(alpha: 0.08)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
        side: BorderSide(
          color: selected ? AppConfig.primaryColor : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
        onTap: () => setState(() {
          if (!_selected.remove(index)) _selected.add(index);
        }),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  child: Image.network(photo,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      // No stand-in image: a grey box is honest about a photo
                      // that would not load.
                      errorBuilder: (_, __, ___) => Container(
                          width: 52, height: 52, color: Colors.grey[200])),
                )
              else
                Container(width: 52, height: 52, color: Colors.grey[200]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((place['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (rating > 0)
                      Text('$rating ★ ($count)',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[700])),
                    if (about.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(about,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[800])),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppConfig.primaryColor : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
