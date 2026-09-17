/// Where the money went: by kind, by day, and by searching for it.
///
/// Three questions a list of expenses cannot answer at a glance. "How much did
/// food cost us" means adding up rows by eye; "what did day two cost" is
/// something only this app can answer, because it is the only one that knows
/// the itinerary the money was spent on.
///
/// Pure arithmetic over the rows, kept apart from any screen so it can be
/// tested -- and so these figures are never computed twice in two places that
/// then disagree.
library;

import 'trip_sync.dart';

/// Spending on one kind of thing.
class CategorySpend {
  const CategorySpend({
    required this.category,
    required this.paise,
    required this.count,
  });

  final String category;
  final int paise;
  final int count;
}

/// Everything spent, grouped by kind, largest first.
///
/// Every approved row, shared or not. This is "where did the money go", not
/// "who owes whom": somebody's own shopping is still money the trip cost.
List<CategorySpend> spendByCategory(List<TripExpense> approved) {
  final paise = <String, int>{};
  final count = <String, int>{};
  for (final row in approved) {
    if (row.paise <= 0) continue;
    // An empty category is not a category. Filed under Other rather than
    // shown as a nameless slice nobody can read.
    final kind = row.category.trim().isEmpty ? 'Other' : row.category.trim();
    paise[kind] = (paise[kind] ?? 0) + row.paise;
    count[kind] = (count[kind] ?? 0) + 1;
  }
  final out = [
    for (final kind in paise.keys)
      CategorySpend(category: kind, paise: paise[kind]!, count: count[kind]!)
  ];
  // Largest first, then by name so equal amounts do not shuffle between
  // rebuilds -- a chart whose order changes on its own looks broken.
  out.sort((a, b) {
    final bySize = b.paise.compareTo(a.paise);
    return bySize != 0 ? bySize : a.category.compareTo(b.category);
  });
  return out;
}

/// Spending on one calendar day.
class DaySpend {
  const DaySpend({
    required this.date,
    required this.paise,
    required this.count,
    this.dayNumber,
  });

  /// Midnight on the day, local time.
  final DateTime date;
  final int paise;
  final int count;

  /// Which day of the trip this was, 1-based, when it falls inside the trip.
  /// Null for money recorded before it began or after it ended -- a deposit
  /// paid a month early is real spending, but it is not "Day 1".
  final int? dayNumber;
}

DateTime _dayOf(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Everything spent, one entry per day that had any, in date order.
///
/// Grouped by when each expense was *recorded*, which is the only date an
/// expense carries. For a group that logs as they go that is the day it was
/// spent; for somebody entering a whole week of receipts on the train home it
/// is not, and the screen says so rather than presenting a wrong breakdown as
/// exact.
///
/// [tripDates] are the itinerary's days, used only to label each date "Day 2"
/// rather than as a filter: nothing is left out for falling outside them.
List<DaySpend> spendByDay(
  List<TripExpense> approved, {
  List<DateTime> tripDates = const [],
}) {
  final paise = <DateTime, int>{};
  final count = <DateTime, int>{};
  for (final row in approved) {
    if (row.paise <= 0) continue;
    final day = _dayOf(row.at);
    paise[day] = (paise[day] ?? 0) + row.paise;
    count[day] = (count[day] ?? 0) + 1;
  }

  final ordered = [for (final date in tripDates) _dayOf(date)]..sort();

  final out = [
    for (final day in paise.keys)
      DaySpend(
        date: day,
        paise: paise[day]!,
        count: count[day]!,
        dayNumber: ordered.contains(day) ? ordered.indexOf(day) + 1 : null,
      )
  ];
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// The expenses matching what somebody typed, and what they add up to.
class ExpenseSearch {
  const ExpenseSearch({required this.matches, required this.paise});

  final List<TripExpense> matches;
  final int paise;

  bool get isEmpty => matches.isEmpty;
}

/// Finds expenses by what they were for, what kind they are, or who paid.
///
/// A separate result rather than a filter on the columns. Filtering the
/// columns would leave their Paid, Share and Balance figures computed over a
/// handful of rows -- a balance that looks exact and is wrong, on the screen
/// people settle up from.
///
/// Every word has to match somewhere, in any order: "food bulla" finds Bulla's
/// food and nothing else, which is what somebody typing two words means.
ExpenseSearch searchExpenses(
  List<TripExpense> approved,
  String query, {
  String Function(String uid)? nameOf,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const ExpenseSearch(matches: [], paise: 0);

  final matches = <TripExpense>[];
  for (final row in approved) {
    final haystack = [
      row.note,
      row.category,
      row.byName,
      nameOf?.call(row.by) ?? '',
    ].join(' ').toLowerCase();
    if (words.every(haystack.contains)) matches.add(row);
  }

  // Newest first: somebody searching is usually looking for the one they
  // just remembered.
  matches.sort((a, b) => b.at.compareTo(a.at));
  final total = matches.fold<int>(0, (sum, row) => sum + row.paise);
  return ExpenseSearch(matches: matches, paise: total);
}
