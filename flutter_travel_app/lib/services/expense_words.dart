/// Tidies up what somebody types against an expense, and files it.
///
/// People add expenses one-handed, on a train, in a hurry: "toxi", "dinnner",
/// "hotal". Those are the same expense as "taxi", "dinner" and "hotel", but
/// they sort apart, group apart and read as carelessness in a list several
/// friends are checking.
///
/// Corrected on the device rather than by asking a model. Every expense is a
/// few words from a small, stable vocabulary, so the arithmetic below settles
/// it instantly, offline, and for nothing -- where a model call would cost a
/// request per expense, take a second, and still have to be checked. The AI is
/// worth its latency for a place name it might genuinely know better; it is
/// not worth it for "toxi".
library;

/// What travel money actually gets spent on, and how each is filed.
///
/// Deliberately small. A wide vocabulary makes the distance check reckless --
/// with enough words, every typo is close to something -- and a word that is
/// not here is simply left as the person wrote it, which is a safe outcome.
const Map<String, String> _vocabulary = {
  // Travel
  'taxi': 'Travel',
  'cab': 'Travel',
  'auto': 'Travel',
  'rickshaw': 'Travel',
  'bus': 'Travel',
  'train': 'Travel',
  'metro': 'Travel',
  'flight': 'Travel',
  'petrol': 'Travel',
  'diesel': 'Travel',
  'fuel': 'Travel',
  'parking': 'Travel',
  'toll': 'Travel',
  // Food
  'breakfast': 'Food',
  'lunch': 'Food',
  'dinner': 'Food',
  'snacks': 'Food',
  'coffee': 'Food',
  'tea': 'Food',
  'water': 'Food',
  'restaurant': 'Food',
  // Stay
  'hotel': 'Stay',
  'hostel': 'Stay',
  'lodge': 'Stay',
  'homestay': 'Stay',
  'resort': 'Stay',
  // Doing things
  'tickets': 'Activities',
  'ticket': 'Activities',
  'entry': 'Activities',
  'guide': 'Activities',
  'museum': 'Activities',
  'temple': 'Activities',
  'boating': 'Activities',
  // Other
  'shopping': 'Shopping',
  'gifts': 'Shopping',
  'souvenirs': 'Shopping',
  'medicine': 'Other',
  'laundry': 'Other',
  'tip': 'Other',
};

/// Levenshtein distance, capped: anything past [limit] is not a near miss and
/// the exact figure does not matter, so the rows stop early.
int _distance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    var best = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = previous[j] + 1;
      if (current[j - 1] + 1 < value) value = current[j - 1] + 1;
      if (previous[j - 1] + cost < value) value = previous[j - 1] + cost;
      current[j] = value;
      if (value < best) best = value;
    }
    if (best > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}

/// How far a word of this length may stray and still be a typo.
///
/// Scaled by length, because one wrong letter in "tea" is a different word
/// while one wrong letter in "restaurant" is a slip. Three letters and under
/// get no tolerance at all: "bus" and "gas" are both real, and guessing
/// between them would rewrite what somebody meant.
///
/// Four is included deliberately, since "toxi" for "taxi" is the commonest
/// mistake there is here. That does mean a real four-letter word one letter
/// from the vocabulary can be offered a correction -- which is why nothing is
/// applied silently: the screen shows the suggestion and the person keeps
/// their own wording if they want it.
int _tolerance(int length) {
  if (length <= 3) return 0;
  if (length <= 7) return 1;
  return 2;
}

/// The corrected word, or null when it was already right or is not close to
/// anything.
String? correctWord(String word) {
  final lower = word.toLowerCase();
  if (lower.isEmpty || _vocabulary.containsKey(lower)) return null;

  final limit = _tolerance(lower.length);
  if (limit == 0) return null;

  String? best;
  var bestDistance = limit + 1;
  var tied = false;

  for (final candidate in _vocabulary.keys) {
    final d = _distance(lower, candidate, limit);
    if (d > limit) continue;
    if (d < bestDistance) {
      bestDistance = d;
      best = candidate;
      tied = false;
    } else if (d == bestDistance) {
      tied = true;
    }
  }

  // Two words equally close is not a correction, it is a guess. Left alone.
  return tied ? null : best;
}

/// A note as it should be filed.
class TidyNote {
  const TidyNote({
    required this.note,
    required this.category,
    required this.corrected,
  });

  final String note;

  /// Best guess at what kind of spending this is, or 'Other'.
  final String category;

  /// Whether any word was changed, so the screen can offer it rather than
  /// applying it silently. Somebody's money should not be relabelled without
  /// them seeing it.
  final bool corrected;
}

/// Corrects the spelling in a note and works out its category.
///
/// Capitalises the first letter, because these end up in a list several people
/// read: "dinner" and "Dinner" as separate-looking rows is the kind of mess
/// that makes a shared ledger feel untrustworthy.
TidyNote tidyNote(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const TidyNote(note: '', category: 'Other', corrected: false);
  }

  var corrected = false;
  final words = trimmed.split(RegExp(r'\s+'));
  final fixed = <String>[];
  String? category;

  for (final word in words) {
    // Punctuation is kept where it sits, so "dinner," stays "Dinner,".
    final match = RegExp(r'^([^\w]*)(.*?)([^\w]*)$').firstMatch(word);
    final head = match?.group(1) ?? '';
    final core = match?.group(2) ?? word;
    final tail = match?.group(3) ?? '';

    final fix = correctWord(core);
    final used = fix ?? core;
    if (fix != null) corrected = true;
    category ??= _vocabulary[used.toLowerCase()];
    fixed.add('$head$used$tail');
  }

  var note = fixed.join(' ');
  note = note[0].toUpperCase() + note.substring(1);

  return TidyNote(
    note: note,
    category: category ?? 'Other',
    corrected: corrected,
  );
}
