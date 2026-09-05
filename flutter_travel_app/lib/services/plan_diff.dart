/// Works out what changed between two versions of a plan.
///
/// A guest's request goes through the same plan adjuster the owner uses, which
/// answers with a whole new set of days rather than with an instruction. The
/// owner can take that answer as-is; a guest cannot, because their edit has to
/// arrive as something the owner approves one piece at a time. This turns
/// "here is the plan afterwards" back into "here is what you are being asked
/// to change".
///
/// Pure, and free of Flutter and Firestore, because the interesting cases are
/// arithmetic on lists -- a place appearing twice, a move that is really a
/// rename, a day that lost everything -- and those are worth checking directly
/// rather than by dragging things around on a screen.
library;

/// One change, as the owner will read it.
class PlanChange {
  const PlanChange({
    required this.kind,
    required this.title,
    required this.dayIndex,
    this.fromDayIndex,
  });

  /// 'add', 'remove' or 'move'.
  final String kind;
  final String title;

  /// Where it ends up. For a removal, where it was.
  final int dayIndex;

  /// Where it came from. Only set for a move.
  final int? fromDayIndex;

  bool get isMove => kind == 'move';

  @override
  bool operator ==(Object other) =>
      other is PlanChange &&
      other.kind == kind &&
      other.title == title &&
      other.dayIndex == dayIndex &&
      other.fromDayIndex == fromDayIndex;

  @override
  int get hashCode => Object.hash(kind, title, dayIndex, fromDayIndex);

  @override
  String toString() => isMove
      ? 'move $title ${fromDayIndex! + 1}->${dayIndex + 1}'
      : '$kind $title @${dayIndex + 1}';
}

/// Compares titles the way a person would.
///
/// Titles arrive with times and notes attached ("09:30 Maitri Baag Zoo") and
/// with inconsistent case and spacing, so a plain == would report a move as a
/// removal plus an unrelated addition.
String _key(String title) {
  var text = title.trim().toLowerCase();
  // A leading clock time, which the scheduler adds and removes freely.
  text = text.replaceFirst(RegExp(r'^\d{1,2}:\d{2}\s*'), '');
  // Anything the plan appends after a dash or bullet is presentation.
  text = text.split(RegExp(r'\s+[-–—·]\s+')).first;
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// What has to happen to turn [before] into [after].
///
/// A title that leaves one day and appears on another is reported once, as a
/// move, rather than as an unrelated removal and addition -- the owner is
/// being asked one question, and splitting it in two lets them accept half and
/// lose the place altogether.
///
/// Duplicates are handled by count rather than by presence: a day that had one
/// coffee stop and now has two yields a single addition, not none.
List<PlanChange> diffPlans(
  List<List<String>> before,
  List<List<String>> after,
) {
  // Every occurrence, keyed for comparison but remembering how it was written
  // so the proposal reads the way the plan does.
  final removed = <String, List<int>>{};
  final added = <String, List<int>>{};
  final display = <String, String>{};

  final days = before.length > after.length ? before.length : after.length;
  for (var day = 0; day < days; day++) {
    final was = day < before.length ? before[day] : const <String>[];
    final now = day < after.length ? after[day] : const <String>[];

    final counts = <String, int>{};
    for (final title in was) {
      final key = _key(title);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => title.trim());
    }
    for (final title in now) {
      final key = _key(title);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) - 1;
      // The new wording wins where both exist: it is what the plan will say.
      display[key] = title.trim();
    }

    counts.forEach((key, delta) {
      for (var i = 0; i < delta; i++) {
        (removed[key] ??= []).add(day);
      }
      for (var i = 0; i < -delta; i++) {
        (added[key] ??= []).add(day);
      }
    });
  }

  final changes = <PlanChange>[];

  // Pair each removal with an addition of the same place: that is a move.
  for (final key in {...removed.keys, ...added.keys}) {
    final from = removed[key] ?? [];
    final to = added[key] ?? [];
    final title = display[key] ?? key;

    final pairs = from.length < to.length ? from.length : to.length;
    for (var i = 0; i < pairs; i++) {
      changes.add(PlanChange(
        kind: 'move',
        title: title,
        dayIndex: to[i],
        fromDayIndex: from[i],
      ));
    }
    for (var i = pairs; i < from.length; i++) {
      changes.add(
          PlanChange(kind: 'remove', title: title, dayIndex: from[i]));
    }
    for (var i = pairs; i < to.length; i++) {
      changes.add(PlanChange(kind: 'add', title: title, dayIndex: to[i]));
    }
  }

  // Stable order, so the same request twice reads the same way: by the day it
  // lands on, then by what is being done, then by name.
  changes.sort((a, b) {
    final byDay = a.dayIndex.compareTo(b.dayIndex);
    if (byDay != 0) return byDay;
    final byKind = a.kind.compareTo(b.kind);
    if (byKind != 0) return byKind;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return changes;
}
