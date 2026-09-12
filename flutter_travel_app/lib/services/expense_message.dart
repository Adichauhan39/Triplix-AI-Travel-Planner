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
/// What the money was for: whatever follows the LAST "for", "on" or
/// "towards".
///
/// It used to take the first, so "put 700 on aditya for the cab" read the
/// purpose as "aditya for the cab" -- the person became part of what was
/// bought. Everything before the last one is context; the tail is the thing.
final RegExp _purpose = RegExp(
  r'^.*\b(?:for|on|towards)\s+(.+?)\s*$',
  caseSensitive: false,
  dotAll: true,
);

/// Sentences that carry a number and are not an expense.
///
/// "my budget is 20000" has an amount and no purpose, which -- once an amount
/// without a purpose became a question -- got answered with "what was the
/// 20,000 for?". Setting a budget is a different act, handled elsewhere, and
/// the reader has to know to keep out of it.
final RegExp _notAnExpense = RegExp(
  r'\b('
  r'budget\s+(?:is|of|:)'
  r'|my\s+budget'
  r'|total\s+budget'
  r'|set\s+(?:a\s+|the\s+)?budget'
  r'|budget\s+for\s+the\s+trip'
  r'|per\s+person\s+budget'
  r'|we\s+are\s+\d+\s+people'
  r'|group\s+of\s+\d+'
  r')',
  caseSensitive: false,
);

/// Verbs and fillers that start a sentence and are not a person.
///
/// "surendra 500 for food" names its payer first with no verb at all, which is
/// worth reading -- but "add 500 for food" has the same shape, and Add is not
/// a person.
const Set<String> _notLeadingNames = {
  'add', 'put', 'paid', 'pay', 'spent', 'spend', 'log', 'logged', 'record',
  'note', 'enter', 'i', 'we', 'my', 'our', 'total', 'budget', 'set', 'the',
  'a', 'an', 'and', 'also', 'please', 'just', 'exclude', 'remove', 'make',
  'dont', 'do', 'not', 'rs', 'inr',
};

/// "<name> 500 for food" -- the payer first, with no verb between.
final RegExp _bareName = RegExp(
  r"^\s*([a-z][a-z]{1,20})\s+(?:rs\.?|₹|inr)?\s*\d",
  caseSensitive: false,
);

