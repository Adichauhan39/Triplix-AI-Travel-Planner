import 'package:flutter/foundation.dart';

import '../models/trip_plan.dart';

/// Holds the day-by-day plan while the user is looking at it.
///
/// In memory only, like the other providers in this app — there is no storage
/// layer yet, so the plan is lost on restart. That needs fixing before this
/// ships: a user who builds a trip, closes the app and reopens it to an empty
/// screen will not build it a second time.
class TripPlanProvider with ChangeNotifier {
  TripPlan? _plan;

  TripPlan? get plan => _plan;
  bool get hasPlan => _plan != null && !_plan!.isEmpty;

  /// Builds the plan from what the user chose during onboarding.
  ///
  /// Rebuilds only when the inputs actually differ, so returning to the
  /// screen doesn't silently discard adjustments the user has made since.
  void buildFromSelection({
    required String destination,
    required DateTime start,
    required DateTime end,
    required List<String> activities,
  }) {
    final existing = _plan;
    if (existing != null &&
        existing.destination == destination &&
        existing.days.isNotEmpty &&
        existing.days.first.date == start) {
      return;
    }
    _plan = TripPlan.fromSelection(
      destination: destination,
      start: start,
      end: end,
      activities: activities,
    );
    notifyListeners();
  }

  /// Replaces the plan's days, e.g. after a typed adjustment.
  void replaceDays(List<PlanDay> days) {
    final existing = _plan;
    if (existing == null) return;
    _plan = TripPlan(destination: existing.destination, days: days);
    notifyListeners();
  }

  void clear() {
    if (_plan == null) return;
    _plan = null;
    notifyListeners();
  }
}
