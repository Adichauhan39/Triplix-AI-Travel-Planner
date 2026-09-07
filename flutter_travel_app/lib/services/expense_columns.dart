/// Groups a trip's spending into one column per person.
///
/// A flat list of expenses answers "what was bought"; a group settling a bill
/// is asking "what did each of us put in", and was having to scan the whole
/// list and add up in their head. This turns the rows into columns without
/// changing any of the arithmetic underneath -- the split still comes from
/// [fairShares], so the columns and the settlement can never disagree.
///
/// Pure, and tested directly, because the interesting cases are about money
/// going missing rather than about layout.
library;

import 'settle_up.dart';
import 'trip_sync.dart';

/// One person's column: what they paid for, and where that leaves them.
class PersonColumn {
  const PersonColumn({
    required this.uid,
    required this.name,
    required this.expenses,
    required this.paid,
    required this.share,
    required this.inSplit,
  });

  final String uid;

  /// What to show above the column. 'You' for the person reading it.
  final String name;

  /// This person's expenses, newest first.
  final List<TripExpense> expenses;

  /// What they put in, in paise.
  final int paid;

  /// What they owe of the total. Zero when they are not in the split.
  final int share;

  /// Whether they are a member of the trip.
  ///
  /// False means somebody who paid for something and has since been removed
  /// from the trip. Their money is still in the ledger, so their column is
  /// still shown -- but no balance is claimed for them, because the settlement
  /// divides between members and will never pay them back.
  final bool inSplit;

  /// What they are up or down by. Positive means the group owes them.
  int get balance => paid - share;

  @override
  String toString() => '$name paid $paid of $share';
}

/// The name to show for a uid.
///
/// Falls through the trip nickname, then the name copied onto an expense when
/// it was written, then a shortened uid. Never an invented placeholder: two
/// unnamed people both reading "Someone" cannot be told apart, and this is a
/// screen about who owes what.
String displayName(
  String uid, {
  String? me,
  List<TripPerson> people = const [],
  List<TripExpense> expenses = const [],
}) {
  if (uid == me) return 'You';
  for (final person in people) {
    if (person.uid == uid && person.name.isNotEmpty) return person.name;
  }
  for (final expense in expenses) {
    if (expense.by == uid && expense.byName.isNotEmpty) return expense.byName;
  }
  return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
}

/// Money the way people write it: whole where it is whole, grouped the Indian
/// way, so 1,40,000 rather than 140,000.
///
/// Takes the absolute value -- a minus sign in front of a balance is the
/// caller's to add, along with the plus.
String formatRupees(int paise) {
  final value = paise.abs() / 100;
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2);
  final parts = text.split('.');
  var whole = parts[0];
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    whole = '${groups.join(',')},$last3';
  }
  return '₹$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// Builds the columns.
///
/// [approved] should be the rows that count -- pending and rejected ones are
/// not money anybody owes yet.
///
/// A column is made for every member **and** for anybody who paid, even if
/// they are no longer on the trip. Building from the member list alone would
/// drop their expenses from the screen while the headline total still counted
/// them, so the columns would quietly fail to add up. Somebody being removed
/// is exactly when their money most needs to stay visible.
List<PersonColumn> buildExpenseColumns({
  required List<TripExpense> approved,
  required List<TripPerson> people,
  String? me,
}) {
  final memberUids = <String>[
    for (final person in people)
      if (person.uid.isNotEmpty) person.uid,
  ];

  final paid = <String, int>{};
  final byPerson = <String, List<TripExpense>>{};
  for (final row in approved) {
    if (row.by.isEmpty) continue;
    paid[row.by] = (paid[row.by] ?? 0) + row.paise;
    (byPerson[row.by] ??= []).add(row);
  }

  // Members first so the order below is stable, then anybody else who paid.
  final uids = <String>[
    ...memberUids,
    for (final uid in byPerson.keys)
      if (!memberUids.contains(uid)) uid,
  ];
  if (uids.isEmpty) return const [];

  // The split is whatever settle_up says it is. Deriving it again here would
  // let the columns and the settlement drift apart, which is the one thing a
  // shared ledger cannot survive.
  final total = approved.fold<int>(0, (sum, row) => sum + row.paise);
  final shares = memberUids.isEmpty
      ? <String, int>{}
      : fairShares(total, memberUids);

  final columns = [
    for (final uid in uids)
      PersonColumn(
        uid: uid,
        name: displayName(uid, me: me, people: people, expenses: approved),
        expenses: byPerson[uid] ?? const [],
        paid: paid[uid] ?? 0,
        share: shares[uid] ?? 0,
        inSplit: memberUids.contains(uid),
      ),
  ];

  // You first -- you are looking for yourself before anybody else -- then by
  // what people put in, then by name so the order never wobbles between builds.
  columns.sort((a, b) {
    if (a.uid == me && b.uid != me) return -1;
    if (b.uid == me && a.uid != me) return 1;
    final byPaid = b.paid.compareTo(a.paid);
    if (byPaid != 0) return byPaid;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return columns;
}
