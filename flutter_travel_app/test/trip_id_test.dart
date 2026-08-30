import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_travel_app/providers/trip_plan_provider.dart';
import 'package:flutter_travel_app/services/local_store.dart';

TripPlanProvider bhilai() => TripPlanProvider()
  ..buildFromSelection(
    destination: 'Bhilai',
    start: DateTime(2026, 9, 1),
    end: DateTime(2026, 9, 3),
    activities: ['Temple', 'Park'],
  );

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('a plan gets an id, and an empty provider has none', () {
    expect(TripPlanProvider().tripId, isEmpty);
    expect(bhilai().tripId, isNotEmpty);
  });

  test('ids are not guessable from one another', () {
    final ids = {for (var i = 0; i < 50; i++) bhilai().tripId};
    expect(ids, hasLength(50), reason: 'every trip gets its own id');
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z2-9]{12}$')));
    }
  });

  test('adjusting dates or activities keeps the id', () {
    // A link already shared with a fellow traveller must keep working.
    final p = bhilai();
    final id = p.tripId;

    p.buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 9, 2),
      end: DateTime(2026, 9, 5),
      activities: ['Temple', 'Park', 'Lake'],
    );
    expect(p.tripId, id);
  });

  test('a different destination is a different trip', () {
    final p = bhilai();
    final id = p.tripId;
    p.buildFromSelection(
      destination: 'Raipur',
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
      activities: ['Temple', 'Park'],
    );
    expect(p.tripId, isNot(id));
  });

  test('the id survives a restart', () async {
    final id = bhilai().tripId;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((TripPlanProvider()..restore()).tripId, id);
  });

  test('editing places does not change the trip', () async {
    final p = bhilai();
    final id = p.tripId;
    p.removeItem(0, 0);
    p.addItems(0, ['Maitri Baag Zoo']);
    expect(p.tripId, id);
  });

  test('a plan saved before ids existed is given one on restore', () async {
    bhilai();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Simulate the older record shape, which had no trip_id.
    final stored = LocalStore.load(LocalStore.keyTripPlan)!;
    stored.remove('trip_id');
    LocalStore.save(LocalStore.keyTripPlan, stored);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final after = TripPlanProvider()..restore();
    expect(after.plan, isNotNull, reason: 'the old plan still loads');
    expect(after.tripId, isNotEmpty,
        reason: 'and can be shared without being rebuilt');
  });

  test('clearing forgets the trip', () {
    final p = bhilai();
    p.clear();
    expect(p.tripId, isEmpty);
  });
}
