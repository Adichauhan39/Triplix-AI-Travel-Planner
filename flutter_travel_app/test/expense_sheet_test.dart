import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/expense_columns.dart';
import 'package:flutter_travel_app/services/expense_sheet.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

TripExpense row(String note, int rupees, String by,
        {DateTime? at, bool shared = true, List<String> with_ = const []}) =>
    TripExpense(
      id: '$note$rupees$by',
      by: by,
      byName: by,
      paise: rupees * 100,
      note: note,
      category: 'Food',
      at: at ?? DateTime(2026, 9, 14),
      shared: shared,
      sharedWith: with_,
    );

void main() {
  final regular = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync();

  String nameOf(String uid) =>
      {'a': 'Adi', 'b': 'Bulla', 'c': 'Surendra'}[uid] ?? uid;

  const people = [
    TripPerson(uid: 'a', name: 'Adi', email: ''),
    TripPerson(uid: 'b', name: 'Bulla', email: ''),
    TripPerson(uid: 'c', name: 'Surendra', email: ''),
  ];

  test('a real sheet, written out so it can be read back', () async {
    final approved = [
      row('Dinner at Chokhi Dhani', 1800, 'a', at: DateTime(2026, 9, 13)),
      row('Cab to Amber Fort', 600, 'b', at: DateTime(2026, 9, 14)),
      row('Gifts', 900, 'c', shared: false),
      row('Lassi', 300, 'a', with_: ['a', 'b']),
    ];
    final columns = buildExpenseColumns(
        approved: approved, people: people, me: 'a');
    final debts = settlementFor(
        approved: approved, people: ['a', 'b', 'c']);

    final bytes = await buildExpenseSheet(
      tripName: 'Jaipur',
      approved: approved,
      columns: columns,
      debts: debts,
      nameOf: nameOf,
      regularFont: regular,
      boldFont: bold,
      madeAt: DateTime(2026, 9, 17),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    File('build/expense_sheet_sample.pdf').writeAsBytesSync(bytes);
  });

  test('a long trip runs onto more pages rather than being cut off', () async {
    final approved = [
      for (var i = 0; i < 120; i++)
        row('Expense number $i with a fairly long description', 100 + i,
            ['a', 'b', 'c'][i % 3],
            at: DateTime(2026, 9, 1 + i % 20)),
    ];
    final bytes = await buildExpenseSheet(
      tripName: 'Long trip',
      approved: approved,
      columns: buildExpenseColumns(
          approved: approved, people: people, me: 'a'),
      debts: settlementFor(approved: approved, people: ['a', 'b', 'c']),
      nameOf: nameOf,
      regularFont: regular,
      boldFont: bold,
    );
    File('build/expense_sheet_long.pdf').writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
  });

  test('nothing recorded still makes a sheet', () async {
    final bytes = await buildExpenseSheet(
      tripName: '',
      approved: const [],
      columns: const [],
      debts: const [],
      nameOf: nameOf,
      regularFont: regular,
      boldFont: bold,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
