/// Checks a day's running order against when the places are actually open.
///
/// The plan already knows both halves and has never compared them: Google's
/// opening hours are fetched and shown on every row, and the scheduler is
/// handed them when it builds a running order -- but nothing verifies what
/// comes back. So a day can say "18:00 Mahant Ghasidas Museum" when the museum
/// shut at 17:00, or send somebody to a place that is closed on Mondays, and
/// the first they know of it is standing outside.
///
/// Pure, and free of Flutter and Firestore, because it is text parsing over
/// two awkward formats and the edge cases -- midnight, split hours, "Open 24
/// hours" -- are worth checking directly rather than by reading a screenshot.
library;

import 'day_shape.dart';

/// A stretch of the day a place is open, in minutes from midnight.
class OpenWindow {
  const OpenWindow(this.from, this.to);

  final int from;

  /// May be less than [from] for a place that closes after midnight.
  final int to;

  /// Whether [minute] falls inside. A window that wraps past midnight is two
  /// stretches of one day, so the test flips rather than the numbers.
  bool contains(int minute) =>
      to >= from ? minute >= from && minute < to : minute >= from || minute < to;

  @override
  String toString() => '${clockLabel(from)}–${clockLabel(to)}';
}

/// What one weekday line says about a place.
class DayHours {
  const DayHours({
    this.unknown = false,
    this.closed = false,
    this.openAllDay = false,
    this.windows = const [],
  });

  /// No data at all. Different from closed, and treated very differently:
  /// silence, rather than a warning we cannot stand behind.
  final bool unknown;

  /// Shut for the whole day.
  final bool closed;
  final bool openAllDay;
  final List<OpenWindow> windows;

  /// Whether the place is open at [minute].
  ///
  /// Unknown hours admit everything. A warning invented from missing data is
  /// worse than no warning: it teaches people to ignore the real ones.
  bool admits(int minute) {
    if (unknown || openAllDay) return true;
    if (closed) return false;
    if (windows.isEmpty) return true;
    return windows.any((w) => w.contains(minute));
  }
}

/// "6:00 PM" for a minute of the day.
String clockLabel(int minutes) {
  final normalised = ((minutes % 1440) + 1440) % 1440;
  final hour24 = normalised ~/ 60;
  final minute = normalised % 60;
  final suffix = hour24 < 12 ? 'AM' : 'PM';
  var hour = hour24 % 12;
  if (hour == 0) hour = 12;
  return '$hour:${minute.toString().padLeft(2, '0')} $suffix';
}

/// Google writes times as "10:00 AM", "6 PM", or "12:00 AM" for midnight.
final RegExp _time = RegExp(
  r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?',
  caseSensitive: false,
);

int? _minutesOf(String text) {
  final match = _time.firstMatch(text.trim());
  if (match == null) return null;
  var hour = int.tryParse(match.group(1) ?? '');
  if (hour == null) return null;
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  final suffix = (match.group(3) ?? '').toLowerCase().replaceAll('.', '');

  if (suffix.startsWith('p') && hour != 12) hour += 12;
  if (suffix.startsWith('a') && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Reads one weekday description, as `_todayHoursFor` returns it.
///
/// That is the part after "Monday: ", so: "10:00 AM – 6:00 PM", "Closed",
/// "Open 24 hours", or two stretches for a place that shuts for the afternoon.
DayHours readHours(String? text) {
  final line = (text ?? '').trim();
  if (line.isEmpty) return const DayHours(unknown: true);

  final lower = line.toLowerCase();
  if (lower.contains('closed')) return const DayHours(closed: true);
  if (lower.contains('24 hours') || lower.contains('open 24')) {
    return const DayHours(openAllDay: true);
  }

  // Google separates the two times with an en dash and the stretches with a
  // comma, and pads them with thin spaces that are not ordinary spaces.
  final windows = <OpenWindow>[];
  for (final part in line.split(',')) {
    final halves = part.split(RegExp(r'\s*[‐-―−–—-]\s*'));
    if (halves.length < 2) continue;
    final from = _minutesOf(halves[0]);
    final to = _minutesOf(halves[1]);
    if (from == null || to == null) continue;
    windows.add(OpenWindow(from, to));
  }

  // Something was written that we could not read. Unknown rather than open:
  // guessing at a format we do not recognise is how a wrong warning happens.
  if (windows.isEmpty) return const DayHours(unknown: true);
  return DayHours(windows: windows);
}

/// A place on the plan at a time it will not be open.
class DayConflict {
  const DayConflict({
    required this.place,
    required this.message,
    required this.certain,
  });

  final String place;

  /// Phrased for the person reading the day, not for a log.
  final String message;

  /// False when the running order only said "Afternoon", so the time itself
  /// is an estimate. Worth saying either way, worth saying differently.
  final bool certain;

  @override
  String toString() => '$place: $message';
}

/// Everything in [runningOrder] that lands when its place is shut.
///
/// [hoursByPlace] maps a place's title to its weekday line for that date --
/// exactly what `_todayHoursFor` already returns, including null for a place
/// whose hours Google does not publish.
///
/// A line is matched to a place by name, so a running order that mentions a
/// place in passing ("walk back past the fort") is checked too. That is the
/// intended behaviour: being outside a closed fort at 9pm is worth knowing
/// whether or not it was meant as a stop.
List<DayConflict> findDayConflicts({
  required List<String> runningOrder,
  required Map<String, String?> hoursByPlace,
}) {
  if (runningOrder.isEmpty || hoursByPlace.isEmpty) return const [];

  final moments = readDayShape(runningOrder);
  if (moments.isEmpty) return const [];

  // Longest names first: a plan containing both "Civic Center" and "Civic
  // Center Bhilai Cg" must match the longer one, or every mention is credited
  // to the shorter.
  final titles = hoursByPlace.keys.where((t) => t.trim().isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  final conflicts = <DayConflict>[];
  final seen = <String>{};

  for (final moment in moments) {
    final text = moment.text.toLowerCase();
    for (final title in titles) {
      if (!text.contains(title.toLowerCase())) continue;

      final hours = readHours(hoursByPlace[title]);
      if (hours.admits(moment.minutes)) break;

      // One warning per place per day. A place visited twice on one closed
      // day is one problem, not two.
      if (!seen.add(title)) break;

      final String message;
      if (hours.closed) {
        message = 'closed all day';
      } else if (hours.windows.isNotEmpty) {
        final window = hours.windows.first;
        final last = hours.windows.last;
        message = moment.minutes < window.from
            ? 'opens at ${clockLabel(window.from)}, '
                'but the plan arrives at ${clockLabel(moment.minutes)}'
            : 'closes at ${clockLabel(last.to)}, '
                'but the plan arrives at ${clockLabel(moment.minutes)}';
      } else {
        message = 'may not be open then';
      }

      conflicts.add(DayConflict(
        place: title,
        message: message,
        certain: moment.isExact,
      ));
      break;
    }
  }

  return conflicts;
}
