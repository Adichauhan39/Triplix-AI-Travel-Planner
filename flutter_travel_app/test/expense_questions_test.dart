import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_questions.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

TripExpense row(String note, int rupees, String by,
        {String category = 'Other', DateTime? at, bool shared = true}) =>
    TripExpense(
      id: '$note$rupees$by',
      by: by,
      byName: by,
      paise: rupees * 100,
      note: note,
      category: category,
      at: at ?? DateTime(2026, 9, 14, 12),
      shared: shared,
    );

void main() {
  const people = [
    TripPerson(uid: 'me', name: 'Adi', email: ''),
    TripPerson(uid: 'b', name: 'Bulla', email: ''),
    TripPerson(uid: 's', name: 'Surendra', email: ''),
  ];
  final trip = [DateTime(2026, 9, 13), DateTime(2026, 9, 14)];

  final ledger = [
    row('Dinner', 1800, 'me', category: 'Food', at: DateTime(2026, 9, 13, 20)),
    row('Cab to fort', 600, 'b', category: 'Travel',
        at: DateTime(2026, 9, 14, 9)),
    row('Lunch', 400, 'b', category: 'Food', at: DateTime(2026, 9, 14, 13)),
    row('Gifts', 900, 's', category: 'Shopping', shared: false,
        at: DateTime(2026, 9, 14, 17)),
  ];

  String? ask(String q, {List<TripExpense>? rows}) => answerAboutExpenses(
        q,
        approved: rows ?? ledger,
        people: people,
        me: 'me',
        tripDates: trip,
      )?.text;

  group('it answers from the ledger', () {
    test('the total', () {
      final a = ask('how much have we spent')!;
      // 1800 + 600 + 400 + 900
      expect(a, contains('3,700'));
      expect(a, contains('4 expenses'));
    });

    test('and separates shared from personal', () {
      // Gifts are somebody's own, so the shared figure is lower.
      expect(ask('total so far'), contains('2,800'));
    });

    test('by kind', () {
      expect(ask('how much on food'), contains('2,200'));
    });

    test('by a word for a kind, not just the kind', () {
      // "taxi" is Travel in the same vocabulary the notes are filed against.
      expect(ask('how much on taxi'), contains('600'));
    });

    test('by day number', () {
      expect(ask('what did day 2 cost'), contains('1,900'));
    });

    test('for one person', () {
      final a = ask('how much did bulla pay')!;
      expect(a, contains('1,000'));
      expect(a, contains('Bulla'));
    });

    test('my own paid and share', () {
      expect(ask('what is my share'), contains('You paid'));
    });

    test('how many expenses', () {
      expect(ask('how many expenses'), contains('4 expenses'));
    });

    test('who owes whom', () {
      final a = ask('who owes whom')!;
      expect(a.toLowerCase(), contains('owe'));
    });

    test('a day with nothing on it says so, rather than zero', () {
      expect(ask('what did day 9 cost'), contains('Nothing is recorded'));
    });

    test('an empty ledger says there is nothing yet', () {
      expect(ask('how much have we spent', rows: []),
          contains('Nothing is recorded yet'));
    });
  });

  group('it stays quiet when it should', () {
    // Null means the chat says "I can only do expenses" instead of letting
    // something invent an answer -- the whole point of this file.
    test('travel advice is not its job', () {
      expect(ask('what should I see in Jaipur'), isNull);
      expect(ask('is the weather good tomorrow'), isNull);
      expect(ask('book me a hotel'), isNull);
    });

    test('nor general chat', () {
      expect(ask('hello'), isNull);
      expect(ask('thanks'), isNull);
    });

    test('nor an empty message', () {
      expect(ask('   '), isNull);
    });
  });
}
