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

  test('topUpDays fills every short day and leaves full ones alone', () {
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

    // Three empty days plus a day holding one place: seven slots short of
    // two apiece. Six names fills what it can.
    p.topUpDays([
      'Shaheed Udyaan',
      'ARJUN RATH PARK',
      'Dam View point',
      'I Love Bhilai',
      'Pioneer monument garden',
      'Garden Space',
    ]);

    expect(p.plan!.days.where((d) => d.items.isEmpty), isEmpty);
    // The day that already held one place keeps it, first, and gains a
    // second: one place is not a day out. This is the behaviour that
    // replaced "only fill days that are completely empty".
    expect(p.plan!.days.first.items.first.title, kept);
    expect(p.plan!.days.first.items.length, 2);
    // The category was the user's choice, so its places are not badged.
    expect(p.plan!.days[1].items.first.addedByAssistant, isFalse);
  });

  test('topUpDays never repeats a place already in the plan', () {
    final p = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 27),
        activities: ['Shaheed Udyaan'],
      );
    p.topUpDays(['shaheed udyaan', 'Dam View point']);
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

  group('contentKey — what the export watches for', () {
    test('changes when a place is removed', () {
      final p = seeded();
      final before = p.contentKey;
      p.removeItem(0, 0);
      expect(p.contentKey, isNot(before));
    });

    test('changes when a place is added', () {
      final p = seeded();
      final before = p.contentKey;
      p.addItems(0, ['Dam View point']);
      expect(p.contentKey, isNot(before));
    });

    test('changes when a place moves to another day', () {
      final p = seeded();
      final before = p.contentKey;
      p.moveItem(0, 0, 2);
      expect(p.contentKey, isNot(before));
    });

    test('is stable across a rebuild from the same inputs', () {
      final p = seeded();
      final before = p.contentKey;
      // What the screen does on every build. If this shifted, the export
      // would think the plan had changed and prompt on an idle screen.
      p.buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 27),
        end: DateTime(2026, 8, 29),
        activities: ['Temple', 'Park', 'Garden'],
      );
      expect(p.contentKey, before);
    });

    test('is empty with no plan, so nothing is compared before one exists', () {
      expect(TripPlanProvider().contentKey, isEmpty);
    });
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

  test('a day holding one place is topped up to two', () {
    final p = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 27),
        activities: ['Matritva Restaurant'],
      );
    // The reported case: one restaurant on day one, calling itself a plan.
    expect(p.plan!.days.first.items, hasLength(1));
    expect(p.shortfall(minPerDay: 2), 3,
        reason: 'one short on day one, two short on day two');

    p.topUpDays(['Maitri Baag Zoo', 'Shaheed Udyaan', 'Dam View point']);
    for (final day in p.plan!.days) {
      expect(day.items.length, greaterThanOrEqualTo(2));
    }
    expect(p.plan!.days.first.items.first.title, 'Matritva Restaurant',
        reason: 'what was already there stays, and stays first');
  });

  test('shortfall is zero when every day already meets the floor', () {
    final p = seeded();
    expect(p.shortfall(minPerDay: 1), 0);
  });

  test('a higher floor asks for more places', () {
    final p = seeded();
    expect(p.shortfall(minPerDay: 3), 6,
        reason: '3 days holding one apiece, wanting three each');
  });

  group('two categories landing on one venue', () {
    TripPlanProvider withTitles(List<String> titles) => TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 30),
        end: DateTime(2026, 8, 30),
        activities: titles,
      );

    test('the duplicate is dropped and the first one stays', () {
      // The reported case: "Art" and "Cafe" both resolved to WOOWOO, which
      // then appeared twice on Day 1 with the same photo and rating.
      final p = withTitles(['Art', 'Cafe', 'Handicraft']);
      expect(p.plan!.days.first.items, hasLength(3));

      final dropped = p.dropResolvedDuplicates({
        'Art': 'place_woowoo',
        'Cafe': 'place_woowoo',
        'Handicraft': 'place_sai',
      });

      expect(dropped, 1);
      expect(p.plan!.days.first.items.map((i) => i.title),
          ['Art', 'Handicraft'],
          reason: 'the first occurrence keeps its place');
    });

    test('a place we could not identify is never dropped', () {
      final p = withTitles(['Art', 'Cafe']);
      // Empty ids mean "not resolved yet", not "same place".
      expect(p.dropResolvedDuplicates({'Art': '', 'Cafe': ''}), 0);
      expect(p.plan!.days.first.items, hasLength(2));
    });

    test('matching ignores case and spacing in the resolved name', () {
      final p = withTitles(['Art', 'Cafe']);
      expect(
        p.dropResolvedDuplicates(
            {'Art': 'WOOWOO Art House', 'Cafe': ' woowoo art house '}),
        1,
      );
    });

    test('distinct places are all kept', () {
      final p = withTitles(['Art', 'Cafe']);
      expect(p.dropResolvedDuplicates({'Art': 'a', 'Cafe': 'b'}), 0);
      expect(p.plan!.days.first.items, hasLength(2));
    });

    test('duplicates across different days are caught too', () {
      final p = TripPlanProvider()
        ..buildFromSelection(
          destination: 'Bhilai',
          start: DateTime(2026, 8, 30),
          end: DateTime(2026, 8, 31),
          activities: ['Art', 'Cafe'],
        );
      // One per day, both the same venue.
      expect(p.plan!.days, hasLength(2));
      expect(p.dropResolvedDuplicates({'Art': 'same', 'Cafe': 'same'}), 1);
      expect(p.plan!.activityCount, 1);
    });
  });

  test('changing what a day is about replaces only that day', () {
    final p = seeded();
    final otherDays = [
      for (var i = 1; i < p.plan!.days.length; i++)
        p.plan!.days[i].items.map((x) => x.title).toList()
    ];

    p.replaceDayItems(0, ['Jagannath Temple', 'Maitri Baag Zoo']);

    expect(p.plan!.days.first.items.map((i) => i.title),
        ['Jagannath Temple', 'Maitri Baag Zoo']);
    for (var i = 1; i < p.plan!.days.length; i++) {
      expect(p.plan!.days[i].items.map((x) => x.title).toList(),
          otherDays[i - 1],
          reason: 'other days are untouched');
    }
    // The user chose the theme, so these are their places, not suggestions.
    expect(p.plan!.days.first.items.first.addedByAssistant, isFalse);
  });

  test('replaceDayItems ignores an out-of-range day', () {
    final p = seeded();
    final before = p.contentKey;
    p.replaceDayItems(9, ['Somewhere']);
    p.replaceDayItems(0, const []);
    expect(p.contentKey, before);
  });

  test('the two routes into the plan collapse onto one venue', () {
    // Exactly the reported shape: the interest the user picked, which
    // resolved to a real place, and the resolved name added later by the
    // top-up, which has no summary of its own. Keyed on the name both rows
    // display, they are the same venue.
    final p = TripPlanProvider()
      ..buildFromSelection(
        destination: 'Bhilai',
        start: DateTime(2026, 8, 30),
        end: DateTime(2026, 8, 30),
        activities: ['Art'],
      );
    p.topUpDays(['WOOWOO ART HOUSE_Bhilai', 'Sai murti and handicraft'],
        minPerDay: 3);
    expect(p.plan!.days.first.items, hasLength(3));

    final dropped = p.dropResolvedDuplicates({
      // "Art" resolved to the venue; the topped-up row is the venue's name.
      'Art': 'woowoo art house_bhilai',
      'WOOWOO ART HOUSE_Bhilai': 'woowoo art house_bhilai',
      'Sai murti and handicraft': 'sai murti and handicraft',
    });

    expect(dropped, 1);
    expect(p.plan!.days.first.items.map((i) => i.title),
        ['Art', 'Sai murti and handicraft'],
        reason: 'the interest the user picked is the one that stays');
  });
}
