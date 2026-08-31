import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_travel_app/services/trip_sync.dart';

/// How a suggestion reads to the person deciding on it is the whole interface
/// of this feature — it is the only thing the owner sees before saying yes.
void main() {
  TripProposal from(Map<String, dynamic> data) =>
      TripProposal.fromDoc('abc123', data);

  test('an addition reads as a sentence', () {
    final p = from({
      'kind': 'add',
      'day': 1,
      'title': 'Maitri Baag Zoo',
      'by': 'priya',
    });
    expect(p.summary, 'Add Maitri Baag Zoo to Day 2');
    expect(p.isAdd, isTrue);
  });

  test('a removal reads as a sentence', () {
    final p = from({
      'kind': 'remove',
      'day': 0,
      'title': 'Wave World Water Park',
      'by': 'priya',
    });
    expect(p.summary, 'Remove Wave World Water Park from Day 1');
    expect(p.isAdd, isFalse);
  });

  test('days are shown one-based, as the trip page numbers them', () {
    // Day 0 in the data is "Day 1" to a human. Getting this wrong would send
    // the owner to approve a change to the wrong day.
    expect(from({'kind': 'add', 'day': 0, 'title': 'X'}).summary,
        contains('Day 1'));
    expect(from({'kind': 'add', 'day': 4, 'title': 'X'}).summary,
        contains('Day 5'));
  });

  test('a malformed proposal does not throw', () {
    final p = from({});
    expect(p.title, isEmpty);
    expect(p.dayIndex, 0);
    expect(p.isAdd, isFalse, reason: 'unknown kinds are not treated as adds');
  });

  test('the id is carried, so a decision can be recorded against it', () {
    expect(from({'kind': 'add', 'day': 0, 'title': 'X'}).id, 'abc123');
  });
}
