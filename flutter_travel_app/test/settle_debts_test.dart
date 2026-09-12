import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_columns.dart';
import 'package:flutter_travel_app/services/settle_up.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

/// An approved expense, as the ledger sees it.
TripExpense row({
  required String by,
  required int paise,
  bool shared = true,
  List<String> sharedWith = const [],
  Map<String, int> shares = const {},
}) =>
    TripExpense(
      id: '$by-$paise-${shares.length}-${sharedWith.length}',
      by: by,
      byName: by,
      paise: paise,
      note: 'x',
      category: 'Other',
      at: DateTime(2026, 9, 12),
      shared: shared,
      sharedWith: sharedWith,
      shares: shares,
    );

void main() {
  group('paying somebody back', () {
    test('a full repayment clears the debt', () {
      // You paid 1,000 for two, so Priya owes 500.
      final paid = {'you': 100000, 'priya': 0};
      final before = settleUp(paidPaise: paid, people: ['you', 'priya']);
      expect(before.single.paise, 50000);

      final after = settleUp(
        paidPaise: withRepayments(
          paidPaise: paid,
          repayments: const [
            Repayment(from: 'priya', to: 'you', paise: 50000)
          ],
        ),
        people: ['you', 'priya'],
      );
      expect(after, isEmpty, reason: 'the debt was paid');
    });

    test('a part payment leaves the rest owed', () {
      final after = settleUp(
        paidPaise: withRepayments(
          paidPaise: {'you': 100000, 'priya': 0},
          repayments: const [
            Repayment(from: 'priya', to: 'you', paise: 30000)
          ],
        ),
        people: ['you', 'priya'],
      );
      expect(after.single.from, 'priya');
      expect(after.single.paise, 20000);
    });

    test('paying too much turns the debt around', () {
      // Not something the sheet allows, but the arithmetic must not silently
      // swallow it: the money went somewhere and is now owed back.
      final after = settleUp(
        paidPaise: withRepayments(
          paidPaise: {'you': 100000, 'priya': 0},
          repayments: const [
            Repayment(from: 'priya', to: 'you', paise: 80000)
          ],
        ),
        people: ['you', 'priya'],
      );
      expect(after.single.from, 'you');
      expect(after.single.paise, 30000);
    });

    test('the group total is untouched by a repayment', () {
      // A repayment is not spending. If it changed the total, everybody's
      // share would move and paying a friend back would cost the group money.
      final paid = {'a': 60000, 'b': 30000, 'c': 0};
      final after = withRepayments(
        paidPaise: paid,
        repayments: const [Repayment(from: 'c', to: 'a', paise: 20000)],
      );
      expect(after.values.fold(0, (x, y) => x + y),
          paid.values.fold(0, (x, y) => x + y));
    });

    test('repayments among three people still balance to nothing', () {
      final paid = {'a': 90000, 'b': 0, 'c': 0};
      final debts = settleUp(paidPaise: paid, people: ['a', 'b', 'c']);
      final after = settleUp(
        paidPaise: withRepayments(
          paidPaise: paid,
          repayments: [
            for (final debt in debts)
              Repayment(from: debt.from, to: debt.to, paise: debt.paise)
          ],
        ),
        people: ['a', 'b', 'c'],
      );
      expect(after, isEmpty);
    });

    test('nonsense repayments are ignored rather than trusted', () {
      final out = withRepayments(
        paidPaise: {'a': 10000, 'b': 0},
        repayments: const [
          Repayment(from: 'a', to: 'a', paise: 5000), // to themselves
          Repayment(from: 'b', to: 'a', paise: 0), // nothing
          Repayment(from: 'b', to: 'a', paise: -500), // negative
        ],
      );
      expect(out, {'a': 10000, 'b': 0});
    });

    test('an empty ledger settles to nothing', () {
      expect(settleUp(paidPaise: const {}, people: ['a', 'b']), isEmpty);
    });
  });

  group('exact amounts', () {
    test('each person owes what was set, not an equal share', () {
      // One had the 900 thali, the other a 200 chai. Equal would be 550 each.
      final owed = owedPerPerson(
        approved: [
          row(by: 'a', paise: 110000, shares: {'a': 90000, 'b': 20000}),
        ],
        members: ['a', 'b'],
      );
      expect(owed, {'a': 90000, 'b': 20000});
    });

    test('the whole expense is still accounted for', () {
      final owed = owedPerPerson(
        approved: [
          row(by: 'a', paise: 100000, shares: {'a': 33333, 'b': 66667}),
        ],
        members: ['a', 'b'],
      );
      expect(owed.values.fold(0, (x, y) => x + y), 100000);
    });

    test('someone who has left the trip does not take money with them', () {
      // Their portion has to land on somebody or the books stop balancing.
      final owed = owedPerPerson(
        approved: [
          row(by: 'a', paise: 90000, shares: {'a': 30000, 'gone': 60000}),
        ],
        members: ['a', 'b'],
      );
      expect(owed.values.fold(0, (x, y) => x + y), 90000,
          reason: 'the money must not vanish');
      expect(owed['a'], 90000, reason: 'it falls to the people still named');
      expect(owed['b'], 0, reason: 'b was never in this expense');
    });

    test('shares naming nobody still present fall back to an equal split', () {
      final owed = owedPerPerson(
        approved: [
          row(by: 'a', paise: 100000, shares: {'ghost': 100000}),
        ],
        members: ['a', 'b'],
      );
      expect(owed, {'a': 50000, 'b': 50000});
    });

    test('exact and equal rows live side by side', () {
      final owed = owedPerPerson(
        approved: [
          row(by: 'a', paise: 110000, shares: {'a': 90000, 'b': 20000}),
          row(by: 'b', paise: 100000),
        ],
        members: ['a', 'b'],
      );
      expect(owed['a'], 90000 + 50000);
      expect(owed['b'], 20000 + 50000);
    });

    test('the settlement agrees with the columns on an exact split', () {
      // The bug this pair of arguments exists to prevent: the columns divided
      // per expense while the settlement divided the total by everybody.
      final rows = [
        row(by: 'a', paise: 110000, shares: {'a': 90000, 'b': 20000}),
      ];
      final members = ['a', 'b'];
      final owed = owedPerPerson(approved: rows, members: members);
      final debts = settleUp(
        paidPaise: {'a': 110000, 'b': 0},
        people: members,
        owedPaise: owed,
      );
      // a paid 110000 and owes 90000, so b owes them exactly 20000.
      expect(debts.single.from, 'b');
      expect(debts.single.to, 'a');
      expect(debts.single.paise, 20000);
    });

    test('a personal row is not divided by anybody', () {
      final owed = owedPerPerson(
        approved: [row(by: 'a', paise: 50000, shared: false)],
        members: ['a', 'b'],
      );
      expect(owed, {'a': 0, 'b': 0});
    });
  });

  group('the UPI link', () {
    test('carries rupees, not paise', () {
      // The spec's amount is in rupees. Sent as paise it would ask for a
      // hundred times too much.
      final link = upiPaymentLink(
        upiId: 'adi@okhdfcbank',
        payeeName: 'Adi',
        paise: 43335,
      );
      expect(link!.queryParameters['am'], '433.35');
      expect(link.queryParameters['pa'], 'adi@okhdfcbank');
      expect(link.queryParameters['cu'], 'INR');
      expect(link.scheme, 'upi');
    });

    test('refuses an id that is not a UPI id', () {
      // Prefilling a payment screen with a bad id is worse than no button.
      expect(upiPaymentLink(upiId: '9876543210', payeeName: 'A', paise: 100),
          isNull);
      expect(upiPaymentLink(upiId: '', payeeName: 'A', paise: 100), isNull);
    });

    test('refuses a zero or negative amount', () {
      expect(upiPaymentLink(upiId: 'a@bank', payeeName: 'A', paise: 0), isNull);
      expect(
          upiPaymentLink(upiId: 'a@bank', payeeName: 'A', paise: -5), isNull);
    });

    test('a name with a space survives', () {
      final link = upiPaymentLink(
        upiId: 'adi@okhdfcbank',
        payeeName: 'Aditya Chauhan',
        paise: 10000,
        note: 'Jaipur trip',
      );
      expect(link!.queryParameters['pn'], 'Aditya Chauhan');
      expect(link.queryParameters['tn'], 'Jaipur trip');
      expect(link.toString(), contains('Aditya%20Chauhan'));
    });
  });
}
