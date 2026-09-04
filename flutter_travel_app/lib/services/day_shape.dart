/// Turns a day's running order into something that can be drawn against a
/// clock.
///
/// The plan already knows the difference between a time it was told and a time
/// it is guessing at -- a confirmed 09:55 departure versus "Afternoon" -- but
/// the day card renders both as identical lines of text. This is what lets the
/// screen show that difference, and lets a three-hour drive occupy three hours
/// of the page rather than one bullet point.
///
/// Pure, and free of Flutter, because it is a parser over free text written by
/// a model: the edge cases are worth testing directly rather than by looking at
/// a screenshot.
library;

/// How certain a moment in the day is.
enum Certainty {
  /// A clock time the plan was given, or worked out from one it was given.
  exact,

  /// A part of the day. "Morning" is an estimate and should not be drawn as
  /// though it were 09:00 sharp.
  approximate,
}

/// One line of a running order, placed on a clock.
class DayMoment {
  const DayMoment({
    required this.minutes,
    required this.certainty,
    required this.text,
  });

  /// Minutes from midnight.
  final int minutes;
  final Certainty certainty;

  /// The line with its time or band prefix removed, so the screen can show the
  /// time in its own right rather than repeating it inside the sentence.
  final String text;

  bool get isExact => certainty == Certainty.exact;

  String get clock {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  String toString() => '$clock ${isExact ? '' : '~'}$text';
}

/// Where each part of the day sits when no clock time is given.
///
/// Nominal, and deliberately spread out: they exist to order the day and give
/// it a shape, not to claim somebody is somewhere at 09:00.
const Map<String, int> _bands = {
  'morning': 9 * 60,
  'around midday': 12 * 60 + 30,
  'midday': 12 * 60 + 30,
  'noon': 12 * 60 + 30,
  'lunch': 13 * 60,
  'afternoon': 15 * 60,
  'evening': 19 * 60,
  'night': 21 * 60,
};

final RegExp _leadingClock = RegExp(r'^\s*(\d{1,2}):([0-5]\d)\s*');
final RegExp _leadingBand = RegExp(
  r'^\s*(around midday|midday|morning|afternoon|evening|night|noon|lunch)\s*:?\s*',
  caseSensitive: false,
);

/// Reads a running order into moments on a clock.
///
/// Lines it cannot place are dropped rather than guessed at: a line with no
/// time and no part of the day has nothing to say about when, and inventing a
/// position for it would be the same fault as inventing the time in the first
/// place.
List<DayMoment> readDayShape(List<String> lines) {
  final moments = <DayMoment>[];

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    final clock = _leadingClock.firstMatch(line);
    if (clock != null) {
      final hour = int.parse(clock.group(1)!);
      final minute = int.parse(clock.group(2)!);
      // A leading "25:00" is not a time. Skip rather than wrap around.
      if (hour > 23) continue;
      moments.add(DayMoment(
        minutes: hour * 60 + minute,
        certainty: Certainty.exact,
        text: line.substring(clock.end).trim(),
      ));
      continue;
    }

    final band = _leadingBand.firstMatch(line);
    if (band != null) {
      final key = band.group(1)!.toLowerCase();
      moments.add(DayMoment(
        minutes: _bands[key]!,
        certainty: Certainty.approximate,
        text: line.substring(band.end).trim(),
      ));
    }
    // Anything else carries no when, so it is not placed on a clock.
  }

  // Stable: exact times first where two land together, so a confirmed
  // departure is never drawn beneath a guess at the same minute.
  moments.sort((a, b) {
    final byTime = a.minutes.compareTo(b.minutes);
    if (byTime != 0) return byTime;
    if (a.isExact == b.isExact) return 0;
    return a.isExact ? -1 : 1;
  });

  // Several lines in one band would otherwise stack on the same pixel. Spread
  // them by a few minutes each so the order stays readable, while the times
  // themselves are still shown as approximate.
  for (var i = 1; i < moments.length; i++) {
    if (moments[i].minutes <= moments[i - 1].minutes &&
        !moments[i].isExact) {
      moments[i] = DayMoment(
        minutes: moments[i - 1].minutes + 20,
        certainty: moments[i].certainty,
        text: moments[i].text,
      );
    }
  }

  return moments;
}

/// The window a day occupies, padded a little at each end.
///
/// Returns null when there is nothing to draw.
({int start, int end})? dayWindow(List<DayMoment> moments) {
  if (moments.isEmpty) return null;
  final first = moments.first.minutes;
  final last = moments.last.minutes;
  // A day with one moment still needs a height, or it draws as a line.
  if (last - first < 120) {
    final middle = (first + last) ~/ 2;
    return (start: middle - 60, end: middle + 60);
  }
  return (start: first - 30, end: last + 30);
}
