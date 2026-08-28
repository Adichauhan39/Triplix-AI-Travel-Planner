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

  /// The trip inputs the current plan was built from.
  ///
  /// The plan is only kept while these hold. Previously the guard compared
  /// the destination and the start date alone, so changing the activities or
  /// the length of the trip left the old itinerary in place -- the user
  /// edited their trip and the plan carried on describing the previous one.
  ///
  /// Comparing everything is also what protects the user's own edits: as long
  /// as the trip is unchanged, a rebuild is a no-op and a place they removed
  /// stays removed.
  String _builtFrom = '';

  TripPlan? get plan => _plan;
  bool get hasPlan => _plan != null && !_plan!.isEmpty;

  /// What the plan currently *contains*, as a comparable string.
  ///
  /// Distinct from [_builtFrom], which records the inputs the plan was built
  /// from. Removing a place, adding one or reordering a day leaves those
  /// inputs untouched, so the build signature cannot answer "has this plan
  /// changed since I started rendering a video of it" -- which is the question
  /// the export needs, since the film is made of the items, not the inputs.
  String get contentKey {
    final plan = _plan;
    if (plan == null) return '';
    return [
      plan.destination,
      for (final day in plan.days)
        '${day.date.toIso8601String().split('T').first}'
            ':${day.items.map((i) => i.title).join(',')}',
    ].join('|');
  }

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
    final signature = [
      destination,
      start.toIso8601String().split('T').first,
      end.toIso8601String().split('T').first,
      ...activities,
    ].join('|');

    if (_plan != null && signature == _builtFrom) return;
    _builtFrom = signature;

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
    _builtFrom = (stored['built_from'] ?? '').toString();
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
          : {
              'destination': plan.destination,
              'days': plan.toJson(),
              // Stored with the plan so a restored trip knows which inputs
              // produced it. Without this, reopening the app and changing an
              // activity would not rebuild, because nothing on disk recorded
              // what the saved plan was built from.
              'built_from': _builtFrom,
            },
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

  /// Spreads [titles] across the days that have nothing on them.
  ///
  /// Used when a trip is built from a couple of interests: one interest
  /// resolves to one place, so a four-day trip arrived with one place and
  /// three empty days. Expanding the interest into several real places of
  /// that kind is honouring the choice rather than adding to it -- someone
  /// who ticked "Lake" asked for lakes, not for one lake.
  ///
  /// Not marked as assistant-added for that reason: the category was the
  /// user's. The badge is reserved for places offered that they never asked
  /// for.
  void fillEmptyDays(List<String> titles, {int perDay = 2}) {
    final plan = _plan;
    if (plan == null || titles.isEmpty) return;

    final used = plan.days
        .expand((d) => d.items.map((i) => i.title.toLowerCase()))
        .toSet();
    final queue = [
      for (final title in titles)
        if (title.trim().isNotEmpty && !used.contains(title.trim().toLowerCase()))
          title.trim(),
    ];
    if (queue.isEmpty) return;

    var index = 0;
    final days = <PlanDay>[];
    for (final day in plan.days) {
      if (day.items.isNotEmpty || index >= queue.length) {
        days.add(day);
        continue;
      }
      final items = <PlanItem>[];
      while (items.length < perDay && index < queue.length) {
        items.add(PlanItem(title: queue[index]));
        index++;
      }
      days.add(day.copyWith(items: items));
    }

    _plan = TripPlan(destination: plan.destination, days: days);
    notifyListeners();
  }

  void clear() {
    if (_plan == null) return;
    _plan = null;
    _builtFrom = '';
    notifyListeners();
  }
}
