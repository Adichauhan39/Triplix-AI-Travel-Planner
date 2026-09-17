import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_insights.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

TripExpense row(
  String note,
  int rupees, {
  String category = 'Other',
  String by = 'me',
  String byName = 'Me',
  DateTime? at,
  bool shared = true,
}) =>
    TripExpense(
      id: '$note-$rupees-${at?.millisecondsSinceEpoch}',
      by: by,
      byName: byName,
      paise: rupees * 100,
      note: note,
      category: category,
      at: at ?? DateTime(2026, 9, 14, 12),
      shared: shared,
    );

void main() {
  group('by kind', () {
    test('adds up each kind, largest first', () {
      final out = spendByCategory([
        row('lunch', 300, category: 'Food'),
        row('hotel', 4000, category: 'Stay'),
        row('dinner', 900, category: 'Food'),
        row('cab', 500, category: 'Travel'),
      ]);
      expect([for (final c in out) c.category], ['Stay', 'Food', 'Travel']);
      expect(out[1].paise, 120000, reason: '300 + 900 of food');
      expect(out[1].count, 2);
    });

    test("somebody's own spending still counts as what the trip cost", () {
      // Where the money went, not who owes whom.
      final out = spendByCategory(
          [row('gifts', 800, category: 'Shopping', shared: false)]);
      expect(out.single.paise, 80000);
    });

    test('a blank kind is filed under Other, not left nameless', () {
      final out = spendByCategory([row('mystery', 100, category: '  ')]);
      expect(out.single.category, 'Other');
    });

    test('equal amounts keep a steady order', () {
      // A chart that reshuffles itself between rebuilds looks broken.
      final a = spendByCategory([
        row('x', 500, category: 'Travel'),
        row('y', 500, category: 'Food'),
      ]);
      final b = spendByCategory([
        row('y', 500, category: 'Food'),
        row('x', 500, category: 'Travel'),
      ]);
      expect([for (final c in a) c.category], [for (final c in b) c.category]);
    });

    test('nothing spent is nothing to draw', () {
      expect(spendByCategory([]), isEmpty);
    });
  });

  group('by day', () {
    final trip = [DateTime(2026, 9, 13), DateTime(2026, 9, 14),
                  DateTime(2026, 9, 15)];

    test('each day of the trip is numbered', () {
      final out = spendByDay([
        row('cab', 500, at: DateTime(2026, 9, 13, 9)),
        row('lunch', 300, at: DateTime(2026, 9, 14, 13)),
        row('dinner', 900, at: DateTime(2026, 9, 14, 20)),
      ], tripDates: trip);

      expect(out.length, 2);
      expect(out[0].dayNumber, 1);
      expect(out[1].dayNumber, 2);
      expect(out[1].paise, 120000, reason: 'lunch and dinner on the 14th');
      expect(out[1].count, 2);
    });

    test('money outside the trip is kept, just not called Day N', () {
      // A deposit paid a month early is real spending, but it is not Day 1.
      final out = spendByDay([
        row('deposit', 2000, at: DateTime(2026, 8, 10)),
        row('cab', 500, at: DateTime(2026, 9, 13)),
      ], tripDates: trip);
      expect(out.length, 2, reason: 'nothing is dropped');
      expect(out.first.dayNumber, isNull);
      expect(out.last.dayNumber, 1);
    });

    test('in date order whatever order it was recorded in', () {
      final out = spendByDay([
        row('later', 100, at: DateTime(2026, 9, 15)),
        row('earlier', 100, at: DateTime(2026, 9, 13)),
      ]);
      expect(out.first.date, DateTime(2026, 9, 13));
    });

    test('no itinerary still groups by date', () {
      final out = spendByDay([row('cab', 500, at: DateTime(2026, 9, 13))]);
      expect(out.single.dayNumber, isNull);
      expect(out.single.paise, 50000);
    });

    test('the trip dates may arrive in any order', () {
      final out = spendByDay(
        [row('cab', 500, at: DateTime(2026, 9, 14))],
        tripDates: [DateTime(2026, 9, 15), DateTime(2026, 9, 13),
                    DateTime(2026, 9, 14)],
      );
      expect(out.single.dayNumber, 2);
    });
  });

  group('search', () {
    final rows = [
      row('Dinner at Chokhi Dhani', 1800, category: 'Food', byName: 'Bulla',
          at: DateTime(2026, 9, 14, 20)),
      row('Lunch', 400, category: 'Food', byName: 'Surendra',
          at: DateTime(2026, 9, 14, 13)),
      row('Cab to fort', 600, category: 'Travel', byName: 'Bulla',
          at: DateTime(2026, 9, 13, 9)),
    ];

    test('finds by what it was for', () {
      final found = searchExpenses(rows, 'dinner');
      expect(found.matches.single.note, 'Dinner at Chokhi Dhani');
    });

    test('finds by kind, and adds them up', () {
      final found = searchExpenses(rows, 'food');
      expect(found.matches.length, 2);
      expect(found.paise, 220000);
    });

    test('finds by who paid', () {
      expect(searchExpenses(rows, 'bulla').matches.length, 2);
    });

    test('every word has to match, in any order', () {
      // "food bulla" means Bulla's food, not everything Bulla or all food.
      final found = searchExpenses(rows, 'bulla food');
      expect(found.matches.single.note, 'Dinner at Chokhi Dhani');
    });

    test('capital letters do not matter', () {
      expect(searchExpenses(rows, 'CAB').matches.length, 1);
    });

    test('newest first', () {
      final found = searchExpenses(rows, 'food');
      expect(found.matches.first.note, 'Dinner at Chokhi Dhani');
    });

    test('an empty search finds nothing rather than everything', () {
      expect(searchExpenses(rows, '   ').isEmpty, isTrue);
    });

    test('a name the app knows by uid is searchable too', () {
      final found = searchExpenses(
        [row('Tea', 50, by: 'uid-9', byName: '')],
        'adi',
        nameOf: (uid) => uid == 'uid-9' ? 'Adi' : '',
      );
      expect(found.matches.length, 1);
    });
  });
}
