import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_columns.dart';
import 'package:flutter_travel_app/services/expense_message.dart';
import 'package:flutter_travel_app/services/expense_words.dart';
import 'package:flutter_travel_app/services/settle_up.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

/// A playground, not a guard.
///
/// Every other test in here asserts a known answer. This one takes the things
/// a person actually types into a budget chat and prints what the code makes
/// of them, so the gap between the two is visible instead of argued about.
///
/// It always passes. Its value is the output.
void main() {
  test('what the reader makes of things people type', () {
    const lines = [
      // Plain adding.
      '500 for dinner',
      'spent 2000 on hotel',
      'paid 300 for the taxi',
      '₹1,250 for dinner',
      'rs 99.50 for tea',
      'add 500 for food',

      // Naming who paid.
      'bulla paid 500 for lunch',
      '500 paid by bulla for the horse ride',
      'add 5000 to surendra account',
      'add 500 to bulla for food',
      'surendra 500 for food',
      'put 700 on aditya for the cab',
      '600 from arjun for petrol',

      // Keeping it out of the split.
      '500 for food, but dont share it',
      "500 for food, don't share it",
      '2000 for shopping, just mine',
      '800 for medicine, personal',
      'exclude that from share',
      'exclude this from the split',
      'dont share the 500 food',
      'make the dinner personal',
      'remove dinner from the split',

      // Spelling.
      '500 for toxi',
      '300 for dinnner',
      '2000 for hotal',

      // Not expenses at all.
      'how much have we spent',
      'what is my budget',
      'my budget is 20000',
      'who owes me',
      'hi',
    ];

    // ignore: avoid_print
    print('\n${'INPUT'.padRight(42)}  AMOUNT   PAYER      SHARED  NOTE');
    // ignore: avoid_print
    print('${'-' * 42}  -------  ---------  ------  ----------------');

    for (final line in lines) {
      final draft = readExpenseDraft(line);
      final String verdict;
      if (!draft.hasAmount) {
        verdict = 'not money';
      } else if (draft.needsPurpose) {
        verdict = 'ASKS what for';
      } else {
        verdict = 'files it';
      }

      final note = draft.description.isEmpty
          ? '-'
          : tidyNote(draft.description).note;

      // ignore: avoid_print
      print('${line.padRight(42)}  '
          '${(draft.rupees?.toStringAsFixed(0) ?? '-').padLeft(7)}  '
          '${(draft.payer ?? '-').padRight(9)}  '
          '${(draft.hasAmount ? (draft.shared ? 'yes' : 'NO') : '-').padRight(6)}  '
          '$note   [$verdict]');
    }
  });

  test('what it makes of instructions about an existing expense', () {
    const lines = [
      'exclude that from share',
      'exclude this from the split',
      'dont share the dinner',
      "don't share that",
      'make the dinner personal',
      'mark the taxi personal',
      'remove dinner from the split',
      'take the shopping out of the share',
      'keep the medicine out of the split',
      'just mine',
      'put it back in the split',
      'share it again',
      'include the dinner in the split',
      'add that back',
      'make it shared',
      // Must NOT be read as instructions.
      '500 for dinner',
      'how much have we spent',
      'we shared a taxi',
    ];

    // ignore: avoid_print
    print('\n${'INPUT'.padRight(42)}  MEANS');
    // ignore: avoid_print
    print('${'-' * 42}  ------------------------');
    for (final line in lines) {
      final wants = readSplitChange(line);
      final says = wants == null
          ? 'not an instruction'
          : wants
              ? 'PUT BACK in the split'
              : 'TAKE OUT of the split';
      // ignore: avoid_print
      print('${line.padRight(42)}  $says');
    }
  });

  test('what the split does with a mixed day', () {
    TripExpense row(String by, int rupees, String note, {bool shared = true}) =>
        TripExpense(
          id: '$by-$note',
          by: by,
          byName: by,
          paise: rupees * 100,
          note: note,
          category: 'Other',
          at: DateTime(2026, 1, 1),
          shared: shared,
        );

    final rows = [
      row('you', 2000, 'hotel'),
      row('bulla', 600, 'dinner'),
      row('arjun', 200, 'bus'),
      row('you', 5000, 'medical emergency', shared: false),
      row('bulla', 500, 'shopping', shared: false),
    ];

    final people = [
      TripPerson(uid: 'you', name: 'You', email: ''),
      TripPerson(uid: 'bulla', name: 'Bulla', email: ''),
      TripPerson(uid: 'arjun', name: 'arjun', email: ''),
    ];

    final columns = buildExpenseColumns(
      approved: rows,
      people: people,
      me: 'you',
    );

    // ignore: avoid_print
    print('\n  shared total    ${formatRupees(sharedTotal(rows))}');
    // ignore: avoid_print
    print('  personal total  ${formatRupees(personalTotal(rows))}');
    // ignore: avoid_print
    print('  everything      ${formatRupees(rows.fold<int>(0, (s, r) => s + r.paise))}');
    // ignore: avoid_print
    print('\n  WHO      PAID     JUST THEIRS   SHARE    BALANCE');
    for (final c in columns) {
      // ignore: avoid_print
      print('  ${c.name.padRight(7)}  '
          '${formatRupees(c.paid).padLeft(7)}  '
          '${formatRupees(c.personal).padLeft(11)}  '
          '${formatRupees(c.share).padLeft(7)}  '
          '${(c.balance >= 0 ? '+' : '-') + formatRupees(c.balance)}');
    }

    final paid = <String, int>{};
    for (final r in rows.where((r) => r.shared)) {
      paid[r.by] = (paid[r.by] ?? 0) + r.paise;
    }
    final debts = settleUp(
      paidPaise: paid,
      people: [for (final p in people) p.uid],
    );
    // ignore: avoid_print
    print('\n  settling up:');
    for (final d in debts) {
      // ignore: avoid_print
      print('    ${d.from} pays ${d.to} ${formatRupees(d.paise)}');
    }

    // The one thing that must always hold.
    final sum = columns.fold<int>(0, (s, c) => s + c.balance);
    // ignore: avoid_print
    print('\n  balances sum to $sum  (must be 0)');
    expect(sum, 0);
  });
}
