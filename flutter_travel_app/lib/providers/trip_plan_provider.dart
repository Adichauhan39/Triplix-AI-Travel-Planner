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

  /// Removes one place from one day.
  ///
  /// Edits go through the provider rather than being made on a copy of the
  /// plan, so they persist through the same notifyListeners hook everything
  /// else uses -- a change the user makes must survive a restart exactly like
  /// one the app made.
  void removeItem(int dayIndex, int itemIndex) {
    final plan = _plan;
    if (plan == null) return;
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;
    final day = plan.days[dayIndex];
    if (itemIndex < 0 || itemIndex >= day.items.length) return;

    final items = [...day.items]..removeAt(itemIndex);
    _plan = TripPlan(
      destination: plan.destination,
      days: [
        for (var i = 0; i < plan.days.length; i++)
          i == dayIndex ? day.copyWith(items: items) : plan.days[i],
      ],
    );
    notifyListeners();
  }

  /// Moves a place to another day, appending it at the end of that day.
  ///
  /// A no-op when the target is the same day: silently reordering within a
  /// day would look like the move failed.
  void moveItem(int fromDay, int itemIndex, int toDay) {
    final plan = _plan;
    if (plan == null || fromDay == toDay) return;
    if (fromDay < 0 || fromDay >= plan.days.length) return;
    if (toDay < 0 || toDay >= plan.days.length) return;
    final source = plan.days[fromDay];
    if (itemIndex < 0 || itemIndex >= source.items.length) return;

    final moved = source.items[itemIndex];
    final remaining = [...source.items]..removeAt(itemIndex);
    final target = [...plan.days[toDay].items, moved];

    _plan = TripPlan(
      destination: plan.destination,
      days: [
        for (var i = 0; i < plan.days.length; i++)
          if (i == fromDay)
            source.copyWith(items: remaining)
          else if (i == toDay)
            plan.days[i].copyWith(items: target)
          else
            plan.days[i],
      ],
    );
    notifyListeners();
  }

  /// Adds places to a day, marked as suggestions rather than choices.
  ///
  /// [addedByAssistant] is what keeps the distinction the rest of the app
  /// relies on: the user picked their own activities, and these were offered
  /// to fill an empty day. The badge on the card comes from this flag.
  void addItems(int dayIndex, List<String> titles) {
    final plan = _plan;
    if (plan == null || titles.isEmpty) return;
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;

    final day = plan.days[dayIndex];
    final existing = day.items.map((i) => i.title.toLowerCase()).toSet();
    final additions = [
      for (final title in titles)
        if (title.trim().isNotEmpty &&
            !existing.contains(title.trim().toLowerCase()))
          PlanItem(title: title.trim(), addedByAssistant: true),
    ];
    if (additions.isEmpty) return;

    _plan = TripPlan(
      destination: plan.destination,
      days: [
        for (var i = 0; i < plan.days.length; i++)
          i == dayIndex
              ? day.copyWith(items: [...day.items, ...additions])
              : plan.days[i],
      ],
    );
    notifyListeners();
  }

  void clear() {
    if (_plan == null) return;
    _plan = null;
    notifyListeners();
  }
}
