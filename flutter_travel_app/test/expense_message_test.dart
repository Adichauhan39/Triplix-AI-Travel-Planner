import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_message.dart';

void main() {
  group('readExpense', () {
    test('reads the sentence that prompted this', () {
      final spoken = readExpense('500 paid by bulla for the horse ride');
      expect(spoken, isNotNull);
      expect(spoken!.rupees, 500);
      expect(spoken.payer, 'bulla');
      // "the" is not part of what the money was for.
      expect(spoken.description, 'horse ride');
    });

    test('reads the payer stated first', () {
      final spoken = readExpense('bulla paid 500 for lunch');
      expect(spoken!.payer, 'bulla');
      expect(spoken.rupees, 500);
      expect(spoken.description, 'lunch');
    });

    test('no payer means the person typing', () {
      final spoken = readExpense('spent 2000 on hotel');
      expect(spoken!.payer, isNull);
      expect(spoken.rupees, 2000);
      expect(spoken.description, 'hotel');
    });

    test('handles a rupee symbol and commas', () {
      final spoken = readExpense('₹1,250 for dinner');
      expect(spoken!.rupees, 1250);
      expect(spoken.description, 'dinner');
    });

    test('handles rs and paise', () {
      final spoken = readExpense('rs 99.50 for tea');
      expect(spoken!.rupees, 99.5);
    });

    test('a payment method is not a person', () {
      // "paid by card" must not file the expense against somebody called
      // Card -- and matchPerson would not find them, so it would silently
      // fall back to the typist. Better to read it correctly here.
      expect(readExpense('500 paid by card for lunch')?.payer, isNull);
      expect(readExpense('500 paid by upi for lunch')?.payer, isNull);
    });

    test('"paid by me" is the person typing', () {
      expect(readExpense('500 paid by me for lunch')?.payer, isNull);
    });

    test('the payer does not leak into the description', () {
      final spoken = readExpense('300 for coffee by arjun');
      expect(spoken!.payer, 'arjun');
      expect(spoken.description, 'coffee');
    });

    test('a question is not an expense', () {
      expect(readExpense('how much have we spent'), isNull);
      expect(readExpense('what is my budget'), isNull);
    });

    test('an amount with nothing it was for is not filed', () {
      // "500" alone could be a budget, a distance or a typo.
      expect(readExpense('500'), isNull);
      expect(readExpense('bulla paid 500'), isNull);
    });

    test('zero and negatives are refused', () {
      expect(readExpense('0 for lunch'), isNull);
    });

    test('a two-word name survives', () {
      final spoken = readExpense('500 paid by ram kumar for dinner');
      expect(spoken!.payer, 'ram kumar');
      expect(spoken.description, 'dinner');
    });

    test('a trailing full stop is not part of the name', () {
      expect(readExpense('500 for tea by adi.')?.payer, 'adi');
    });
  });

  group('matchPerson', () {
    const people = {
      'uid-a': 'Bulla',
      'uid-b': 'Arjun Singh',
      'uid-c': 'aditya',
    };

    test('matches regardless of case', () {
      expect(matchPerson('bulla', people), 'uid-a');
      expect(matchPerson('BULLA', people), 'uid-a');
      expect(matchPerson('Aditya', people), 'uid-c');
    });

    test('matches a first name', () {
      expect(matchPerson('arjun', people), 'uid-b');
    });

    test('an unknown name matches nobody', () {
      // Filing money against the wrong person is worse than not filing it.
      expect(matchPerson('priya', people), isNull);
    });

    test('null in, null out', () {
      expect(matchPerson(null, people), isNull);
      expect(matchPerson('   ', people), isNull);
    });

    test('an ambiguous first name matches nobody', () {
      const twoArjuns = {'uid-1': 'Arjun Singh', 'uid-2': 'Arjun Verma'};
      expect(matchPerson('arjun', twoArjuns), isNull);
    });

    test('an exact match beats a partial one', () {
      const both = {'uid-1': 'Arjun', 'uid-2': 'Arjun Verma'};
      expect(matchPerson('arjun', both), 'uid-1');
    });
  });
}
