/// Answers questions about a trip's spending from the ledger itself.
///
/// The budget chat used to send what it knew to a model and print the prose
/// that came back. Two things were wrong with that, and neither was the
/// model's fault.
///
/// It sent the wrong data: the list kept on that one device, not the shared
/// ledger -- so a friend's ₹500 added from their own phone was invisible, and
/// "how much have we spent" was answered from half the money.
///
/// And it let something that cannot read the ledger do the arithmetic about
/// it. A model asked for a total will produce a total, whether or not it can
/// see the rows; it has already told people their money was recorded when it
/// was not.
///
/// So these answers are computed here, from the same functions the screens
/// use. They are instant, cost nothing, work with no signal, and cannot say
/// anything the ledger does not. A question this cannot answer is answered
/// with "I cannot", which is a true sentence and better than a fluent one.
library;

import 'expense_columns.dart';
import 'expense_insights.dart';
import 'expense_words.dart';
import 'trip_sync.dart';

/// What to say back, and whether anything was understood at all.
class ExpenseAnswer {
  const ExpenseAnswer(this.text);

  final String text;
}

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
];

/// Answers [question] about [approved], or returns null when it is not a
/// question about the spending at all.
///
/// Null is the important answer: it means "say you cannot help", not "make
/// something up". Every branch below reads real rows.
ExpenseAnswer? answerAboutExpenses(
  String question, {
  required List<TripExpense> approved,
  required List<TripPerson> people,
  String? me,
  List<DateTime> tripDates = const [],
}) {
  final q = question.toLowerCase().trim();
  if (q.isEmpty) return null;

  bool asks(List<String> words) => words.any(q.contains);

  // Nothing recorded is its own answer, and a better one than zero rupees
  // dressed up as a summary.
  if (approved.isEmpty) {
    if (asks(['how much', 'total', 'spent', 'owe', 'share', 'summary',
              'how many'])) {
      return const ExpenseAnswer(
          'Nothing is recorded yet. Tell me what you paid -- '
          '"500 for the cab" -- and it goes in.');
    }
    return null;
  }

  final uids = [for (final p in people) p.uid];
  String nameOf(String uid) =>
      displayName(uid, me: me, people: people, expenses: approved);

  final total = approved.fold<int>(0, (sum, row) => sum + row.paise);

  // ---------------------------------------------------------- who owes whom
  if (asks(['owe', 'settle', 'square', 'who should pay'])) {
    final debts = settlementFor(approved: approved, people: uids);
    if (debts.isEmpty) {
      return const ExpenseAnswer('Nobody owes anybody -- everyone is square.');
    }
    // "Do I owe" and "who owes me" are about one person, and answering with
    // the whole table makes them find their own line in it.
    final aboutMe = me != null && asks(['i owe', 'do i owe', 'owes me', 'my ']);
    final lines = <String>[];
    for (final debt in debts) {
      if (aboutMe && debt.from != me && debt.to != me) continue;
      lines.add(debt.from == me
          ? 'You owe ${nameOf(debt.to)} ${formatRupees(debt.paise)}'
          : debt.to == me
              ? '${nameOf(debt.from)} owes you ${formatRupees(debt.paise)}'
              : '${nameOf(debt.from)} owes ${nameOf(debt.to)} '
                  '${formatRupees(debt.paise)}');
    }
    if (lines.isEmpty) {
      return const ExpenseAnswer('You are square with everyone.');
    }
    return ExpenseAnswer(lines.join('\n'));
  }

  // ------------------------------------------------------------ one person
  // Checked before the plain total, since "how much did Bulla pay" contains
  // "how much" too.
  for (final person in people) {
    final name = person.name.trim().toLowerCase();
    if (name.isEmpty || name.length < 3) continue;
    if (!q.contains(name)) continue;

    final columns =
        buildExpenseColumns(approved: approved, people: people, me: me);
    final column = columns.where((c) => c.uid == person.uid).firstOrNull;
    if (column == null) continue;

    if (asks(['share', 'owe'])) {
      return ExpenseAnswer(
          "${person.name}'s share is ${formatRupees(column.share)}, "
          'and they paid ${formatRupees(column.paid)}.');
    }
    return ExpenseAnswer(
        '${person.name} paid ${formatRupees(column.paid)} across '
        '${column.expenses.length} '
        '${column.expenses.length == 1 ? 'expense' : 'expenses'}. '
        'Their share is ${formatRupees(column.share)}.');
  }

  // --------------------------------------------------------------- my share
  if (me != null && asks(['my share', 'my total', 'i paid', 'have i paid'])) {
    final columns =
        buildExpenseColumns(approved: approved, people: people, me: me);
    final mine = columns.where((c) => c.uid == me).firstOrNull;
    if (mine != null) {
      return ExpenseAnswer(
          'You paid ${formatRupees(mine.paid)} and your share is '
          '${formatRupees(mine.share)}.');
    }
  }

  // ------------------------------------------------------------ by the day
  final dayNumber = RegExp(r'day\s*(\d{1,2})').firstMatch(q);
  if (dayNumber != null) {
    final wanted = int.parse(dayNumber.group(1)!);
    final days = spendByDay(approved, tripDates: tripDates);
    final day = days.where((d) => d.dayNumber == wanted).firstOrNull;
    if (day == null) {
      return ExpenseAnswer('Nothing is recorded for day $wanted.');
    }
    return ExpenseAnswer('Day $wanted came to ${formatRupees(day.paise)} '
        'across ${day.count} ${day.count == 1 ? 'expense' : 'expenses'}.');
  }

  if (asks(['today', 'yesterday'])) {
    final now = DateTime.now();
    final wanted = q.contains('yesterday')
        ? DateTime(now.year, now.month, now.day - 1)
        : DateTime(now.year, now.month, now.day);
    final days = spendByDay(approved, tripDates: tripDates);
    final day = days.where((d) => d.date == wanted).firstOrNull;
    final word = q.contains('yesterday') ? 'Yesterday' : 'Today';
    if (day == null) return ExpenseAnswer('Nothing is recorded for $word.');
    return ExpenseAnswer('$word came to ${formatRupees(day.paise)} across '
        '${day.count} ${day.count == 1 ? 'expense' : 'expenses'}.');
  }

  // ----------------------------------------------------------- by the kind
  // Matched on the kinds the ledger actually files things under, plus the
  // words people use for them, so "how much on taxis" finds Travel.
  //
  // Only when the sentence is asking about money, though. Naming a kind is
  // not enough: "book me a hotel" contains a kind of spending and is not a
  // question about spending, and answering it with "nothing is recorded under
  // Stay" is a confident reply to something nobody asked.
  final aboutMoney = asks(
      ['how much', 'how many', 'total', 'spent', 'spend', 'cost', 'costs',
       'paid', 'expense', 'summary', 'so far', 'altogether']);
  final kinds = aboutMoney ? spendByCategory(approved) : <CategorySpend>[];
  for (final kind in kinds) {
    if (q.contains(kind.category.toLowerCase())) {
      return ExpenseAnswer('${kind.category} came to '
          '${formatRupees(kind.paise)} across ${kind.count} '
          '${kind.count == 1 ? 'expense' : 'expenses'}, '
          '${(kind.paise * 100 / total).round()}% of everything.');
    }
  }
  final spokenKind = aboutMoney ? categoryOfWord(q) : null;
  if (spokenKind != null) {
    final kind = kinds.where((k) => k.category == spokenKind).firstOrNull;
    if (kind != null) {
      return ExpenseAnswer('$spokenKind came to ${formatRupees(kind.paise)} '
          'across ${kind.count} '
          '${kind.count == 1 ? 'expense' : 'expenses'}.');
    }
    return ExpenseAnswer('Nothing is recorded under $spokenKind yet.');
  }

  // ------------------------------------------------------------- a listing
  if (asks(['show me', 'list', 'which expenses', 'what did we buy'])) {
    final found = searchExpenses(approved, q, nameOf: nameOf);
    if (!found.isEmpty) {
      final lines = [
        for (final row in found.matches.take(8))
          '${row.note.isEmpty ? row.category : row.note} -- '
              '${formatRupees(row.paise)} (${nameOf(row.by)})'
      ];
      return ExpenseAnswer('${found.matches.length} '
          '${found.matches.length == 1 ? 'expense' : 'expenses'}, '
          '${formatRupees(found.paise)} in all:\n${lines.join('\n')}');
    }
  }

  // --------------------------------------------------------- how many, how much
  if (asks(['how many'])) {
    return ExpenseAnswer('${approved.length} '
        '${approved.length == 1 ? 'expense' : 'expenses'} so far, '
        '${formatRupees(total)} in all.');
  }

  if (asks(['how much', 'total', 'spent', 'altogether', 'summary',
            'so far'])) {
    final biggest = kinds.isEmpty ? null : kinds.first;
    final shared = sharedTotal(approved);
    return ExpenseAnswer(
      '${formatRupees(total)} in all, across ${approved.length} '
      '${approved.length == 1 ? 'expense' : 'expenses'}.'
      '${shared != total ? '\n${formatRupees(shared)} of that is shared; '
          'the rest is personal.' : ''}'
      '${biggest != null ? '\nMost of it went on ${biggest.category} '
          '(${formatRupees(biggest.paise)}).' : ''}',
    );
  }

  // Not a question about the money. The caller says so plainly rather than
  // inventing an answer.
  return null;
}
