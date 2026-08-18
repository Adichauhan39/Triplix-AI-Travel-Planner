import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/models/trip_plan.dart';

void main() {
  TripPlan build(int days, List<String> acts) => TripPlan.fromSelection(
        destination: 'Udaipur',
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 1).add(Duration(days: days - 1)),
        activities: acts,
      );

  test('spreads evenly rather than packing the first day', () {
    final plan = build(3, ['A', 'B', 'C', 'D', 'E', 'F']);
    expect(plan.days.length, 3);
    expect(plan.days.map((d) => d.items.length).toList(), [2, 2, 2]);
  });

  test('keeps every activity the user picked', () {
    final acts = List.generate(11, (i) => 'Act$i');
    final plan = build(3, acts);
    expect(plan.activityCount, 11);
  });

  test('empty days are kept, not dropped', () {
    final plan = build(4, ['A']);
    expect(plan.days.length, 4);
    expect(plan.days.first.items.length, 1);
    expect(plan.days.last.items, isEmpty);
  });

  test('no activities still yields the right number of days', () {
    final plan = build(3, []);
    expect(plan.days.length, 3);
    expect(plan.activityCount, 0);
  });

  test('single day trip', () {
    final plan = build(1, ['A', 'B']);
    expect(plan.days.length, 1);
    expect(plan.activityCount, 2);
  });

  test('dates are consecutive from the start date', () {
    final plan = build(3, ['A']);
    expect(plan.days[0].date, DateTime(2026, 9, 1));
    expect(plan.days[2].date, DateTime(2026, 9, 3));
  });
}
