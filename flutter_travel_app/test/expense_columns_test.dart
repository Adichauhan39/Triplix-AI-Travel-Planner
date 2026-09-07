import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_columns.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

TripExpense expense(String by, int paise, {String note = 'x', String name = ''}) =>
    TripExpense(
      id: '$by-$paise-$note',
      by: by,
      byName: name,
      paise: paise,
      note: note,
      category: 'Other',
      at: DateTime(2026, 1, 1),
    );

TripPerson person(String uid, String name) =>
    TripPerson(uid: uid, name: name, email: '');

void main() {
  group('buildExpenseColumns', () {
    test('puts each expense under the person who paid', () {
      final columns = buildExpenseColumns(
        approved: [
          expense('u1', 60000, note: 'dinner'),
          expense('u2', 50000, note: 'cab'),
          expense('u3', 5600, note: 'mobile'),
          expense('u3', 20000, note: 'bus'),
        ],
        people: [person('u1', 'Bulla'), person('u2', 'You'), person('u3', 'arjun')],
        me: 'u2',
      );

      expect(columns, hasLength(3));
      final arjun = columns.firstWhere((c) => c.uid == 'u3');
      expect(arjun.expenses.map((e) => e.note), ['mobile', 'bus']);
      expect(arjun.paid, 25600);
    });

    test('the viewer comes first', () {
      final columns = buildExpenseColumns(
        approved: [expense('u1', 100000)],
        people: [person('u1', 'Bulla'), person('u2', 'Me')],
        me: 'u2',
      );
      // Even having paid nothing, you are the column you look for first.
      expect(columns.first.uid, 'u2');
      expect(columns.first.name, 'You');
    });

    test('a member who paid nothing still owes their share', () {
      final columns = buildExpenseColumns(
        approved: [expense('u1', 90000)],
        people: [person('u1', 'A'), person('u2', 'B')],
        me: null,
      );
      final b = columns.firstWhere((c) => c.uid == 'u2');
      expect(b.paid, 0);
      expect(b.share, 45000);
      expect(b.balance, -45000);
      expect(b.inSplit, isTrue);
    });

    test('a payer who has left the trip keeps a column', () {
      // The point of the whole exercise: building from members alone would
      // drop this money from the screen while the headline total still counted
      // it, and the columns would not add up.
      final columns = buildExpenseColumns(
        approved: [expense('u1', 50000), expense('gone', 30000, name: 'Old')],
        people: [person('u1', 'A')],
        me: null,
      );
      expect(columns.map((c) => c.uid), containsAll(['u1', 'gone']));
      final left = columns.firstWhere((c) => c.uid == 'gone');
      expect(left.paid, 30000);
      expect(left.inSplit, isFalse);
      // No balance is claimed for somebody the settlement will never pay.
      expect(left.share, 0);
      expect(left.name, 'Old');
    });

    test('the columns account for every rupee of the total', () {
      final rows = [
        expense('u1', 60000),
        expense('u2', 50000),
        expense('u3', 5600),
        expense('u3', 20000),
        expense('gone', 700),
      ];
      final columns = buildExpenseColumns(
        approved: rows,
        people: [person('u1', 'A'), person('u2', 'B'), person('u3', 'C')],
        me: 'u2',
      );

      final total = rows.fold<int>(0, (s, r) => s + r.paise);
      final shown = columns.fold<int>(0, (s, c) => s + c.paid);
      expect(shown, total);
    });

    test('an uneven split leaves no stray paise', () {
      final columns = buildExpenseColumns(
        approved: [expense('u1', 10000)],
        people: [person('u1', 'A'), person('u2', 'B'), person('u3', 'C')],
        me: null,
      );
      final shares = columns.fold<int>(0, (s, c) => s + c.share);
      // 100 rupees three ways: the remainder has to land somewhere.
      expect(shares, 10000);
    });

    test('balances cancel out among members', () {
      final columns = buildExpenseColumns(
        approved: [expense('u1', 200000), expense('u2', 70000)],
        people: [person('u1', 'A'), person('u2', 'B')],
        me: null,
      );
      final sum = columns.fold<int>(0, (s, c) => s + c.balance);
      expect(sum, 0);
    });

    test('no expenses still shows the members', () {
      final columns = buildExpenseColumns(
        approved: const [],
        people: [person('u1', 'A'), person('u2', 'B')],
        me: null,
      );
      expect(columns, hasLength(2));
      expect(columns.every((c) => c.paid == 0 && c.share == 0), isTrue);
    });

    test('nobody at all gives nothing', () {
      expect(
        buildExpenseColumns(approved: const [], people: const [], me: null),
        isEmpty,
      );
    });

    test('rows with no payer are ignored rather than grouped together', () {
      final columns = buildExpenseColumns(
        approved: [expense('', 5000), expense('u1', 10000)],
        people: [person('u1', 'A')],
        me: null,
      );
      expect(columns, hasLength(1));
      expect(columns.single.paid, 10000);
    });

    test('the order does not wobble between builds', () {
      List<String> order() => buildExpenseColumns(
            approved: [expense('u1', 5000), expense('u2', 5000)],
            people: [person('u1', 'Bea'), person('u2', 'Ann')],
            me: null,
          ).map((c) => c.uid).toList();
      // Equal amounts fall back to the name, so this is stable.
      expect(order(), order());
      expect(order().first, 'u2');
    });
  });

  group('displayName', () {
    test('is You for the viewer', () {
      expect(displayName('u1', me: 'u1'), 'You');
    });

    test('prefers the trip nickname', () {
      expect(
        displayName('u1',
            people: [person('u1', 'Adi')],
            expenses: [expense('u1', 100, name: 'Aditya Chauhan')]),
        'Adi',
      );
    });

    test('falls back to the name stored on the row', () {
      expect(
        displayName('u1', expenses: [expense('u1', 100, name: 'Aditya')]),
        'Aditya',
      );
    });

    test('falls back to a shortened uid, never a placeholder', () {
      // Two unnamed people both reading "Someone" cannot be told apart.
      expect(displayName('abcdefghijkl'), 'abcdefgh…');
    });
  });

  group('formatRupees', () {
    test('drops empty decimals', () {
      expect(formatRupees(50000), '₹500');
    });

    test('keeps real ones', () {
      expect(formatRupees(9950), '₹99.50');
    });

    test('groups the Indian way', () {
      expect(formatRupees(14000000), '₹1,40,000');
      expect(formatRupees(100000), '₹1,000');
    });

    test('is unsigned, so the caller chooses the sign', () {
      expect(formatRupees(-65000), '₹650');
    });
  });
}
