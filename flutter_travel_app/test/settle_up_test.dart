import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_travel_app/services/settle_up.dart';

/// The settlement is the one place in this app where being subtly wrong costs
/// somebody real money, so it is tested for the properties that matter rather
/// than a couple of happy paths.
void main() {
  int paid(List<Debt> debts, String person) => debts
      .where((d) => d.from == person)
      .fold(0, (sum, d) => sum + d.paise);

  int received(List<Debt> debts, String person) => debts
      .where((d) => d.to == person)
      .fold(0, (sum, d) => sum + d.paise);

  group('fair shares', () {
    test('an even split is even', () {
      expect(fairShares(30000, ['a', 'b', 'c']),
          {'a': 10000, 'b': 10000, 'c': 10000});
    });

    test('shares always add back up to the total', () {
      // ₹100 split three ways is the classic case: 33.33 x 3 is 99.99, and
      // the missing paisa has to go somewhere deliberate.
      for (final total in [10000, 10001, 10002, 1, 7, 99999]) {
        for (final n in [2, 3, 4, 7]) {
          final people = [for (var i = 0; i < n; i++) 'p$i'];
          final shares = fairShares(total, people);
          expect(shares.values.fold(0, (a, b) => a + b), total,
              reason: 'splitting $total between $n people lost money');
        }
      }
    });

    test('nobody is short by more than a paisa', () {
      final shares = fairShares(10000, ['a', 'b', 'c']);
      final values = shares.values.toList()..sort();
      expect(values.last - values.first, lessThanOrEqualTo(1));
    });

    test('the same split comes out the same way twice', () {
      expect(fairShares(10000, ['c', 'a', 'b']),
          fairShares(10000, ['a', 'b', 'c']),
          reason: 'order of the member list must not change who pays the extra');
    });
  });

  group('settling up', () {
    test('the simple case reads the way a person would say it', () {
      // Priya paid 4200, you paid 6100. Total 10300, half is 5150.
      final debts = settleUp(
        paidPaise: {'priya': 420000, 'you': 610000},
        people: ['priya', 'you'],
      );
      expect(debts, hasLength(1));
      expect(debts.first.from, 'priya');
      expect(debts.first.to, 'you');
      expect(debts.first.rupees, 950.0);
    });

    test('nobody pays more than they owe, or receives more than they are owed',
        () {
      final paidBy = {'a': 100000, 'b': 50000, 'c': 0};
      final people = ['a', 'b', 'c'];
      final debts = settleUp(paidPaise: paidBy, people: people);

      final total = paidBy.values.fold(0, (x, y) => x + y);
      final shares = fairShares(total, people);
      for (final p in people) {
        final net = (paidBy[p] ?? 0) - shares[p]!;
        if (net > 0) {
          expect(received(debts, p) - paid(debts, p), net);
        } else {
          expect(paid(debts, p) - received(debts, p), -net);
        }
      }
    });

    test('money is neither created nor destroyed', () {
      final debts = settleUp(
        paidPaise: {'a': 33333, 'b': 1, 'c': 0, 'd': 99999},
        people: ['a', 'b', 'c', 'd'],
      );
      final out = debts.fold(0, (sum, d) => sum + d.paise);
      final back = debts.fold(0, (sum, d) => sum + d.paise);
      expect(out, back);
      for (final d in debts) {
        expect(d.paise, greaterThan(0), reason: 'no zero or negative payments');
      }
    });

    test('somebody who paid nothing still owes their share', () {
      final debts = settleUp(
        paidPaise: {'a': 90000},
        people: ['a', 'b', 'c'],
      );
      expect(debts.map((d) => d.from).toSet(), {'b', 'c'});
      expect(debts.every((d) => d.to == 'a'), isTrue);
      expect(debts.fold(0, (s, d) => s + d.paise), 60000);
    });

    test('an even split needs no payments at all', () {
      expect(
        settleUp(paidPaise: {'a': 5000, 'b': 5000}, people: ['a', 'b']),
        isEmpty,
      );
    });

    test('two people owing one person send two payments, not more', () {
      final debts = settleUp(
        paidPaise: {'a': 30000, 'b': 0, 'c': 0},
        people: ['a', 'b', 'c'],
      );
      expect(debts, hasLength(2), reason: 'no payments beyond what is needed');
    });

    test('travelling alone settles nothing', () {
      expect(settleUp(paidPaise: {'a': 5000}, people: ['a']), isEmpty);
    });

    test('a trip where nobody has spent yet settles nothing', () {
      expect(settleUp(paidPaise: const {}, people: ['a', 'b']), isEmpty);
    });

    test('the settlement is stable across runs', () {
      Map<String, int> paidBy() => {'a': 12345, 'b': 6789, 'c': 100};
      final first = settleUp(paidPaise: paidBy(), people: ['a', 'b', 'c']);
      final second = settleUp(paidPaise: paidBy(), people: ['c', 'b', 'a']);
      expect(first, second,
          reason: 'reopening the trip must not reshuffle who pays whom');
    });
  });

  group('reading an amount somebody typed', () {
    test('rupees become whole paise', () {
      expect(rupeesToPaise(12.34), 1234);
      expect(rupeesToPaise(1200), 120000);
    });

    test('a stray third decimal rounds rather than being dropped', () {
      // Truncating loses money on every entry; over a trip that adds up.
      expect(rupeesToPaise(12.345), 1235);
      expect(rupeesToPaise(0.005), 1);
    });
  });
}
