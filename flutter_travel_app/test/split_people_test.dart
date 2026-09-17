import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

List<String> uids(Map<String, dynamic> data) =>
    [for (final p in TripSync.splitPeopleOf(data)) p.uid];

void main() {
  test('a friend approved only for the budget is in the split', () {
    // The bug: splitting read `members`, so Surendra -- let into the money
    // but not the itinerary -- had no column and owed nothing.
    final trip = {
      'owner': 'adi',
      'members': ['adi'],
      'money': ['adi', 'surendra'],
    };
    expect(uids(trip), containsAll(['adi', 'surendra']));
  });

  test('a friend approved only for the plan is not charged', () {
    // And the other half: Priya can help pick restaurants, cannot see the
    // money, and was still being handed a share of it.
    final trip = {
      'owner': 'adi',
      'members': ['adi', 'priya'],
      'money': ['adi'],
    };
    expect(uids(trip), isNot(contains('priya')));
    expect(uids(trip), ['adi']);
  });

  test('a trip from before the budget had its own list splits as it did', () {
    // No `money` field at all: every member could record spending, so every
    // member shares the bill. Nothing about an old trip changes.
    final old = {
      'owner': 'adi',
      'members': ['adi', 'bulla', 'surendra'],
    };
    expect(uids(old), ['adi', 'bulla', 'surendra']);
  });

  test('names come from the trip, as before', () {
    final trip = {
      'owner': 'adi',
      'money': ['adi', 'surendra'],
      'profiles': {
        'surendra': {'name': 'Surendra'},
      },
    };
    final people = TripSync.splitPeopleOf(trip);
    expect(people.firstWhere((p) => p.uid == 'surendra').name, 'Surendra');
  });

  test('an empty money list means nobody, not everybody', () {
    // Once the list exists it is the only thing consulted, so removing the
    // last person cannot silently fall back to the whole membership.
    final trip = {
      'owner': 'adi',
      'members': ['adi', 'priya'],
      'money': <String>[],
    };
    expect(uids(trip), isEmpty);
  });
}