/// "put 700 on aditya for the cab" -- the person after "on".
final RegExp _onName = RegExp(
  r"\bon\s+([a-z][a-z .]{0,30}?)\s+(?:for|towards)\b",
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

/// "in surendra account", "to surendra", "surendra's account".
///
/// A separate pattern from `by`/`from`, because this is how people actually
/// say it when they are putting money against somebody rather than reporting
/// who paid: "add 500 to bulla", "5000 in surendra account".
final RegExp _accountOf = RegExp(
  r"\b(?:in|into|to|for)\s+([a-z][a-z .]{0,30}?)(?:'?s)?"
  r"\s*(?:account|name|share)\b",
  caseSensitive: false,
);

/// "add 500 to bulla" -- no account word, so it has to end there or run into
/// the purpose.
final RegExp _toName = RegExp(
  r"^\s*add\b[^a-z]*(?:rs\.?|₹|inr)?\s*[\d,.]+\s*(?:rs\.?|₹|rupees?)?\s*"
  r"(?:in|into|to)\s+([a-z][a-z .]{0,30}?)"
  r"(?=\s+(?:for|on|towards)\b|[,.]|$)",
  caseSensitive: false,
);

/// What a sentence says about money, including when it does not say enough.
///
/// [readExpense] answers null for an incomplete sentence, which is right for
/// filing but useless for talking: somebody who types "add 5000 to surendra
/// account" has said three quarters of an expense and should be asked for the
/// rest, not ignored while a model invents a reply.
class ExpenseDraft {
  const ExpenseDraft({
    this.rupees,
    this.payer,
    this.description = '',
    this.shared = true,
  });

  final double? rupees;
  final String? payer;

  /// What the money was for. Empty when the sentence never said.
  final String description;
  final bool shared;

  bool get hasAmount => rupees != null && rupees! > 0;

  /// Enough to file.
  bool get complete => hasAmount && description.isNotEmpty;

  /// An amount and nothing to call it: worth one question.
  bool get needsPurpose => hasAmount && description.isEmpty;
}

/// Reads a sentence into an expense, or null if there is no money in it.
///
/// Returning null is the common case and not a failure: most messages in a
/// budget chat are questions, and filing an expense from one would be worse
/// than missing it.
SpokenExpense? readExpense(String message) {
  final draft = readExpenseDraft(message);
  if (!draft.complete) return null;
  return SpokenExpense(
    rupees: draft.rupees!,
    description: draft.description,
    payer: draft.payer,
    shared: draft.shared,
  );
}

/// Everything the sentence gave up, complete or not.
ExpenseDraft readExpenseDraft(String message) {
  final text = message.trim();
  if (text.isEmpty) return const ExpenseDraft();

  // Apostrophes dropped for the test only; the original text is still what
  // the amount and the payer are read from.
  final plain = text.replaceAll("'", '').replaceAll('\u2019', '');
  final shared = !_notShared.hasMatch(plain);

  // Somebody setting a budget or saying how many they are. Both carry a
  // number and neither is money that was spent.
  if (_notAnExpense.hasMatch(plain)) return const ExpenseDraft();

  final amountMatch = _amount.firstMatch(text);
  if (amountMatch == null) return const ExpenseDraft();
  final rupees = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
  if (rupees == null || rupees <= 0) return const ExpenseDraft();

  // Payer, if the sentence names one. "<name> paid" is checked first because
  // "bulla paid 500 by card" would otherwise report the card as the payer.
  String? payer;
  final leading = _namePaid.firstMatch(text);
  final account = _accountOf.firstMatch(text);
  final toward = _toName.firstMatch(text);
  final onWho = _onName.firstMatch(text);
  final bare = _bareName.firstMatch(text);
  if (leading != null) {
    payer = leading.group(1)!.trim();
  } else if (onWho != null) {
    // "put 700 on aditya for the cab".
    payer = onWho.group(1)!.trim();
  } else if (account != null) {
    // "5000 in surendra account" -- checked before `by`, since "for" appears
    // in both this pattern and the purpose one.
    payer = account.group(1)!.trim();
  } else if (toward != null) {
    payer = toward.group(1)!.trim();
  } else {
    final trailing = _byName.firstMatch(text);
    if (trailing != null) {
      payer = trailing.group(1)!.trim();
    } else if (bare != null &&
        !_notLeadingNames.contains(bare.group(1)!.toLowerCase())) {
      // "surendra 500 for food" -- a name, then the amount, no verb.
      payer = bare.group(1)!.trim();
    }
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
    // Nor does "surendra account": "for" introduces the purpose and also the
    // person, and the person is not what the money was spent on.
    if (RegExp(r'^[a-z][a-z .]{0,30}?(?:\u0027?s)?\s*(?:account|name|share)$',
            caseSensitive: false)
        .hasMatch(description)) {
      description = '';
    }
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
  return ExpenseDraft(
    rupees: rupees,
    payer: payer,
    description: description,
    shared: shared,
  );
}

/// Asking for an expense to leave the split, or to come back into it.
///
/// Returns false for "take it out", true for "put it back", and null when the
/// sentence is not about that at all.
///
/// Which expense is left to the caller, because only the caller has the
/// ledger: the notes on the rows are what a sentence can name, and matching
/// against them beats trying to parse a noun out of "exclude that from share".
bool? readSplitChange(String message) {
  final plain =
      message.trim().replaceAll("'", '').replaceAll('\u2019', '').toLowerCase();
  if (plain.isEmpty) return null;

  // Back in first: "share it again" contains "share it", and so does
  // "dont share it".
  final backIn = RegExp(
    r'\b(?:'
    r'include\s+(?:it|this|that|the)?[a-z ]*\s*(?:in|into)\s+(?:the\s+)?(?:split|share)'
    r'|add\s+(?:it|this|that)\s+back'
    r'|put\s+(?:it|this|that)\s+back'
    r'|back\s+in\s+(?:the\s+)?(?:split|share)'
    r'|make\s+(?:it|this|that)\s+shared'
    r'|share\s+(?:it|this|that)\s+again'
    r'|do\s+share'
    r')',
  );
  if (backIn.hasMatch(plain)) return true;

  final takeOut = RegExp(
    r'\b(?:'
    r'exclude'
    r'|dont\s+share|do\s+not\s+share'
    r'|(?:remove|take|drop|keep)\s+[a-z0-9 ]{0,24}?\s*(?:out\s+)?'
    r'(?:from|of)\s+(?:the\s+)?(?:split|share|sharing)'
    r'|not\s+(?:shared|split)'
    r'|make\s+[a-z0-9 ]{0,24}?\s*personal'
    r'|mark\s+[a-z0-9 ]{0,24}?\s*personal'
    r'|just\s+mine|only\s+mine'
    r')',
  );
  if (takeOut.hasMatch(plain)) return false;

  return null;
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
