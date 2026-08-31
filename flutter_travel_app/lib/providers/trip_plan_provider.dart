import 'dart:math' as math;

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

  /// A stable name for this trip.
  ///
  /// The plan has never had an identity: it was simply "the plan on this
  /// device". That is enough while it lives in one browser, and not enough for
  /// anything else -- a link to share, a row to store, a booking that belongs
  /// to one trip rather than to the user in general. The stacked outbound
  /// flights came from exactly that gap.
  ///
  /// Minted when a plan is first built, and again when the destination
  /// changes, because that is a different trip. Changing dates or activities
  /// keeps the id: that is the same trip being adjusted, and a shared link to
  /// it should not break because somebody moved their dates by a day.
  String _tripId = '';

  /// Random, not sequential. This ends up in a shareable URL, and an id you
  /// can increment is an invitation to read somebody else's itinerary.
  static String _mintId() {
    const alphabet = 'abcdefghijkmnopqrstuvwxyz23456789';
    final random = math.Random.secure();
    return List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  TripPlan? get plan => _plan;

  /// The trip's id, or empty when no plan exists yet.
  String get tripId => _tripId;
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

    // A different destination is a different trip. Anything else -- new dates,
    // new activities -- is this trip being changed, so it keeps its id and any
    // link already shared with a fellow traveller keeps working.
    final previousDestination = _plan?.destination;
    if (_tripId.isEmpty || previousDestination != destination) {
      _tripId = _mintId();
    }
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
    // A plan saved before trips had ids is given one on the way in, so an
    // existing trip can be shared without being rebuilt.
    final storedId = (stored['trip_id'] ?? '').toString();
    _tripId = storedId.isEmpty ? _mintId() : storedId;
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
              'trip_id': _tripId,
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

  /// Spreads [titles] across the days that are short of places.
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
  void topUpDays(List<String> titles, {int minPerDay = 2}) {
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
      // Tops up any short day, not only an empty one. Filling empties alone
      // left a day holding a single restaurant and calling itself a plan --
      // one place is somewhere to eat, not a day out.
      if (day.items.length >= minPerDay || index >= queue.length) {
        days.add(day);
        continue;
      }
      final items = List<PlanItem>.from(day.items);
      while (items.length < minPerDay && index < queue.length) {
        items.add(PlanItem(title: queue[index]));
        index++;
      }
      days.add(day.copyWith(items: items));
    }

    _plan = TripPlan(destination: plan.destination, days: days);
    notifyListeners();
  }

  /// How many more places the plan needs before every day holds [minPerDay].
  ///
  /// Lets the caller ask for exactly that many rather than guessing, and lets
  /// it skip the lookup entirely when the trip is already full.
  int shortfall({int minPerDay = 2}) {
    final plan = _plan;
    if (plan == null) return 0;
    var missing = 0;
    for (final day in plan.days) {
      final gap = minPerDay - day.items.length;
      if (gap > 0) missing += gap;
    }
    return missing;
  }

  /// Drops places that turn out to be the same real venue.
  ///
  /// The plan dedupes by title, and a title is whatever the user picked --
  /// often a category. Two categories can land on one venue: "Art" and "Cafe"
  /// both resolved to WOOWOO ART HOUSE, so it appeared twice on one day, with
  /// the same photo and rating and only its Google type list differing.
  ///
  /// The clash is invisible until titles resolve, which is why it cannot be
  /// caught when the day is built: at that point the plan holds two different
  /// strings that happen to describe one place.
  ///
  /// [resolved] maps each item title to a stable id for the real place -- its
  /// Google place id where known, its resolved name otherwise. The first
  /// occurrence stays, in its day and its position; later ones go.
  /// Returns how many were dropped, so the caller can top the days back
  /// up: removing a duplicate leaves a day short of the minimum.
  int dropResolvedDuplicates(Map<String, String> resolved) {
    final plan = _plan;
    if (plan == null || resolved.isEmpty) return 0;

    final seen = <String>{};
    var removed = 0;
    final days = <PlanDay>[];
    for (final day in plan.days) {
      final kept = <PlanItem>[];
      for (final item in day.items) {
        final key = (resolved[item.title] ?? '').trim().toLowerCase();
        // Unresolved items are left alone: a place we could not identify is
        // not evidence of a duplicate, and dropping it would silently shrink
        // the trip while summaries are still loading.
        if (key.isEmpty || seen.add(key)) {
          kept.add(item);
        } else {
          removed++;
        }
      }
      days.add(day.copyWith(items: kept));
    }
    if (removed == 0) return 0;

    _plan = TripPlan(destination: plan.destination, days: days);
    notifyListeners();
    return removed;
  }

  /// Replaces one day's places wholesale.
  ///
  /// Used when the user changes what a day is about. Not marked as
  /// assistant-added: they chose the theme, so these are their places, the
  /// same as any other activity they picked.
  void replaceDayItems(int dayIndex, List<String> titles) {
    final plan = _plan;
    if (plan == null || titles.isEmpty) return;
    if (dayIndex < 0 || dayIndex >= plan.days.length) return;

    _plan = TripPlan(
      destination: plan.destination,
      days: [
        for (var i = 0; i < plan.days.length; i++)
          i == dayIndex
              ? plan.days[i].copyWith(
                  items: [for (final t in titles) PlanItem(title: t.trim())])
              : plan.days[i],
      ],
    );
    notifyListeners();
  }

  /// Straight-line distance in km. Good enough to order stops within a city,
  /// where the road distance is a near-constant multiple of it.
  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  /// Reorders the whole trip so each day's places sit near each other, and each
  /// day begins near where the last one ended.
  ///
  /// Both of those are the same problem. Every place is chained into one
  /// nearest-neighbour route through the city, and that route is then cut into
  /// days at the existing day boundaries. Neighbours in the chain end up on the
  /// same day, and the cut points are themselves neighbours -- so the join
  /// between Monday's last stop and Tuesday's first is no worse than any other
  /// step.
  ///
  /// Clustering the days separately would have given tight days with arbitrary
  /// joins between them, which is the version of this that looks right on each
  /// card and wrong on the map.
  ///
  /// The first located place anchors the chain, so the day the user starts with
  /// still starts the trip. Places we have no coordinates for keep their order
  /// and go last; they cannot be positioned, and guessing would move somebody's
  /// stop for no reason.
  ///
  /// Day sizes are preserved exactly: this decides *which* day each place
  /// falls on, never how full a day is.
  ///
  /// Returns the number of places that changed day, so a caller can tell
  /// whether anything actually moved.
  /// [from] is where the traveller sleeps, when it is known. The route is
  /// chained outward from there instead of from whichever place happens to be
  /// listed first, so a day starts with what is nearest the bed rather than
  /// with a stop across town.
  /// [to] is where the trip has to finish -- the airport, when the last day
  /// ends in a flight. The route is optimised to arrive near it, so the final
  /// stops are the ones closest to departure instead of leaving a cross-city
  /// dash with luggage.
  int arrangeByProximity(Map<String, List<double>> coords,
      {List<double>? from, List<double>? to}) {
    final plan = _plan;
    if (plan == null) return 0;

    final counts = [for (final day in plan.days) day.items.length];
    final all = [for (final day in plan.days) ...day.items];

    bool located(PlanItem i) {
      final c = coords[i.title];
      return c != null && c.length == 2;
    }

    final remaining = [for (final i in all) if (located(i)) i];
    final unlocated = [for (final i in all) if (!located(i)) i];
    // Two stops are already in whatever order they are; there is no route to
    // improve until there is a choice to make.
    if (remaining.length < 3) return 0;

    final chain = <PlanItem>[];
    // Anchored on the bed where we know it. Falling back to the first place
    // keeps the user's own first choice leading the trip, which is what
    // happened before a stay was ever recorded.
    var cursor = (from != null && from.length == 2)
        ? from
        : coords[remaining.first.title]!;

    // With a real anchor the first stop is chosen too, rather than assumed:
    // the nearest place to the hotel leads the day.
    if (from != null && from.length == 2) {
      var nearest = 0;
      var best = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final c = coords[remaining[i].title]!;
        final d = _km(cursor[0], cursor[1], c[0], c[1]);
        if (d < best) {
          best = d;
          nearest = i;
        }
      }
      final first = remaining.removeAt(nearest);
      chain.add(first);
      cursor = coords[first.title]!;
    }
    while (remaining.isNotEmpty) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final c = coords[remaining[i].title]!;
        final d = _km(cursor[0], cursor[1], c[0], c[1]);
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
        }
      }
      final picked = remaining.removeAt(best);
      chain.add(picked);
      cursor = coords[picked.title]!;
    }

    // Greedy gets a decent route and then strands itself: having taken the
    // nearest place each time, whatever is left is far away, and the chain
    // ends with one long jump back across the city. 2-opt fixes exactly that
    // -- it reverses any stretch of the route that shortens the whole thing,
    // which is what un-crosses a path that doubles back on itself.
    //
    // Position 0 is held fixed so the place the user started with still starts
    // the trip. The loop runs to a fixed ceiling rather than to exhaustion: it
    // converges in a handful of passes at these sizes, and a trip is not worth
    // spinning on.
    double hop(PlanItem a, PlanItem b) {
      final p1 = coords[a.title]!;
      final p2 = coords[b.title]!;
      return _km(p1[0], p1[1], p2[0], p2[1]);
    }

    // The cost of finishing at a place, which is zero unless the trip has to
    // end somewhere in particular. Including it in the 2-opt means the search
    // optimises the whole journey -- bed to airport -- rather than just the
    // hops between stops.
    double tail(PlanItem x) {
      if (to == null || to.length != 2) return 0.0;
      final p = coords[x.title]!;
      return _km(p[0], p[1], to[0], to[1]);
    }

    var improved = true;
    var passes = 0;
    while (improved && passes < 50) {
      improved = false;
      passes++;
      for (var i = 1; i < chain.length - 1; i++) {
        for (var j = i + 1; j < chain.length; j++) {
          final before = hop(chain[i - 1], chain[i]) +
              (j + 1 < chain.length
                  ? hop(chain[j], chain[j + 1])
                  : tail(chain[j]));
          final after = hop(chain[i - 1], chain[j]) +
              (j + 1 < chain.length
                  ? hop(chain[i], chain[j + 1])
                  : tail(chain[i]));
          // The epsilon stops a pair of equal-length routes swapping forever.
          if (after < before - 1e-9) {
            chain.setRange(i, j + 1, chain.sublist(i, j + 1).reversed.toList());
            improved = true;
          }
        }
      }
    }

    final ordered = [...chain, ...unlocated];
    var moved = 0;
    var cut = 0;
    final days = <PlanDay>[];
    for (var d = 0; d < plan.days.length; d++) {
      final slice = ordered.sublist(cut, cut + counts[d]);
      for (var i = 0; i < slice.length; i++) {
        if (plan.days[d].items.length <= i ||
            plan.days[d].items[i].title != slice[i].title) {
          moved++;
        }
      }
      days.add(plan.days[d].copyWith(items: slice));
      cut += counts[d];
    }
    if (moved == 0) return 0;

    _plan = TripPlan(destination: plan.destination, days: days);
    notifyListeners();
    return moved;
  }

  void clear() {
    if (_plan == null) return;
    _plan = null;
    _builtFrom = '';
    _tripId = '';
    notifyListeners();
  }
}
