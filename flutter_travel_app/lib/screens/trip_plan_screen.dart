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
import '../services/local_store.dart';
import '../services/python_adk_service.dart';
import '../services/trip_sync.dart';
import '../widgets/place_detail_sheet.dart';
import '../widgets/trip_access_requests.dart';
import '../widgets/trip_expenses.dart';
import 'shared_trip_screen.dart';

/// The positions of [names], sorted by where each is first named in [notes].
///
/// Top level and pure so the ordering can be tested directly: matching place
/// names inside free text has enough edge cases -- one name contained in
/// another, a place the schedule never mentions -- that eyeballing the day
/// card is not evidence it is right.
///
/// Anything unmentioned sorts to the end, keeping its existing order rather
/// than being dropped or shuffled.
List<int> runningOrderIndices(List<String> names, List<String> notes) {
  final running = notes.join('\n').toLowerCase();
  const unmentioned = 1 << 30;

  int mentionedAt(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return unmentioned;
    final at = running.indexOf(needle);
    return at < 0 ? unmentioned : at;
  }

  // Longest name first when two share a position: "Hotel Amit Park" contains
  // "Amit Park", so the shorter one can match at the same index and steal the
  // place of the longer. Preferring the longer match keeps the pair in the
  // order the schedule actually names them.
  final order = List<int>.generate(names.length, (i) => i);
  order.sort((a, b) {
    final byMention = mentionedAt(names[a]).compareTo(mentionedAt(names[b]));
    if (byMention != 0) return byMention;
    final byLength = names[b].length.compareTo(names[a].length);
    if (byLength != 0 && mentionedAt(names[a]) != unmentioned) return byLength;
    // Ties keep their original order, so the sort is stable and two places
    // named in the same line do not swap between rebuilds.
    return a.compareTo(b);
  });
  return order;
}

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

  /// The export being rendered on the server, if any.
  ///
  /// A film takes one to three and a half minutes, so it runs as a job the
  /// server owns and we poll. Holding the request open instead used to time
  /// out at 180s, which meant a five-day trip could not be exported at all.
  String? _exportJobId;
  double _exportProgress = 0;
  String _exportStage = '';
  Timer? _exportPoll;

  /// The plan as it was when the current render started, and whether the user
  /// has already been asked about the difference. Asked once per job, not once
  /// per edit: people change several things in a row, and a dialog per change
  /// would be unusable.
  String _exportPlanKey = '';
  bool _exportEditPrompted = false;

  /// Guards the one-time reattach, so a rebuild does not restart polling.
  bool _resumedExport = false;

  /// The plan whose days have already been ordered geographically.
  String _arrangedFor = '';

  /// The whole-trip map, and the plan it was drawn for.
  Uint8List? _tripMap;
  String _tripMapFor = '';

  /// The day currently having places found for it, so only its own button
  /// shows a spinner rather than every day at once.
  int? _fillingDay;

  /// The day currently being scheduled, so only its button spins.
  int? _schedulingDay;

  /// The trip whose interests have already been expanded into places, so a
  /// rebuild of this screen does not fetch them again.
  String _expandedFor = '';

  /// Places per day. Two is the floor: one place is somewhere to eat, not
  /// a day out. Raised only if the user says they want fuller days.
  int _minPerDay = 2;

  /// Where the traveller sleeps, when they have no booking in the app.
  ///
  /// Free text on purpose -- "my cousin's place in Sector 7" is a real answer
  /// and not a hotel. Used to name the start of each day, and to anchor the
  /// route so the nearest place to the bed leads the morning.
  String _stayingAt = '';

  /// How the traveller leaves at the end of the trip, when they have told us.
  ///
  /// Holds mode, time and place. Kept apart from booked flights because this
  /// is something typed in a sentence rather than confirmed against a real
  /// booking -- most Indian trips end on a train, and none of those pass
  /// through the flight sheet.
  Map<String, dynamic>? _departure;

  /// Whether the one gap question has been put to the user for this trip.
  String _askedFor = '';

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
    _exportPoll?.cancel();
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

  /// Turns the chosen interests into enough real places to cover the trip.
  ///
  /// A category resolves to a single place, so a trip built from one or two
  /// interests arrived mostly empty. This asks for enough places of those
  /// kinds to give every day something, and fills only the days that have
  /// nothing -- a day the user has already arranged is left alone.
  ///
  /// Runs once per trip. The guard is the destination and the interests, so
  /// changing either expands again and a plain rebuild does not.
  /// Whether this screen is the one the user is actually looking at.
  ///
  /// The trip tab lives in an IndexedStack, so it keeps building while the
  /// user is on Bookings or Account -- and a sheet opened from here appears
  /// over whatever is on top. It surfaced over the Account page, on top of a
  /// sign-out dialog.
  ///
  /// TickerMode is set per tab by the home screen; isCurrent covers the other
  /// half, where a dialog or a pushed page sits above the whole tab bar.
  bool get _isVisible {
    if (!mounted) return false;
    if (!TickerMode.of(context)) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  /// Asks the one thing we cannot work out for ourselves, and only when it
  /// would change the plan.
  ///
  /// The trip screen used to present whatever it had: one restaurant on a day,
  /// a running order built around it, and a share button beside it. Filling
  /// the gap needs exactly one fact -- how full a day should be -- so that is
  /// the only thing asked. Everything else is either already known (the dates,
  /// the hotel, the flight) or guessable from it.
  ///
  /// Asked once per trip and remembered on the device: a question that returns
  /// every time the screen is opened is worse than no question at all.
  /// Reattaches to a render that was already running.
  ///
  /// The job lives on the server, so coming back to this screen -- or
  /// reopening the app -- should find the film waiting rather than starting
  /// again. A job the server has since forgotten simply clears.
  void _resumeExport() {
    if (_exportJobId != null || _resumedExport) return;
    _resumedExport = true;
    final stored = LocalStore.load(LocalStore.keyExportJob);
    final jobId = (stored?['job_id'] ?? '').toString();
    if (jobId.isEmpty) return;
    setState(() {
      _exportJobId = jobId;
      _exportFormat = (stored?['format'] ?? 'mp4').toString();
      _exportStage = 'Still working';
    });
    _pollExport();
  }

  /// Opens the whole trip full screen, pinnable and zoomable.
  ///
  /// A pinch-zoomable image rather than a live map: the Maps key stays on the
  /// server, and a static render is one billed request instead of a tile
  /// stream. Google Maps itself is one tap away for anyone who wants to
  /// actually navigate, which is the thing a picture cannot do.
  Future<void> _openTripMap(TripPlan plan) async {
    final image = _tripMap;
    if (image == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TripMapDialog(
        plan: plan,
        initialImage: image,
        adk: _adk,
        coords: _mapCoords(plan),
        placeName: _placeName,
        onOpenInMaps: () => _openWholeTripInMaps(plan),
      ),
    );
  }

  /// Each place in the plan as a point, for asking the server to redraw one
  /// day. Built from the summaries already loaded, so switching days costs a
  /// map request and nothing else.
  Map<String, List<double>> _mapCoords(TripPlan plan) {
    final coords = <String, List<double>>{};
    for (final entry in _summaries.entries) {
      final lat = (entry.value['lat'] as num?)?.toDouble();
      final lng = (entry.value['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) coords[entry.key] = [lat, lng];
    }
    return coords;
  }

  /// The pin colour for a day. Mirrors the server palette, so the key on
  /// screen and the pins on the map cannot disagree.
  Color _dayColour(int dayIndex) {
    const palette = [
      Color(0xFF0D0D82), Color(0xFFD62D20), Color(0xFF008744),
      Color(0xFFFFA700), Color(0xFF9C27B0), Color(0xFF00838F),
      Color(0xFF795548), Color(0xFFC2185B),
    ];
    return palette[dayIndex % palette.length];
  }

  /// Hands the whole trip to Google Maps, where it can actually be navigated.
  Future<void> _openWholeTripInMaps(TripPlan plan) async {
    final stops = [
      for (final day in plan.days)
        for (final item in day.items) _placeName(item.title)
    ].where((s) => s.isNotEmpty).toList();
    if (stops.isEmpty) return;

    // Maps takes an origin, a destination and waypoints between them.
    final params = <String, String>{
      'api': '1',
      'origin': stops.first,
      'destination': stops.last,
      if (stops.length > 2)
        'waypoints': stops.sublist(1, stops.length - 1).take(8).join('|'),
    };
    await launchUrl(Uri.https('www.google.com', '/maps/dir/', params),
        mode: LaunchMode.externalApplication);
  }

  /// Draws every stop on one map, grouped by day.
  ///
  /// A list of days tells you what you are doing; this tells you where the
  /// trip is. Three days clustered in one corner and a fourth an hour away is
  /// obvious on a map and invisible in a list.
  ///
  /// Fetched once per plan. It is a billed map request, and redrawing it on
  /// every rebuild would spend one per scroll.
  Future<void> _loadTripMap(TripPlan plan, Map<String, List<double>> coords) async {
    final key = context.read<TripPlanProvider>().contentKey;
    if (key.isEmpty || key == _tripMapFor) return;
    _tripMapFor = key;

    final days = [
      for (final day in plan.days)
        {
          'items': [
            for (final item in day.items)
              if (coords[item.title] != null)
                {
                  'lat': coords[item.title]![0],
                  'lng': coords[item.title]![1],
                }
          ]
        }
    ];
    if (days.every((d) => (d['items'] as List).isEmpty)) return;

    final bytes = await _adk.tripMap(days);
    if (!mounted || bytes == null) return;
    setState(() => _tripMap = Uint8List.fromList(bytes));
  }

  /// Where the trip ends: a typed departure if there is one, otherwise the
  /// airport when a booked flight leaves on the last day.
  ///
  /// A typed departure wins because it is more specific -- somebody who says
  /// "train from Durg" has told us the exact building, where a flight only
  /// implies the city's airport.
  String _departurePlace(TripPlan plan) {
    final typed = _departure;
    if (typed != null) {
      final place = (typed['place'] ?? '').toString().trim();
      if (place.isNotEmpty) return place;
      // Mode without a place: a train still means a station, not an airport.
      final mode = (typed['mode'] ?? '').toString();
      final city = plan.destination.split(',').first.trim();
      if (mode == 'train') return '$city railway station';
      if (mode == 'bus') return '$city bus stand';
      if (mode == 'flight') return '$city airport';
    }
    if (_leavesByAir(plan)) {
      return '${plan.destination.split(',').first} airport';
    }
    return '';
  }

  /// Whether a booked flight leaves on the trip's last day.
  ///
  /// Only then does the airport decide where the trip should finish. A trip
  /// someone is driving home from has no such constraint, and pulling its
  /// final day towards an airport would be actively wrong.
  bool _leavesByAir(TripPlan plan) {
    if (plan.days.isEmpty) return false;
    final last = plan.days.last.date;
    return context.read<BookedTripProvider>().flights.any((f) =>
        f.startDate.year == last.year &&
        f.startDate.month == last.month &&
        f.startDate.day == last.day);
  }

  /// A named place as a point on the map.
  ///
  /// Resolved through the same summaries call as everywhere else, and cached
  /// in [_summaries] so a trip costs one lookup rather than one per rebuild.
  Future<List<double>?> _resolvePoint(String key, String destination) async {
    if (key.isEmpty || destination.isEmpty) return null;
    final cached = _summaries[key];
    final clat = (cached?['lat'] as num?)?.toDouble();
    final clng = (cached?['lng'] as num?)?.toDouble();
    if (clat != null && clng != null) return [clat, clng];

    final found =
        await _adk.placeSummaries(city: destination, names: [key]);
    final resolved = found?[key];
    if (resolved == null) return null;
    _summaries[key] = resolved;
    final lat = (resolved['lat'] as num?)?.toDouble();
    final lng = (resolved['lng'] as num?)?.toDouble();
    return (lat != null && lng != null) ? [lat, lng] : null;
  }

  /// Where the traveller sleeps on this trip: their booking if they made
  /// one through the app, otherwise whatever they told us.
  String _stayFor(TripPlan plan) {
    final booked = context.read<BookedTripProvider>().hotels;
    if (booked.isNotEmpty) {
      return (booked.first.hotelName ?? booked.first.title).trim();
    }
    return _stayingAt.trim();
  }

  /// Asks where they are staying, when no booking tells us.
  ///
  /// Without it a day reads "set off from where you are staying", which is
  /// honest but vague, and the route starts from whichever place happens to be
  /// listed first rather than from the bed. One question, once, and only when
  /// there is no hotel booked for the trip.
  Future<void> _askWhereStaying(TripPlan plan, BookedTripProvider booked) async {
    if (_stayingAt.isNotEmpty || booked.hotels.isNotEmpty) return;

    final stored = LocalStore.load(LocalStore.keyTripShape);
    final storedDeparture = stored?['departure'];
    if (_departure == null && storedDeparture is Map<String, dynamic>) {
      _departure = storedDeparture;
    }
    final remembered = (stored?['staying_at'] ?? '').toString();
    if (remembered.isNotEmpty) {
      setState(() => _stayingAt = remembered);
      return;
    }
    // Asked once per trip, and only while the trip tab is on screen.
    final signature = '${plan.destination}|stay';
    if (_askedFor == signature || !_isVisible) return;
    _askedFor = signature;

    // A picker, not a text box.
    //
    // Free text stored whatever was typed: "I am staying in model town bhilai"
    // went into the plan as a sentence and came back out of the running order
    // as one, and could not be resolved to a point to anchor the route on.
    // Choosing a real place stores "Model Town" -- a name that reads properly
    // and locates itself.
    //
    // Typing something with no match is still allowed. Somebody staying at a
    // relative's house has a real answer that Places has never heard of, and
    // refusing it would be worse than storing it plainly.
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _StayPickerDialog(
        city: plan.destination,
        adk: _adk,
      ),
    );
    if (!mounted || picked == null) return;

    final answer = (picked['name'] ?? '').toString().trim();
    // Coordinates come back with the choice, so anchoring the route needs no
    // second lookup.
    final lat = (picked['lat'] as num?)?.toDouble();
    final lng = (picked['lng'] as num?)?.toDouble();
    if (answer.isNotEmpty && lat != null && lng != null) {
      _summaries[answer] = {'name': answer, 'lat': lat, 'lng': lng};
    }

    if (!mounted || answer == null || answer.isEmpty) return;

    // Somewhere far from the trip is almost certainly a mistake -- a stay in
    // Bannerghatta on a Bhilai trip is a thousand kilometres of driving a day.
    // Queried rather than assumed, and only warned about when we can actually
    // locate it: a private house resolves to nothing, and that is not evidence
    // of anything.
    // Only for a freehand answer: anything chosen from the list was already
    // filtered to the city before it was offered.
    final away = (lat != null && lng != null)
        ? null
        : await _adk.distanceFromCity(text: answer, city: plan.destination);
    if (!mounted) return;
    if (away != null && away > 60) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('That looks a long way off'),
          content: Text(
            'That appears to be about ${away.round()} km from '
            '${plan.destination.split(',').first}. Days planned from there '
            'would start with a very long drive.\n\n'
            'Use it anyway, or enter somewhere closer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Let me change it'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use it anyway'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (keep != true) {
        // Asked again next time rather than silently dropped.
        _askedFor = '';
        return;
      }
    }

    final shape = Map<String, dynamic>.from(
        LocalStore.load(LocalStore.keyTripShape) ?? const {});
    shape['staying_at'] = answer;
    LocalStore.save(LocalStore.keyTripShape, shape);
    setState(() {
      _stayingAt = answer;
      // The running order described days that began somewhere else.
      _schedules = {};
      // And the route was chained from a different starting point.
      _arrangedFor = '';
    });
  }

  Future<void> _askIfThin(TripPlan plan) async {
    final signature = '${plan.destination}|${plan.days.length}';
    if (signature == _askedFor) return;

    final stored = LocalStore.load(LocalStore.keyTripShape);
    final remembered = (stored?['min_per_day'] as num?)?.toInt();
    if (remembered != null) {
      _askedFor = signature;
      if (remembered != _minPerDay) setState(() => _minPerDay = remembered);
      return;
    }

    // Nothing to fix, nothing to ask.
    final provider = context.read<TripPlanProvider>();
    if (provider.shortfall(minPerDay: 2) == 0) return;
    // Not while the user is somewhere else. The question keeps until they
    // come back rather than being asked over another page.
    if (!_isVisible) return;
    _askedFor = signature;

    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('How full should each day be?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Some days do not have enough to do yet. Tell us the pace and '
              'we will fill them with real places in '
              '${plan.destination.split(',').first}.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 2),
            child: const Text('Relaxed · 2 a day'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 3),
            child: const Text('Balanced · 3'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 4),
            child: const Text('Packed · 4'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    // Dismissing is an answer too: two a day is the floor either way, and
    // nagging someone who closed the dialog is how a helpful question becomes
    // an obstacle.
    final perDay = choice ?? 2;
    LocalStore.save(LocalStore.keyTripShape, {'min_per_day': perDay});
    setState(() {
      _minPerDay = perDay;
      // The plan must be re-examined against the new floor.
      _expandedFor = '';
    });
  }

  Future<void> _expandInterests(TripPlan plan, UserPreferences prefs) async {
    final interests = prefs.selectedActivities;
    if (interests.isEmpty) return;
    final signature = '${plan.destination}|${interests.join('|')}';
    if (signature == _expandedFor) return;

    // Every day short of the minimum, not only the wholly empty ones. A day
    // holding one restaurant used to count as filled, so it stayed a single
    // lunch stop with a running order built around it.
    final provider = context.read<TripPlanProvider>();
    final missing = provider.shortfall(minPerDay: _minPerDay);
    if (missing == 0) {
      _expandedFor = signature;
      return;
    }
    _expandedFor = signature;

    final already = plan.days
        .expand((d) => d.items.map((i) => _placeName(i.title)))
        .toSet()
        .toList();
    final found = await _adk.discoverPlaces(
      city: plan.destination,
      interests: interests,
      exclude: already,
      // A margin over the shortfall: some results come back without a usable
      // name, and asking for exactly enough leaves the last day short.
      limit: missing + 2,
    );
    if (!mounted || found == null || found.isEmpty) return;

    final names = <String>[];
    for (final place in found) {
      final name = (place['name'] ?? '').toString();
      if (name.isEmpty) continue;
      names.add(name);
      _summaries[name] = place;
    }
    if (names.isEmpty) return;

    provider.topUpDays(names, minPerDay: _minPerDay);
    if (!mounted) return;
    setState(() => _summarisedFor = '');
    // The chosen interests have now given everything they can. If days are
    // still short, the plan needs more kinds of place, and only the user can
    // say which.
    await _askForMoreInterests(plan);
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

    // Now that titles have become real places, two of them may be the same
    // venue. Checked here because this is the first moment it can be known.
    if (!mounted) return;

    // Keyed on the name every row actually displays, not on the place id.
    //
    // The two entries for one venue reach the plan by different routes: one is
    // the interest the user picked ("Art"), which has a summary and therefore
    // an id; the other is the resolved place name added by the top-up, which
    // has no summary yet and therefore no id. Comparing ids put a real id
    // against an empty string, so they never matched and the duplicate
    // survived -- with the tell-tale missing photo, because nothing had
    // resolved it.
    //
    // Names are the one identifier both routes always have. Ids are still used
    // to collapse two spellings of the same venue onto a single name first.
    final canonicalById = <String, String>{};
    for (final summary in _summaries.values) {
      final id = (summary['place_id'] ?? '').toString().trim();
      final name = (summary['name'] ?? '').toString().trim();
      if (id.isNotEmpty && name.isNotEmpty) {
        canonicalById.putIfAbsent(id, () => name);
      }
    }

    String keyFor(String title) {
      final summary = _summaries[title];
      final id = (summary?['place_id'] ?? '').toString().trim();
      final name = (summary?['name'] ?? '').toString().trim();
      final canonical =
          id.isNotEmpty ? (canonicalById[id] ?? name) : name;
      return (canonical.isEmpty ? title : canonical).trim().toLowerCase();
    }

    // Every item in the plan, so nothing is skipped for want of a summary.
    final resolved = <String, String>{};
    for (final day in plan.days) {
      for (final item in day.items) {
        resolved[item.title] = keyFor(item.title);
      }
    }
    final provider = context.read<TripPlanProvider>();
    final dropped = provider.dropResolvedDuplicates(resolved);
    // A day left short by a duplicate must be filled again, so clearing
    // the guard lets the next frame go and find replacements.
    if (dropped > 0 && mounted) setState(() => _expandedFor = '');

    // Now that the plan has coordinates, put the days in a sensible order on
    // the ground: near things together, and each day starting close to where
    // the last one finished. Done here because this is the first point the
    // positions are known, and once per plan -- reshuffling on every rebuild
    // would move places under the user's hands while they were reading.
    final coords = <String, List<double>>{};
    for (final entry in _summaries.entries) {
      final lat = (entry.value['lat'] as num?)?.toDouble();
      final lng = (entry.value['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) coords[entry.key] = [lat, lng];
    }
    // Where they sleep, resolved to a point on the map, so the route can be
    // chained outward from the bed. Looked up through the same summaries call
    // as everywhere else -- free text like a hotel name or a neighbourhood
    // usually resolves; when it does not, the route simply falls back to
    // starting at their first chosen place.
    List<double>? anchor;
    final stayName = _stayFor(plan);
    if (stayName.isNotEmpty) {
      final cached = _summaries[stayName];
      final lat = (cached?['lat'] as num?)?.toDouble();
      final lng = (cached?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        anchor = [lat, lng];
      } else {
        final found = await _adk
            .placeSummaries(city: plan.destination, names: [stayName]);
        final resolved = found?[stayName];
        if (resolved != null) {
          _summaries[stayName] = resolved;
          final rlat = (resolved['lat'] as num?)?.toDouble();
          final rlng = (resolved['lng'] as num?)?.toDouble();
          if (rlat != null && rlng != null) anchor = [rlat, rlng];
        }
      }
    }
    if (!mounted) return;

    // If the trip ends with a flight, the last stops should be the ones
    // nearest the airport -- otherwise the plan cheerfully sends someone
    // across the city with their luggage an hour before departure.
    List<double>? finish;
    final leavingFrom = _departurePlace(plan);
    if (leavingFrom.isNotEmpty) {
      finish = await _resolvePoint(leavingFrom, plan.destination);
      if (!mounted) return;
    }

    _loadTripMap(plan, coords);

    final planKey = provider.contentKey;
    if (planKey != _arrangedFor && coords.length >= 3) {
      _arrangedFor = planKey;
      final moved =
          provider.arrangeByProximity(coords, from: anchor, to: finish);
      // The running order described the old sequence.
      if (moved > 0 && mounted) {
        setState(() {
          _schedules = {};
          _arrangedFor = provider.contentKey;
        });
      }
    }
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

    // Which hotel they are actually in on this date, across the whole stay
    // rather than only on the day they check in.
    //
    // Without this the scheduler could only see hotels among the day's places,
    // and a hotel suggested as somewhere to visit looked exactly like the one
    // they had booked -- so a traveller checked in to Grand Dhillon was sent
    // to Hotel Amit Park International for breakfast. Naming the booking makes
    // one of them a fact and the rest just places.
    String? stay;
    final onDay = DateTime(day.date.year, day.date.month, day.date.day);
    for (final h in booked.hotels) {
      final from =
          DateTime(h.startDate.year, h.startDate.month, h.startDate.day);
      final end = h.endDate ?? h.startDate;
      final until = DateTime(end.year, end.month, end.day);
      if (!onDay.isBefore(from) && !onDay.isAfter(until)) {
        stay = h.hotelName ?? h.title;
        break;
      }
    }
    // No booking covering this date: fall back to whatever they told us.
    stay ??= _stayingAt.isEmpty ? null : _stayingAt;

    // A typed departure is a fixed point exactly like a confirmed flight: the
    // day has to be built backwards from it. Added only to the day it falls
    // on -- 'last' is the only one the extractor reports, and putting a
    // departure on every day would wreck the whole trip.
    final departure = _departure;
    if (departure != null) {
      final plan = context.read<TripPlanProvider>().plan;
      final isLastDay = plan != null &&
          plan.days.isNotEmpty &&
          _sameDate(plan.days.last.date, day.date);
      if (isLastDay) {
        final mode = (departure['mode'] ?? '').toString();
        final time = (departure['time'] ?? '').toString();
        final place = (departure['place'] ?? '').toString();
        if (mode.isNotEmpty) {
          final where = place.isEmpty ? '' : ' from $place';
          // The time leads, because that is the part the day is planned
          // around. No time means the mode still shapes the evening.
          fixed.add(time.isEmpty
              ? 'A $mode$where on this day, time unknown'
              : '$mode departs$where at $time');
        }
      }
    }

    return {
        'date': iso(day.date),
        if (fixed.isNotEmpty) 'fixed': fixed,
        if (stay != null) 'stay': stay,
        'items': _orderedItems(day).map((i) {
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

  /// The day's places in the order the running order actually visits them.
  ///
  /// The card listed them in the order they were added, while the schedule
  /// underneath sent you round in a different sequence entirely -- Nehru Art
  /// Gallery sat at the top of the list and was the last stop of the day. The
  /// photographs then read as the shape of the day, which they were not.
  ///
  /// Sorted for display and for export rather than written back to the plan:
  /// reordering the stored items would count as an edit, which would persist,
  /// and would interrupt a running video render to ask about a change the user
  /// never made. This way the card, the day map, the PDF and the film all show
  /// one order without anything being rewritten behind them.
  List<PlanItem> _orderedItems(PlanDay day) {
    final notes = _schedules[day.date.toIso8601String().split('T').first] ??
        const <String>[];
    if (notes.isEmpty || day.items.length < 2) return day.items;

    final order = runningOrderIndices(
        [for (final i in day.items) _placeName(i.title)], notes);
    return [for (final i in order) day.items[i]];
  }

  /// Whether two DateTimes fall on the same calendar day.
  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
  /// Publishes the trip and copies a link to it.
  ///
  /// Separate from the PDF and the video: those are pictures of a plan at a
  /// moment, and this is the plan itself, still changing, that somebody else
  /// can ask to help with.
  /// Applies a suggestion the owner accepted, then republishes.
  ///
  /// Goes through TripPlanProvider like every other edit, so an accepted
  /// suggestion is indistinguishable from one the owner made -- it persists,
  /// it re-triggers the summaries and the ordering, and it survives a restart.
  /// Republishing afterwards is what lets the person who suggested it see
  /// their change land.
  Future<void> _applyProposal(TripProposal proposal) async {
    final provider = context.read<TripPlanProvider>();
    final plan = provider.plan;
    if (plan == null) return;
    if (proposal.dayIndex < 0 || proposal.dayIndex >= plan.days.length) return;

    if (proposal.isAdd) {
      provider.addItems(proposal.dayIndex, [proposal.title]);
    } else {
      final items = plan.days[proposal.dayIndex].items;
      final at = items.indexWhere(
          (i) => _placeName(i.title).toLowerCase() ==
              proposal.title.toLowerCase());
      if (at >= 0) provider.removeItem(proposal.dayIndex, at);
    }

    final updated = provider.plan;
    if (updated == null) return;
    await TripSync().publish(
      tripId: provider.tripId,
      plan: updated,
      notes: _schedules,
      fixed: _fixedByDate(updated),
    );
    if (mounted) setState(() => _summarisedFor = '');
  }

  Future<void> _sharePlanLink(TripPlan plan) async {
    final tripId = context.read<TripPlanProvider>().tripId;
    if (tripId.isEmpty) return;
    await shareTrip(
      context: context,
      tripId: tripId,
      plan: plan,
      notes: _schedules,
      fixed: _fixedByDate(plan),
    );
  }

  /// The confirmed flights and hotels for each day, keyed by ISO date.
  ///
  /// Rebuilt from the same booking data _dayPayload uses, so what a guest
  /// reads and what the scheduler was told cannot disagree.
  Map<String, List<String>> _fixedByDate(TripPlan plan) {
    final booked = context.read<BookedTripProvider>();
    final out = <String, List<String>>{};
    for (final day in plan.days) {
      final lines = <String>[];
      for (final f in booked.flights) {
        if (!_sameDate(f.startDate, day.date)) continue;
        final t = f.departureTime;
        lines.add('${f.flightNumber ?? f.title}'
            '${t == null || t.isEmpty ? '' : '  ·  $t'}');
      }
      for (final h in booked.hotels) {
        if (!_sameDate(h.startDate, day.date)) continue;
        lines.add('Check in  ·  ${h.hotelName ?? h.title}');
      }
      if (lines.isNotEmpty) {
        out[day.date.toIso8601String().split('T').first] = lines;
      }
    }
    return out;
  }

  Future<void> _sharePlan(
      TripPlan plan, BookedTripProvider booked, String format) async {
    setState(() {
      _exportProgress = 0;
      _exportStage = 'Getting ready';
      _exportBytes = null;
      _exportEditPrompted = false;
      _exportPlanKey = context.read<TripPlanProvider>().contentKey;
    });

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
        // Ordered, so the film's map pins, its photo sequence and the PDF
        // pages all follow the same day the card shows.
        'items': _orderedItems(day).map((i) {
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
            // The coordinates, without which the film has no map at all.
            // render_film only treats a place as a stop when it carries both,
            // and needs two before it draws anything -- so omitting these
            // silently skipped the route shot and the car driving it, and the
            // day cut straight from its card to the photos. The animation was
            // only ever seen in tests that built this payload by hand, which
            // is exactly what the note above says about `photos`. Same
            // function, same mistake, twice.
            if (summary['lat'] != null) 'lat': summary['lat'],
            if (summary['lng'] != null) 'lng': summary['lng'],
            if (summary['description'] != null)
              'about': summary['description'],
            if (_todayHoursFor(i.title, day.date) != null)
              'hours_today': _todayHoursFor(i.title, day.date),
          };
        }).toList(),
        'notes': _schedules[iso(day.date)] ?? const <String>[],
      };
    }).toList();

    final started = await _adk.startExport(
        days: days, format: format, destination: plan.destination);
    if (!mounted) return;

    if (started == null) {
      setState(() {
        _exportJobId = null;
        _error = "Couldn't build the $format — check the server is running.";
      });
      return;
    }

    final jobId = started['job_id'] as String;
    // Written down before polling begins. The render belongs to the server,
    // not to this screen, so leaving the page -- or closing the app -- should
    // not lose it. Without this, pressing Back cancelled the timer in dispose
    // and the finished film had nowhere to arrive.
    LocalStore.save(LocalStore.keyExportJob,
        {'job_id': jobId, 'format': format});
    setState(() {
      _error = null;
      _exportFormat = format;
      _exportJobId = jobId;
      _exportStage = 'Getting ready';
    });
    _pollExport();
  }

  /// Watches the running export and collects the file when it is done.
  ///
  /// Two seconds: fast enough that the figure looks live, slow enough that a
  /// three-minute render is ~90 requests rather than thousands.
  void _pollExport() {
    _exportPoll?.cancel();
    _exportPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final jobId = _exportJobId;
      if (jobId == null) {
        timer.cancel();
        return;
      }
      final status = await _adk.exportStatus(jobId);
      if (!mounted) {
        timer.cancel();
        return;
      }
      // A single failed poll is not a failed render -- the server may just be
      // busy with the frame it is on. Keep waiting rather than throwing away
      // work that is still going.
      if (status == null) return;

      final state = (status['state'] ?? '').toString();
      if (state == 'error') {
        timer.cancel();
        LocalStore.save(LocalStore.keyExportJob, null);
        setState(() {
          _exportJobId = null;
          _error = "Couldn't build the $_exportFormat — ${status['message']}";
        });
        return;
      }

      setState(() {
        _exportProgress = (status['progress'] as num?)?.toDouble() ?? 0;
        _exportStage = (status['stage'] ?? '').toString();
      });

      if (state != 'done') return;
      timer.cancel();

      final bytes = await _adk.fetchExport(jobId);
      LocalStore.save(LocalStore.keyExportJob, null);
      if (!mounted) return;
      setState(() {
        _exportJobId = null;
        if (bytes == null) {
          _error = 'The file was built but could not be collected.';
        } else {
          _error = null;
          _exportBytes = Uint8List.fromList(bytes);
        }
      });
    });
  }

  /// Asks what to do when the plan is edited while a video is being made.
  ///
  /// The render is of the plan as it was when it started, so an edit makes the
  /// film that is coming out of date. Rather than silently discarding minutes
  /// of work or silently handing over a stale video, ask -- once.
  Future<void> _askAboutEdit(
      TripPlan plan, BookedTripProvider booked) async {
    _exportEditPrompted = true;
    final format = _exportFormat;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your plan changed'),
        content: Text(
          'The $_exportFormat being made is of your plan as it was a moment '
          'ago. Start again so it matches your changes, or keep the one '
          'already being made?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Keep the current one'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'restart'),
            child: const Text('Start again'),
          ),
        ],
      ),
    );
    if (!mounted || choice != 'restart') return;

    // The old job is left to finish on the server: it may well be the cache
    // hit for whatever they undo next, and cancelling ffmpeg part-way buys
    // nothing back.
    _exportPoll?.cancel();
    setState(() => _exportJobId = null);
    await _sharePlan(plan, booked, format);
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

  /// Reads a departure out of a typed message and confirms it before use.
  ///
  /// Confirmed rather than applied, because this is a number the whole last
  /// day gets built backwards from. A misread "5:00PM" as 05:00 would quietly
  /// rearrange a day around the wrong hour, and nothing on screen would say
  /// so. One tap is a cheap price for that.
  Future<void> _captureDeparture(String request, TripPlan plan) async {
    // Cheap gate: most prompts are not about leaving, and this saves a model
    // call on every "move the palace to Day 2".
    final lower = request.toLowerCase();
    const words = ['train', 'bus', 'flight', 'depart', 'leave', 'leaving'];
    if (!words.any(lower.contains)) return;

    final found = await _adk.extractDeparture(
        text: request, city: plan.destination);
    if (!mounted || found == null) return;

    final mode = (found['mode'] ?? '').toString();
    final time = (found['time'] ?? '').toString();
    final place = (found['place'] ?? '').toString();
    if (mode.isEmpty) return;

    final where = place.isEmpty ? '' : ' from $place';
    final when = time.isEmpty ? '' : ' at $time';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Is this right?'),
        content: Text(
          'You have a $mode$when$where on your last day.\n\n'
          'The last day will be planned around it, ending near where you '
          'leave from.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No, ignore that'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final shape = Map<String, dynamic>.from(
        LocalStore.load(LocalStore.keyTripShape) ?? const {});
    shape['departure'] = found;
    LocalStore.save(LocalStore.keyTripShape, shape);
    setState(() {
      _departure = found;
      // The running order and the route were both built without knowing this.
      _schedules = {};
      _arrangedFor = '';
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

    // Checked first, because a departure changes the shape of the last day
    // and the plan adjuster knows nothing about times or stations.
    await _captureDeparture(request, plan);
    if (!mounted) return;

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
    final planProvider = context.watch<TripPlanProvider>();
    final plan = planProvider.plan;
    if (plan != null && !plan.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _resumeExport();
        await _askWhereStaying(plan, booked);
        if (!mounted) return;
        // Asked first: the answer decides how many places to go and find.
        await _askIfThin(plan);
        if (!mounted) return;
        _expandInterests(plan, prefs);
        _loadSummaries(plan);
      });
    }

    // The plan changed while a video of it was being made. Ask what to do
    // with the render that is already under way -- once per job, after the
    // frame, since this is inside build.
    if (_exportJobId != null &&
        !_exportEditPrompted &&
        _exportPlanKey.isNotEmpty &&
        planProvider.contentKey != _exportPlanKey &&
        plan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _exportJobId != null && !_exportEditPrompted) {
          _askAboutEdit(plan, booked);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(plan?.destination.isNotEmpty == true
            ? 'Your trip to ${plan!.destination.split(',').first}'
            : 'Your trip'),
        centerTitle: true,
        actions: [
          if (plan != null && !plan.isEmpty && _tripMap != null)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'See the whole trip on a map',
              onPressed: () => _openTripMap(plan),
            ),
          if (plan != null && !plan.isEmpty)
            // A determinate ring, not a spinner: the wait is minutes, and a
            // spinner that long is indistinguishable from a hang.
            _exportJobId != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _exportProgress > 0 ? _exportProgress : null,
                      ),
                    ),
                  )
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share this trip',
                    onSelected: (choice) {
                      if (choice == 'link') {
                        _sharePlanLink(plan);
                      } else {
                        _sharePlan(plan, booked, choice);
                      }
                    },
                    itemBuilder: (_) => const [
                      // First, because it is the one that invites somebody in
                      // rather than handing them a finished file.
                      PopupMenuItem(
                          value: 'link',
                          child: Text('Invite someone to this trip')),
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
                // Above the plan, because a person waiting on you is more
                // urgent than anything below it. Renders nothing when nobody
                // is waiting.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TripAccessRequests(
                    tripId: context.watch<TripPlanProvider>().tripId,
                  ),
                ),
                // Shared spending, beside the plan it belongs to. A separate
                // budget screen would ask people to remember a second place
                // to go; the taxi they just paid for is on their mind while
                // they are looking at the day it belonged to.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TripExpenses(
                    tripId: context.watch<TripPlanProvider>().tripId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: TripProposalReview(
                    tripId: context.watch<TripPlanProvider>().tripId,
                    onAccept: _applyProposal,
                  ),
                ),

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
                  // Ordered by the running order, so the list reads as the
                  // shape of the day. Edits still resolve through
                  // day.items.indexOf below, which is the real position.
                  for (final item in _orderedItems(day))
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
                  // Changes what the day is *about*. The row menu edits one
                  // place at a time, which is the wrong tool for "make this a
                  // temple day instead" -- that meant removing each place by
                  // hand before adding any.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _fillingDay == null
                          ? () => _changeDayTheme(plan, index)
                          : null,
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Change what this day is about'),
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
  /// Rebuilds one day around a different interest.
  ///
  /// Offers the activities the user already chose, plus anything they care to
  /// type. Picking one replaces that day's places with ones of that kind --
  /// nearby, because the search is anchored on the city and the places already
  /// in the trip are excluded, so a second temple day does not repeat the
  /// first.
  /// Kinds of place worth offering when one interest cannot fill a trip.
  ///
  /// A fixed list rather than a model call: these are categories Google Places
  /// answers well for Indian cities, and asking a model to invent category
  /// names produces things it cannot then find.
  static const List<String> _moreInterests = [
    'Temple', 'Park', 'Lake', 'Museum', 'Market', 'Street food',
    'Viewpoint', 'Fort', 'Garden', 'Cafe', 'Zoo', 'Shopping mall',
  ];

  /// Asks for more interests when the chosen ones have run out.
  ///
  /// One activity does not describe a week. Rather than leaving days blank --
  /// or padding them with whatever the city happens to rank highest, which is
  /// how a water park ended up on an art day -- this asks which other kinds of
  /// place are wanted, then fills from those.
  ///
  /// Only shown when days are genuinely still short after the chosen interests
  /// have been exhausted, and only once per trip.
  Future<void> _askForMoreInterests(TripPlan plan) async {
    final provider = context.read<TripPlanProvider>();
    if (provider.shortfall(minPerDay: _minPerDay) == 0) return;

    final signature = '${plan.destination}|${plan.days.length}|more';
    if (_askedFor == signature) return;
    if (!_isVisible) return;
    _askedFor = signature;

    final chosen = context
        .read<UserPreferencesProvider>()
        .preferences
        .selectedActivities
        .map((a) => a.toLowerCase())
        .toSet();
    final offer = [
      for (final kind in _moreInterests)
        if (!chosen.contains(kind.toLowerCase())) kind,
    ];
    if (offer.isEmpty) return;

    final picked = <String>{};
    // Re-checked immediately before opening: the places lookup above is a
    // network call, and the user can change tab while it is in flight.
    if (!_isVisible) {
      _askedFor = '';
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (innerContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('A few days still need filling',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'What else do you enjoy? We will find real places of these '
                  'kinds in ${plan.destination.split(',').first}.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in offer)
                      FilterChip(
                        label: Text(kind),
                        selected: picked.contains(kind),
                        onSelected: (on) => setSheetState(() {
                          on ? picked.add(kind) : picked.remove(kind);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: picked.isEmpty
                        ? null
                        : () => Navigator.pop(innerContext, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: const Text('Fill the rest of my trip'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(innerContext, false),
                  child: const Text('Leave them empty for now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true || picked.isEmpty) return;

    final already = plan.days
        .expand((d) => d.items.map((i) => _placeName(i.title)))
        .toSet()
        .toList();
    final found = await _adk.discoverPlaces(
      city: plan.destination,
      interests: picked.toList(),
      exclude: already,
      limit: provider.shortfall(minPerDay: _minPerDay) + 2,
    );
    if (!mounted || found == null || found.isEmpty) return;

    final names = <String>[];
    for (final place in found) {
      final name = (place['name'] ?? '').toString();
      if (name.isEmpty) continue;
      names.add(name);
      _summaries[name] = place;
    }
    if (names.isEmpty) return;
    provider.topUpDays(names, minPerDay: _minPerDay);
    setState(() => _summarisedFor = '');
  }

  Future<void> _changeDayTheme(TripPlan plan, int dayIndex) async {
    final interests =
        context.read<UserPreferencesProvider>().preferences.selectedActivities;

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What should Day ${dayIndex + 1} be about?',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Its current places are replaced with ones of this kind.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in interests)
                    ActionChip(
                      label: Text(interest),
                      onPressed: () => Navigator.pop(sheetContext, interest),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: interests.isEmpty,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Or type one — "museum", "street food", "lake"',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConfig.radiusMedium),
                  ),
                ),
                onSubmitted: (value) {
                  final typed = value.trim();
                  if (typed.isNotEmpty) Navigator.pop(sheetContext, typed);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null || choice.trim().isEmpty) return;

    setState(() {
      _fillingDay = dayIndex;
      _error = null;
    });

    // Everything already in the trip is excluded, so a new theme brings new
    // places rather than shuffling the ones already used.
    final already = plan.days
        .expand((d) => d.items.map((i) => _placeName(i.title)))
        .toSet()
        .toList();
    final found = await _adk.discoverPlaces(
      city: plan.destination,
      interests: [choice.trim()],
      exclude: already,
      limit: _minPerDay + 2,
    );
    if (!mounted) return;
    setState(() => _fillingDay = null);

    if (found == null || found.isEmpty) {
      setState(() => _error = found == null
          ? "Couldn't look for places — check the server is running."
          : 'Nothing found for "${choice.trim()}" in '
              '${plan.destination.split(',').first}.');
      return;
    }

    final names = <String>[];
    for (final place in found.take(_minPerDay)) {
      final name = (place['name'] ?? '').toString();
      if (name.isEmpty) continue;
      names.add(name);
      _summaries[name] = place;
    }
    if (names.isEmpty) return;

    context.read<TripPlanProvider>().replaceDayItems(dayIndex, names);
    setState(() {
      // The running order described a day that no longer exists.
      _schedules = {};
      _summarisedFor = '';
    });
  }

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

    // A failed lookup is worth saying. An empty one is not a dead end: the
    // city has more in it than the chosen interests describe, and the picker
    // has a search box. Telling someone "no more places found" and stopping
    // left them with an empty day and nothing to press -- so the sheet opens
    // anyway, and they can name a place or a kind of place themselves.
    if (found == null) {
      setState(() {
        _fillingDay = null;
        _error = "Couldn't look for places — check the server is running.";
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
        // Shown when the interests turned nothing up, so the empty sheet
        // reads as an invitation rather than a failure.
        emptyHint: found.isEmpty
            ? 'Nothing left matching your interests in '
                '${plan.destination.split(',').first}. '
                'Search for a place, or the kind of place you fancy — '
                '"museum", "street food", "lake".'
            : null,
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
          // Deliberately not a modal: the whole point of moving the render to
          // the server is that the trip stays usable while it runs.
          if (_exportJobId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_exportStage.isEmpty ? 'Working' : _exportStage}'
                          ' — making your ${_exportFormat.toUpperCase()}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${(_exportProgress * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _exportProgress > 0 ? _exportProgress : null,
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                          AppConfig.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Keep planning — we will tell you when it is done.',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                ],
              ),
            ),

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
    this.emptyHint,
  });

  final List<Map<String, dynamic>> places;
  final String dayLabel;

  /// Shown in place of the list when there was nothing to suggest, so the
  /// sheet asks for a place instead of just being blank.
  final String? emptyHint;

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
          // An empty sheet with a search box and no words looks broken. Saying
          // what to type turns it into the next step.
          if (_shown.isEmpty && widget.emptyHint != null &&
              _searchError == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                widget.emptyHint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            )
          else
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

/// Asks where somebody is staying, offering real places as they type.
///
/// Separate widget because the dialog has to hold its own search state, and a
/// showDialog builder cannot.
class _StayPickerDialog extends StatefulWidget {
  const _StayPickerDialog({required this.city, required this.adk});

  final String city;
  final PythonADKService adk;

  @override
  State<_StayPickerDialog> createState() => _StayPickerDialogState();
}

class _StayPickerDialogState extends State<_StayPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _matches = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _matches = const []);
      return;
    }
    // Waits for a pause in typing: a Places call per keystroke is billed per
    // keystroke.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final found =
          await widget.adk.suggestPlaces(text: value, city: widget.city);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _matches = found ?? const [];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    return AlertDialog(
      title: const Text('Where are you staying?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'So each day starts from the right place, and the stops are '
              'ordered from near you.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Area, hotel, or landmark',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final match in _matches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text((match['name'] ?? '').toString(),
                    style: const TextStyle(fontSize: 14)),
                subtitle: (match['address'] ?? '').toString().isEmpty
                    ? null
                    : Text((match['address'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, match),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        // Kept enabled for somewhere Places has never heard of, like a
        // relative's house.
        TextButton(
          onPressed:
              typed.isEmpty ? null : () => Navigator.pop(context, {'name': typed}),
          child: const Text('Use what I typed'),
        ),
      ],
    );
  }
}

/// The trip on a map, either whole or one day at a time.
///
/// Stateful because choosing a day fetches a different picture. A day on its
/// own also gets its driving route drawn, which the whole trip does not:
/// twelve days of overlapping lines is a scribble, and the question there is
/// "where is this trip", not "what is Tuesday's drive".
class _TripMapDialog extends StatefulWidget {
  const _TripMapDialog({
    required this.plan,
    required this.initialImage,
    required this.adk,
    required this.coords,
    required this.placeName,
    required this.onOpenInMaps,
  });

  final TripPlan plan;
  final Uint8List initialImage;
  final PythonADKService adk;
  final Map<String, List<double>> coords;
  final String Function(String) placeName;
  final VoidCallback onOpenInMaps;

  @override
  State<_TripMapDialog> createState() => _TripMapDialogState();
}

class _TripMapDialogState extends State<_TripMapDialog> {
  late Uint8List _image = widget.initialImage;

  /// null means the whole trip.
  int? _day;
  bool _loading = false;

  /// Maps already fetched, so going back to a day is instant and unbilled.
  final Map<int, Uint8List> _cache = {};

  Future<void> _show(int? day) async {
    if (day == _day) return;
    final cached = _cache[day ?? -1];
    if (cached != null) {
      setState(() {
        _day = day;
        _image = cached;
      });
      return;
    }

    setState(() {
      _day = day;
      _loading = true;
    });
    final indices = day == null
        ? [for (var i = 0; i < widget.plan.days.length; i++) i]
        : [day];
    final payload = [
      for (final i in indices)
        {
          // Sent so a day drawn on its own still gets its own number and
          // colour, matching the key beneath the map.
          'day': i,
          'items': [
            for (final item in widget.plan.days[i].items)
              if (widget.coords[item.title] != null)
                {
                  'lat': widget.coords[item.title]![0],
                  'lng': widget.coords[item.title]![1],
                }
          ]
        }
    ];
    final bytes = await widget.adk.tripMap(payload, route: day != null);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (bytes != null) {
        final image = Uint8List.fromList(bytes);
        _cache[day ?? -1] = image;
        _image = image;
      }
    });
  }

  /// How many of a day's places we can actually put on a map.
  int _locatedCount(int day) => widget.plan.days[day].items
      .where((i) => widget.coords[i.title] != null)
      .length;

  Color _colour(int day) {
    const palette = [
      Color(0xFF0D0D82), Color(0xFFD62D20), Color(0xFF008744),
      Color(0xFFFFA700), Color(0xFF9C27B0), Color(0xFF00838F),
      Color(0xFF795548), Color(0xFFC2185B),
    ];
    return palette[day % palette.length];
  }

  String _mark(int day) {
    if (day < 9) return '${day + 1}';
    if (day < 35) return String.fromCharCode(65 + day - 9);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.plan.days;
    return Dialog(
      insetPadding: const EdgeInsets.all(10),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.96,
        height: MediaQuery.of(context).size.height * 0.92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _day == null
                              ? 'Your whole trip'
                              : 'Day ${_day! + 1}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _day == null
                              ? 'Pinch to zoom. Tap a day below for its route.'
                              : _locatedCount(_day!) < 2
                                  // A single stop has no drive. Saying so
                                  // beats showing one pin and letting the
                                  // reader wonder where the line went.
                                  ? 'Only one place on this day, so there is '
                                      'no route to draw.'
                                  : 'The drive for this day, in order.',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.grey.shade100,
                width: double.infinity,
                child: Stack(
                  children: [
                    InteractiveViewer(
                      maxScale: 8,
                      clipBehavior: Clip.hardEdge,
                      child: Center(
                          child: Image.memory(_image, fit: BoxFit.contain)),
                    ),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 150,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_day != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton.icon(
                          onPressed: () => _show(null),
                          icon: const Icon(Icons.arrow_back, size: 15),
                          label: const Text('Back to the whole trip',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    for (var d = 0; d < days.length; d++)
                      if (days[d].items.isNotEmpty)
                        InkWell(
                          onTap: () => _show(d),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: _day == d
                                ? Colors.blue.shade50
                                : Colors.transparent,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  alignment: Alignment.center,
                                  margin: const EdgeInsets.only(top: 1),
                                  decoration: BoxDecoration(
                                    color: _colour(d),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(_mark(d),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Day ${d + 1}  ·  '
                                    '${days[d].items.map((i) => widget.placeName(i.title)).join(', ')}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 16, color: Colors.grey[400]),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenInMaps,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in Google Maps'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

