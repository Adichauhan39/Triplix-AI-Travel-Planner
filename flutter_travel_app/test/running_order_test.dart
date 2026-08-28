import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_travel_app/screens/trip_plan_screen.dart';

/// The day the user reported: the card listed the places in the order they
/// were added, while the schedule underneath visited them in another order
/// entirely.
const _notes = [
  '09:30 Set off for Indian Coffee House, about 15 minutes.',
  '09:45 Have coffee at Indian Coffee House for 1 hour.',
  '11:00 Spend 2 hours at Nehru Art Gallery.',
  '13:15 Have lunch at Hari Raj Pure Veg Restaurant for about an hour.',
];

List<String> ordered(List<String> names, List<String> notes) =>
    [for (final i in runningOrderIndices(names, notes)) names[i]];

void main() {
  test('places follow the running order, not the order they were added', () {
    expect(
      ordered(const [
        'Nehru Art Gallery',
        'Hari Raj Pure Veg Restaurant',
        'Indian Coffee House',
      ], _notes),
      ['Indian Coffee House', 'Nehru Art Gallery', 'Hari Raj Pure Veg Restaurant'],
    );
  });

  test('a place the schedule never names keeps its place at the end', () {
    final result = ordered(const [
      'Maitri Baag Zoo',
      'Nehru Art Gallery',
      'Indian Coffee House',
    ], _notes);
    expect(result.first, 'Indian Coffee House');
    expect(result.last, 'Maitri Baag Zoo',
        reason: 'unmentioned places sort to the end rather than vanishing');
  });

  test('two unmentioned places keep their original order', () {
    expect(
      ordered(const ['Alpha', 'Beta'], _notes),
      ['Alpha', 'Beta'],
    );
  });

  test('no schedule leaves the order untouched', () {
    expect(
      ordered(const ['Third', 'First', 'Second'], const []),
      ['Third', 'First', 'Second'],
    );
  });

  test('a name contained in another does not steal its position', () {
    // "Amit Park" is a substring of "Hotel Amit Park International", so both
    // match at the same index. The longer, more specific name is the one the
    // line is actually about.
    final result = ordered(const ['Amit Park', 'Hotel Amit Park International'],
        const ['20:00 Dine at Hotel Amit Park International.']);
    expect(result.first, 'Hotel Amit Park International');
  });

  test('matching ignores case', () {
    expect(
      ordered(const ['NEHRU ART GALLERY', 'Indian Coffee House'], _notes),
      ['Indian Coffee House', 'NEHRU ART GALLERY'],
    );
  });

  test('every place is returned exactly once', () {
    const names = ['A place', 'Nehru Art Gallery', 'Indian Coffee House', 'B'];
    final result = ordered(names, _notes);
    expect(result, hasLength(names.length));
    expect(result.toSet(), names.toSet());
  });
}
