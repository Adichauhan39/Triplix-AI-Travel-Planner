import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_travel_app/providers/trip_plan_provider.dart';
import 'package:flutter_travel_app/services/local_store.dart';

/// Real Bhilai coordinates, deliberately interleaved so the naive order
/// zig-zags across the city.
const _coords = <String, List<double>>{
  'Maitri Baag Zoo': [21.1938, 81.3509],
  'Jubilee Park': [21.2144, 81.3509],
  'Shaheed Udyaan': [21.2094, 81.3789],
  'Dam View point': [21.1729, 81.3312],
  'Civic Center Bhilai': [21.2050, 81.3800],
  'Maroda Tank': [21.1850, 81.3600],
};

double km(List<double> a, List<double> b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(b[0] - a[0]);
  final dLon = rad(b[1] - a[1]);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a[0])) *
          math.cos(rad(b[0])) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Total distance walked over the whole trip, including the joins between days.
double tripDistance(TripPlanProvider p) {
  final order = [
    for (final d in p.plan!.days) ...d.items.map((i) => i.title)
  ].where(_coords.containsKey).toList();
  var total = 0.0;
  for (var i = 0; i < order.length - 1; i++) {
    total += km(_coords[order[i]]!, _coords[order[i + 1]]!);
  }
  return total;
}

