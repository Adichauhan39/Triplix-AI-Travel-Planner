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
/// Money one traveller has actually handed to another.
///
/// Not an expense: nothing was bought, and it must not appear in what the
/// group spent. It exists so a debt can be closed -- without it the
/// settlement says "Surendra owes you 433" for ever, however many times he
/// has paid.
class Repayment {
  const Repayment({
    required this.from,
    required this.to,
    required this.paise,
  });

  final String from;
  final String to;
  final int paise;
}

/// Folds repayments into what each person has put in.
///
/// In the arithmetic a repayment behaves exactly like an expense paid by the
/// payer on the receiver's behalf: paying back 500 leaves the payer 500 less
/// short and the receiver 500 less owed. So one contribution goes up and the
/// other comes down by the same amount -- the group total is untouched, which
/// is what keeps the shares and the headline figure honest -- and the
/// settlement comes out at nothing once everybody has paid.
Map<String, int> withRepayments({
  required Map<String, int> paidPaise,
  required List<Repayment> repayments,
}) {
  final out = {...paidPaise};
  for (final paid in repayments) {
    if (paid.paise <= 0 || paid.from == paid.to) continue;
    out[paid.from] = (out[paid.from] ?? 0) + paid.paise;
    out[paid.to] = (out[paid.to] ?? 0) - paid.paise;
  }
  return out;
}

List<Debt> settleUp({
  required Map<String, int> paidPaise,
  required List<String> people,
  Map<String, int>? owedPaise,
}) {
  if (people.length < 2) return const [];

  final total = people.fold<int>(0, (sum, p) => sum + (paidPaise[p] ?? 0));
  // No early return on a total of zero any more.
  //
  // It used to mean "nothing was spent, so nobody owes anything", which was
  // true while the only inputs were expenses. Once a repayment can make one
  // person's contribution negative, a total of zero no longer implies
  // balances of zero -- a group that spent nothing and then paid each other
  // has real balances. The balances below are already the answer, so they
  // decide, and an empty ledger falls out of them as an empty list anyway.

  // What each person owes. Given explicitly when expenses are split between
  // different subsets of the group -- a dinner three of five went to is not
  // divided by five -- and otherwise the whole total shared equally, which is
  // what it has always been.
  final shares = owedPaise ?? fairShares(total, people);

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
