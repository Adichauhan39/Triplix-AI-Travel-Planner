import 'package:flutter/foundation.dart';

import '../models/trip_plan.dart';
import '../services/local_store.dart';

/// Holds the day-by-day plan while the user is looking at it.
///
/// Written to the device on every change, so a plan the user has edited
/// through the prompt box survives a restart. Those edits are the part that
/// cannot be rebuilt from the onboarding answers.
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

  /// Reads back a saved plan, including any adjustments the user made.
  ///
  /// Restored before the screen rebuilds from onboarding, and
  /// [buildFromSelection] then leaves it alone because its inputs match — so
  /// a plan the user reordered is not silently rebuilt from scratch.
  void restore() {
    final stored = LocalStore.load(LocalStore.keyTripPlan);
    if (stored == null) return;
    final days = ((stored['days'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanDay.fromJson)
        .toList();
    if (days.isEmpty) return;
    _plan = TripPlan(
      destination: (stored['destination'] ?? '').toString(),
      days: days,
    );
    notifyListeners();
  }

  /// Persists on every change, so no future mutation can forget to save.
  @override
  void notifyListeners() {
    super.notifyListeners();
    final plan = _plan;
    LocalStore.save(
      LocalStore.keyTripPlan,
      plan == null
          ? null
          : {'destination': plan.destination, 'days': plan.toJson()},
    );
  }

  void clear() {
    if (_plan == null) return;
    _plan = null;
    notifyListeners();
  }
}