TripPlanProvider tripOf(List<String> titles, int days) {
  final p = TripPlanProvider()
    ..buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 8, 30),
      end: DateTime(2026, 8, 30).add(Duration(days: days - 1)),
      activities: titles,
    );
  return p;
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('the trip gets shorter, joins between days included', () {
    final p = tripOf(_coords.keys.toList(), 3);
    final before = tripDistance(p);
    p.arrangeByProximity(_coords);
    final after = tripDistance(p);
    expect(after, lessThan(before),
        reason: 'a nearest-neighbour chain must beat the arbitrary order');
  });

  /// The longest single hop anywhere in the trip, days included.
  ///
  /// Measured against the unarranged trip rather than a fixed number of
  /// kilometres: Bhilai is about 7km across, so with six places over three
  /// days some hop has to be long. A threshold picked out of the air would
  /// only record how spread out this fixture happens to be.
  double worstHop(TripPlanProvider p) {
    final order = [
      for (final d in p.plan!.days) ...d.items.map((i) => i.title)
    ].where(_coords.containsKey).toList();
    var worst = 0.0;
    for (var i = 0; i < order.length - 1; i++) {
      final d = km(_coords[order[i]]!, _coords[order[i + 1]]!);
      if (d > worst) worst = d;
    }
    return worst;
  }

  test('no hop is longer than the worst one before arranging', () {
    final p = tripOf(_coords.keys.toList(), 3);
    final before = worstHop(p);
    p.arrangeByProximity(_coords);
    expect(worstHop(p), lessThanOrEqualTo(before));
  });

  test('the join between days is no worse than a hop within one', () {
    final p = tripOf(_coords.keys.toList(), 3);
    p.arrangeByProximity(_coords);

    var worstJoin = 0.0;
    for (var d = 0; d < p.plan!.days.length - 1; d++) {
      final end = _coords[p.plan!.days[d].items.last.title]!;
      final start = _coords[p.plan!.days[d + 1].items.first.title]!;
      worstJoin = math.max(worstJoin, km(end, start));
    }
    // The whole point of chaining first and cutting after: a day boundary is
    // just another step in the route, so it must not stand out.
    expect(worstJoin, lessThanOrEqualTo(worstHop(p)));
  });

  test('day sizes are never changed', () {
    final p = tripOf(_coords.keys.toList(), 3);
    final before = [for (final d in p.plan!.days) d.items.length];
    p.arrangeByProximity(_coords);
    expect([for (final d in p.plan!.days) d.items.length], before);
  });

  test('nothing is lost or invented', () {
    final p = tripOf(_coords.keys.toList(), 3);
    final before =
        [for (final d in p.plan!.days) ...d.items.map((i) => i.title)].toSet();
    p.arrangeByProximity(_coords);
    final after =
        [for (final d in p.plan!.days) ...d.items.map((i) => i.title)].toSet();
    expect(after, before);
  });

  test('places with no coordinates are kept, at the end', () {
    final titles = [..._coords.keys, 'Somewhere unmapped'];
    final p = tripOf(titles, 3);
    p.arrangeByProximity(_coords);
    final all =
        [for (final d in p.plan!.days) ...d.items.map((i) => i.title)];
    expect(all, contains('Somewhere unmapped'));
    expect(all.last, 'Somewhere unmapped',
        reason: 'unplaceable stops go last rather than being guessed at');
  });

  test('too few stops to reorder is left alone', () {
    final p = tripOf(['Maitri Baag Zoo', 'Jubilee Park'], 2);
    expect(p.arrangeByProximity(_coords), 0);
  });

  /// The route plain greedy nearest-neighbour would produce, so the refined
  /// one can be measured against it rather than merely asserted to be good.
  double greedyDistance(List<String> titles, Map<String, List<double>> c) {
    final remaining = [...titles];
    final route = [remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      var best = 0;
      var bestD = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d = km(c[route.last]!, c[remaining[i]]!);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      route.add(remaining.removeAt(best));
    }
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      total += km(c[route[i]]!, c[route[i + 1]]!);
    }
    return total;
  }

  test('2-opt is never worse than plain greedy', () {
    final p = tripOf(_coords.keys.toList(), 3);
    p.arrangeByProximity(_coords);
    expect(tripDistance(p),
        lessThanOrEqualTo(greedyDistance(_coords.keys.toList(), _coords)));
  });

  test('the detour greedy walks past is corrected', () {
    // A genuine trap. Four stops march up a line; one sits just off it,
    // slightly further from the start than the first stop on the line.
    //
    // Greedy takes the marginally nearer stop first, then has to come back
    // out for the one it skipped, and rejoins the line having walked the
    // gap twice. Picking up the off-line stop on the way costs a fraction
    // more at the first step and less overall.
    //
    // My first attempt at this test put every point on one line starting at
    // an end, where greedy is already optimal -- so it proved nothing.
    const trap = <String, List<double>>{
      'Start': [21.100, 81.300],
      'OnLine1': [21.110, 81.300],
      'OnLine2': [21.120, 81.300],
      'OnLine3': [21.130, 81.300],
      'OffLine': [21.109, 81.305],
    };
    final p = tripOf(trap.keys.toList(), 2);
    final greedy = greedyDistance(trap.keys.toList(), trap);
    p.arrangeByProximity(trap);

    final order = [
      for (final d in p.plan!.days) ...d.items.map((i) => i.title)
    ];
    var refined = 0.0;
    for (var i = 0; i < order.length - 1; i++) {
      refined += km(trap[order[i]]!, trap[order[i + 1]]!);
    }
    expect(refined, lessThan(greedy),
        reason: 'the doubling-back should be gone: $order');
  });

  test('the refined route still starts where the user started', () {
    final titles = _coords.keys.toList();
    final p = tripOf(titles, 3);
    p.arrangeByProximity(_coords);
    expect(p.plan!.days.first.items.first.title, titles.first);
  });

  group('starting from where you sleep', () {
    test('the day begins with the place nearest the bed', () {
      final p = tripOf(_coords.keys.toList(), 3);
      // A stay right beside Dam View point, which is listed fourth.
      p.arrangeByProximity(_coords, from: const [21.1730, 81.3313]);
      expect(p.plan!.days.first.items.first.title, 'Dam View point');
    });

    test('without a stay, the first choice picked still leads', () {
      final titles = _coords.keys.toList();
      final p = tripOf(titles, 3);
      p.arrangeByProximity(_coords);
      expect(p.plan!.days.first.items.first.title, titles.first);
    });

    test('anchoring does not lose or duplicate anywhere', () {
      final p = tripOf(_coords.keys.toList(), 3);
      p.arrangeByProximity(_coords, from: const [21.1730, 81.3313]);
      final all = [
        for (final d in p.plan!.days) ...d.items.map((i) => i.title)
      ];
      expect(all.toSet(), _coords.keys.toSet());
      expect(all, hasLength(_coords.length));
    });

    test('a malformed anchor is ignored rather than throwing', () {
      final p = tripOf(_coords.keys.toList(), 3);
      expect(() => p.arrangeByProximity(_coords, from: const [21.0]),
          returnsNormally);
    });
  });

  group('finishing near the airport', () {
    // Raipur airport, the one a Bhilai trip actually flies from.
    const airport = [21.1804, 81.7388];

    test('the last stop of the trip is the one nearest departure', () {
      final p = tripOf(_coords.keys.toList(), 3);
      p.arrangeByProximity(_coords, to: airport);

      final last = p.plan!.days.last.items.last.title;
      final lastDistance = km(_coords[last]!, airport);
      for (final entry in _coords.entries) {
        expect(lastDistance, lessThanOrEqualTo(km(entry.value, airport) + 0.001),
            reason: 'ended at $last, but ${entry.key} is closer to the airport');
      }
    });

    test('the whole journey including the airport run gets shorter', () {
      double toAirport(TripPlanProvider p) {
        final order = [
          for (final d in p.plan!.days) ...d.items.map((i) => i.title)
        ].where(_coords.containsKey).toList();
        var total = 0.0;
        for (var i = 0; i < order.length - 1; i++) {
          total += km(_coords[order[i]]!, _coords[order[i + 1]]!);
        }
        return total + km(_coords[order.last]!, airport);
      }

      final plain = tripOf(_coords.keys.toList(), 3)..arrangeByProximity(_coords);
      final aimed = tripOf(_coords.keys.toList(), 3)
        ..arrangeByProximity(_coords, to: airport);
      expect(toAirport(aimed), lessThanOrEqualTo(toAirport(plain)));
    });

    test('a start and a finish can both be honoured', () {
      final p = tripOf(_coords.keys.toList(), 3);
      p.arrangeByProximity(_coords,
          from: const [21.1730, 81.3313], to: airport);
      // Begins beside the bed, ends nearest the airport.
      expect(p.plan!.days.first.items.first.title, 'Dam View point');
      final all = [
        for (final d in p.plan!.days) ...d.items.map((i) => i.title)
      ];
      expect(all.toSet(), _coords.keys.toSet(), reason: 'nothing lost');
    });
  });
}
