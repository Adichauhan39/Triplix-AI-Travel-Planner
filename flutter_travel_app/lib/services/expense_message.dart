/// Reads an expense out of a sentence somebody typed.
///
/// "500 paid by bulla for the horse ride" carries three facts -- an amount, a
/// payer and what it was for -- and the budget chat was reading only the first
/// two thirds of that, dropping the payer entirely and filing everything as
/// the person doing the typing.
///
/// Pure, and free of Flutter and Firestore, because word order is the whole
/// problem here: "bulla paid 500" and "500 paid by bulla" mean the same thing
/// and read nothing alike, and that is worth checking directly.
library;

/// What a sentence turned out to say.
class SpokenExpense {
  const SpokenExpense({
    required this.rupees,
    required this.description,
    this.payer,
    this.shared = true,
  });

  final double rupees;
  final String description;

  /// Who paid, as written. Null when the sentence does not say, which means
  /// the person typing it.
  final String? payer;

  /// Whether the sentence asked for this to be divided.
  ///
  /// False when it says something like "don't share it" or "just mine". The
  /// instruction is acted on and removed from the description, so the note
  /// reads "Food" rather than "Food, but dont share it".
  final bool shared;

  @override
  String toString() =>
      '$rupees for "$description"${payer == null ? '' : ' by $payer'}';
}

/// Words that introduce the payer.
final RegExp _byName = RegExp(
  r'\b(?:paid\s+by|by|from)\s+([a-z][a-z .]{0,30}?)'
  r'(?=\s+(?:for|on|towards)\b|[,.]|$)',
  caseSensitive: false,
);

/// "<name> paid ..." -- the payer stated first.
final RegExp _namePaid = RegExp(
  r'^\s*([a-z][a-z .]{0,30}?)\s+(?:paid|spent)\b',
  caseSensitive: false,
);

/// The amount: rupees, with or without a symbol, commas allowed.
final RegExp _amount = RegExp(
  r'(?:rs\.?|₹|inr)?\s*(\d[\d,]*(?:\.\d{1,2})?)\s*(?:rs\.?|₹|rupees?)?',
  caseSensitive: false,
);

/// What the money was for: whatever follows "for" or "on".
final RegExp _purpose = RegExp(
  r'\b(?:for|on|towards)\s+(.+?)\s*$',
  caseSensitive: false,
);

/// Words that are never somebody's name, so a sentence with no payer is not
/// read as having one.
const Set<String> _notNames = {
  'i', 'we', 'me', 'us', 'my', 'our', 'the', 'a', 'an',
  'cash', 'card', 'upi', 'gpay', 'paytm', 'phonepe', 'online',
  'today', 'yesterday', 'now', 'him', 'her', 'them', 'someone',
};

/// Ways of saying "this one is mine, do not divide it".
///
/// Matched on the sentence with its apostrophes removed, so "don't" and "dont"
/// are one pattern rather than two -- people type both, and a split that
/// depends on punctuation is a split that will be wrong.
final RegExp _notShared = RegExp(
  r"\b("
  r"dont\s+(?:share|split|include)"
  r"|do\s+not\s+(?:share|split|include)"
  r"|not\s+(?:shared|split)"
  r"|no\s+split"
  r"|exclude\s+(?:it\s+)?from"
  r"|just\s+(?:mine|me|for\s+me)"
  r"|only\s+(?:mine|me|for\s+me)"
  r"|my\s+own"
  r"|personal"
  r")\b",
  caseSensitive: false,
);

/// Reads a sentence into an expense, or null if there is no money in it.
///
/// Returning null is the common case and not a failure: most messages in a
/// budget chat are questions, and filing an expense from one would be worse
/// than missing it.
SpokenExpense? readExpense(String message) {
  final text = message.trim();
  if (text.isEmpty) return null;

  // Apostrophes dropped for the test only; the original text is still what
  // the amount and the payer are read from.
  final plain = text.replaceAll("'", '').replaceAll('\u2019', '');
  final shared = !_notShared.hasMatch(plain);

  final amountMatch = _amount.firstMatch(text);
  if (amountMatch == null) return null;
  final rupees = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
  if (rupees == null || rupees <= 0) return null;

  // Payer, if the sentence names one. "<name> paid" is checked first because
  // "bulla paid 500 by card" would otherwise report the card as the payer.
  String? payer;
  final leading = _namePaid.firstMatch(text);
  if (leading != null) {
    payer = leading.group(1)!.trim();
  } else {
    final trailing = _byName.firstMatch(text);
    if (trailing != null) payer = trailing.group(1)!.trim();
  }

  if (payer != null) {
    final cleaned = payer.replaceAll(RegExp(r'[.]+$'), '').trim();
    // A payment method is not a person, and "paid by me" names the typist.
    if (cleaned.isEmpty ||
        _notNames.contains(cleaned.toLowerCase()) ||
        RegExp(r'^\d').hasMatch(cleaned)) {
      payer = null;
    } else {
      payer = cleaned;
    }
  }

  // What it was for.
  var description = '';
  final purpose = _purpose.firstMatch(text);
  if (purpose != null) {
    description = purpose.group(1)!.trim();
    // "for the horse ride" -- the article is not part of the thing.
    description =
        description.replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '');
    // A trailing "by bulla" belongs to the payer, not to the description.
    description = description
        .replaceFirst(RegExp(r'\s+(?:paid\s+)?by\s+.+$', caseSensitive: false), '')
        .trim();
  }
  // The instruction is not part of what was bought. Cut at the connector so
  // "food, but dont share it" becomes "food" rather than "food but".
  if (!shared) {
    final cut = description.split(RegExp(
        r'\s*(?:,|\band\b|\bbut\b|\bhowever\b|--|\u2014)\s*',
        caseSensitive: false));
    for (final piece in cut) {
      final trimmed = piece.trim();
      if (trimmed.isEmpty) continue;
      if (_notShared.hasMatch(
          trimmed.replaceAll("'", '').replaceAll('\u2019', ''))) {
        continue;
      }
      description = trimmed;
      break;
    }
    // Everything in it was the instruction, so nothing names the expense.
    if (_notShared
        .hasMatch(description.replaceAll("'", '').replaceAll('\u2019', ''))) {
      description = '';
    }
  }
  if (description.isEmpty) return null;

  return SpokenExpense(
    rupees: rupees,
    description: description,
    payer: payer,
    shared: shared,
  );
}

/// Matches a spoken name against the people on the trip.
///
/// Deliberately forgiving about case and surrounding spaces, and deliberately
/// unforgiving about everything else: filing money against the wrong person is
/// worse than not filing it, so an ambiguous name matches nobody and the
/// screen can ask.
String? matchPerson(String? spoken, Map<String, String> peopleByUid) {
  if (spoken == null) return null;
  final want = spoken.trim().toLowerCase();
  if (want.isEmpty) return null;

  final exact = <String>[];
  final partial = <String>[];
  peopleByUid.forEach((uid, name) {
    final have = name.trim().toLowerCase();
    if (have.isEmpty) return;
    if (have == want) {
      exact.add(uid);
    } else if (have.split(' ').first == want || have.startsWith('$want ')) {
      partial.add(uid);
    }
  });

  if (exact.length == 1) return exact.first;
  if (exact.isEmpty && partial.length == 1) return partial.first;
  // None, or more than one: not a decision to guess at.
  return null;
}
