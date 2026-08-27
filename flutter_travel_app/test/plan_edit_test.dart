import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_travel_app/providers/trip_plan_provider.dart';
import 'package:flutter_travel_app/services/local_store.dart';

TripPlanProvider seeded() => TripPlanProvider()
  ..buildFromSelection(
    destination: 'Bhilai',
    start: DateTime(2026, 8, 27),
    end: DateTime(2026, 8, 29),
    activities: ['Temple', 'Park', 'Garden'],
  );

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  test('removing a place drops only that one', () {
    final p = seeded();
    final before = p.plan!.activityCount;
    p.removeItem(0, 0);
    expect(p.plan!.activityCount, before - 1);
    expect(p.plan!.days, hasLength(3), reason: 'days must not be dropped');
  });

  test('moving a place changes which day holds it', () {
    final p = seeded();
    final moved = p.plan!.days[0].items.first.title;
    p.moveItem(0, 0, 2);
    expect(p.plan!.days[0].items.any((i) => i.title == moved), isFalse);
    expect(p.plan!.days[2].items.last.title, moved);
    expect(p.plan!.activityCount, 3, reason: 'nothing lost in the move');
  });

  test('moving to the same day is a no-op', () {
    final p = seeded();
    final before = p.plan!.days[0].items.map((i) => i.title).toList();
    p.moveItem(0, 0, 0);
    expect(p.plan!.days[0].items.map((i) => i.title).toList(), before);
  });

  test('out-of-range edits are ignored rather than throwing', () {
    final p = seeded();
    final before = p.plan!.activityCount;
    p.removeItem(9, 0);
    p.removeItem(0, 9);
    p.moveItem(0, 9, 1);
    p.moveItem(0, 0, 9);
    expect(p.plan!.activityCount, before);
  });

  test('an edit survives a restart', () async {
    seeded().removeItem(0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = TripPlanProvider()..restore();
    expect(after.plan!.activityCount, 2);
  });

  test('rebuilding from the same inputs does not undo an edit', () async {
    final p = seeded();
    p.removeItem(0, 0);
    // What the screen does on every build.
    p.buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 8, 27),
      end: DateTime(2026, 8, 29),
      activities: ['Temple', 'Park', 'Garden'],
    );
    expect(p.plan!.activityCount, 2,
        reason: 'a removed place must not reappear on the next rebuild');
  });

  test('fillEmptyDays covers every empty day and leaves full ones alone', () {
    final p = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 29),
        activities: ['Green Space'],
      );
    expect(p.plan!.days.where((d) => d.items.isEmpty), hasLength(3),
        reason: 'one interest gives one place, so three days start empty');
    final kept = p.plan!.days.first.items.single.title;

    // Three empty days at two apiece needs six, which is what the screen
    // requests: emptyDays * 2.
    p.fillEmptyDays([
      'Shaheed Udyaan',
      'ARJUN RATH PARK',
      'Dam View point',
      'I Love Bhilai',
      'Pioneer monument garden',
      'Garden Space',
    ]);

    expect(p.plan!.days.where((d) => d.items.isEmpty), isEmpty);
    expect(p.plan!.days.first.items.single.title, kept,
        reason: 'a day that already had something is untouched');
    // The category was the user's choice, so its places are not badged.
    expect(p.plan!.days[1].items.first.addedByAssistant, isFalse);
  });

  test('fillEmptyDays never repeats a place already in the plan', () {
    final p = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 27),
        activities: ['Shaheed Udyaan'],
      );
    p.fillEmptyDays(['shaheed udyaan', 'Dam View point']);
    final titles =
        p.plan!.days.expand((d) => d.items.map((i) => i.title.toLowerCase()));
    expect(titles.where((t) => t == 'shaheed udyaan'), hasLength(1));
  });

  test('changing the activities rebuilds the plan', () {
    final p = seeded();
    p.removeItem(0, 0);
    final before = p.plan!.activityCount;

    p.buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 8, 27),
      end: DateTime(2026, 8, 29),
      activities: ['Temple', 'Park', 'Garden', 'Lake'],
    );
    expect(p.plan!.activityCount, greaterThan(before),
        reason: 'a new activity must reach the plan');
  });

  test('changing the trip length rebuilds the plan', () {
    final p = seeded();
    expect(p.plan!.days, hasLength(3));
    p.buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 8, 27),
      end: DateTime(2026, 8, 28),
      activities: ['Temple', 'Park', 'Garden'],
    );
    expect(p.plan!.days, hasLength(2),
        reason: 'a shorter trip must not keep the old days');
  });

  test('changing the destination rebuilds the plan', () {
    final p = seeded();
    p.buildFromSelection(
      destination: 'Raipur',
      start: DateTime(2026, 8, 27),
      end: DateTime(2026, 8, 29),
      activities: ['Temple', 'Park', 'Garden'],
    );
    expect(p.plan!.destination, 'Raipur');
  });

  test('an edit survives a restart and the rebuild that follows it', () async {
    seeded().removeItem(0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // What the screen does on its first frame after a cold start.
    final after = TripPlanProvider()..restore();
    after.buildFromSelection(
      destination: 'Bhilai',
      start: DateTime(2026, 8, 27),
      end: DateTime(2026, 8, 29),
      activities: ['Temple', 'Park', 'Garden'],
    );
    expect(after.plan!.activityCount, 2,
        reason: 'the removed place must not come back on relaunch');
  });
}
