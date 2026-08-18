/// A day-by-day plan built from the activities the user actually chose.
///
/// Deliberately not generated from scratch: the plan starts as the user's own
/// picks spread across their dates, so nothing appears in it that they didn't
/// ask for. Anything the assistant adds later, in response to a typed request,
/// is marked [addedByAssistant] so the two can be told apart on screen — the
/// same distinction the booking confirmations draw between a verified place
/// and one the user typed.
library;

class PlanItem {
  const PlanItem({
    required this.title,
    this.addedByAssistant = false,
  });

  final String title;

  /// True when this came from a typed request rather than the user's original
  /// selection. Shown differently, because we haven't checked it exists.
  final bool addedByAssistant;

  Map<String, dynamic> toJson() => {
        'title': title,
        'added_by_assistant': addedByAssistant,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        title: (json['title'] ?? '').toString(),
        addedByAssistant: json['added_by_assistant'] == true,
      );
}

class PlanDay {
  const PlanDay({required this.date, required this.items});

  final DateTime date;
  final List<PlanItem> items;

  PlanDay copyWith({List<PlanItem>? items}) =>
      PlanDay(date: date, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String().split('T').first,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory PlanDay.fromJson(Map<String, dynamic> json) => PlanDay(
        date: DateTime.tryParse((json['date'] ?? '').toString()) ??
            DateTime.now(),
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanItem.fromJson)
            .toList(),
      );
}

class TripPlan {
  const TripPlan({required this.destination, required this.days});

  final String destination;
  final List<PlanDay> days;

  bool get isEmpty => days.isEmpty;

  int get activityCount =>
      days.fold(0, (total, day) => total + day.items.length);

  /// Spreads [activities] across the trip's dates, in order, filling each day
  /// up to [perDay] before moving on.
  ///
  /// Rules rather than a model call: the input is a handful of names and a
  /// date range, so there is nothing to reason about, and a generated plan
  /// would risk inventing activities the user never chose. It is also
  /// instant and free, which matters on a screen the user opens repeatedly.
  ///
  /// Days beyond the chosen activities are kept as empty days rather than
  /// dropped — an empty Day 3 is a true statement about the trip, and hiding
  /// it would misrepresent how long they are staying.
  factory TripPlan.fromSelection({
    required String destination,
    required DateTime start,
    required DateTime end,
    required List<String> activities,
    int perDay = 3,
  }) {
    final dayCount = end.difference(start).inDays + 1;
    if (dayCount <= 0) {
      return TripPlan(destination: destination, days: const []);
    }

    // Spread evenly rather than packing the front: three activities on day one
    // and none on day three reads as a worse trip than two, two, two.
    final spread = activities.isEmpty
        ? perDay
        : (activities.length / dayCount).ceil().clamp(1, perDay);

    final days = <PlanDay>[];
    var index = 0;
    for (var i = 0; i < dayCount; i++) {
      final items = <PlanItem>[];
      while (items.length < spread && index < activities.length) {
        items.add(PlanItem(title: activities[index]));
        index++;
      }
      days.add(PlanDay(date: start.add(Duration(days: i)), items: items));
    }

    // Anything left over — more activities than days x spread — goes on the
    // last day rather than being silently dropped.
    if (index < activities.length && days.isNotEmpty) {
      final last = days.removeLast();
      days.add(last.copyWith(items: [
        ...last.items,
        for (; index < activities.length; index++)
          PlanItem(title: activities[index]),
      ]));
    }

    return TripPlan(destination: destination, days: days);
  }

  List<Map<String, dynamic>> toJson() =>
      days.map((d) => d.toJson()).toList();
}
