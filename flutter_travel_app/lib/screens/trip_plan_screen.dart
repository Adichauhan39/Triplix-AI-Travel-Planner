import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../models/user_preferences.dart';
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

    final plan = context.watch<TripPlanProvider>().plan;

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
                Expanded(child: _buildDays(plan)),
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

  Widget _buildDays(TripPlan plan) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppConfig.paddingMedium),
      itemCount: plan.days.length,
      itemBuilder: (context, index) {
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
                const SizedBox(height: 10),
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
                          const Icon(Icons.place_outlined,
                              size: 18, color: AppConfig.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item.title,
                                style: const TextStyle(fontSize: 14)),
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
              ],
            ),
          ),
        );
      },
    );
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
