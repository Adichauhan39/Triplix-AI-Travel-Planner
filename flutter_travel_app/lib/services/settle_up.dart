/// Works out who owes whom after a shared trip.
///
/// Kept as plain functions with no Firestore and no widgets, because this is
/// the part that must not be wrong: an itinerary that reads oddly is annoying,
/// and a settlement that is off by a rupee is an argument.
library;

/// One payment that settles part of a balance.
class Debt {
  const Debt({required this.from, required this.to, required this.paise});

  /// Who pays.
  final String from;

  /// Who receives.
  final String to;

  /// Always positive.
  final int paise;

  double get rupees => paise / 100;

  @override
  String toString() => '$from -> $to: ${rupees.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      other is Debt &&
      other.from == from &&
      other.to == to &&
      other.paise == paise;

  @override
  int get hashCode => Object.hash(from, to, paise);
}

/// What each person's share of the total works out to.
///
/// Money is handled in paise as whole numbers throughout. Splitting ₹100
/// three ways in floating point gives three shares of 33.333… that do not add
/// back up to 100, and the missing fraction has to land somewhere -- so it
/// lands deliberately here rather than in a rounding error nobody can explain.
Map<String, int> fairShares(int totalPaise, List<String> people) {
  if (people.isEmpty || totalPaise == 0) {
    return {for (final p in people) p: 0};
  }
  final sorted = [...people]..sort();
  final base = totalPaise ~/ sorted.length;
  final remainder = totalPaise.remainder(sorted.length).abs();

  // The odd paise go to the first few people by sorted id. Arbitrary, but
  // deterministic -- the same trip must settle the same way every time it is
  // opened, or the numbers appear to drift.
  return {
    for (var i = 0; i < sorted.length; i++)
      sorted[i]: base + (i < remainder ? (totalPaise.isNegative ? -1 : 1) : 0),
  };
}

/// Who owes whom, given what each person paid.
///
/// [paidPaise] need not include everyone: somebody who paid nothing still owes
/// their share, so [people] is the list that decides who is in the split.
///
/// The result is a short list of payments, not a matrix. Two people who each
/// owe a third should send two payments, not six.
List<Debt> settleUp({
  required Map<String, int> paidPaise,
  required List<String> people,
}) {
  if (people.length < 2) return const [];

  final total = people.fold<int>(0, (sum, p) => sum + (paidPaise[p] ?? 0));
  if (total == 0) return const [];

  final shares = fairShares(total, people);

  // Positive means owed money back; negative means owing.
  final balances = <String, int>{
    for (final p in people) p: (paidPaise[p] ?? 0) - (shares[p] ?? 0),
  };

  // Sorted so the settlement is stable between runs.
  final creditors = [
    for (final e in balances.entries)
      if (e.value > 0) e
  ]..sort((a, b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
    });
  final debtors = [
    for (final e in balances.entries)
      if (e.value < 0) e
  ]..sort((a, b) {
      final byAmount = a.value.compareTo(b.value);
      return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
    });

  // Largest debt against largest credit, repeatedly. Not provably the fewest
  // possible payments -- that problem is NP-hard -- but it settles each person
  // in as few as it reasonably can, and never invents a payment that is not
  // owed.
  final owed = {for (final c in creditors) c.key: c.value};
  final owes = {for (final d in debtors) d.key: -d.value};

  final debts = <Debt>[];
  final creditorNames = [for (final c in creditors) c.key];
  final debtorNames = [for (final d in debtors) d.key];

  var ci = 0;
  var di = 0;
  while (ci < creditorNames.length && di < debtorNames.length) {
    final creditor = creditorNames[ci];
    final debtor = debtorNames[di];
    final amount =
        owed[creditor]! < owes[debtor]! ? owed[creditor]! : owes[debtor]!;

    if (amount > 0) {
      debts.add(Debt(from: debtor, to: creditor, paise: amount));
      owed[creditor] = owed[creditor]! - amount;
      owes[debtor] = owes[debtor]! - amount;
    }
    if (owed[creditor] == 0) ci++;
    if (owes[debtor] == 0) di++;
  }
  return debts;
}

/// Rupees as typed by a person, to whole paise.
///
/// Rounded rather than truncated: "12.345" entered by hand is nearer 12.35
/// than 12.34, and truncation quietly loses money on every entry.
int rupeesToPaise(num rupees) => (rupees * 100).round();
