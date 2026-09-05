import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/plan_diff.dart';

void main() {
  group('diffPlans', () {
    test('an unchanged plan yields nothing', () {
      final days = [
        ['Maitri Baag Zoo', 'Civic Center'],
        ['Supela Market'],
      ];
      expect(diffPlans(days, days), isEmpty);
    });

    test('a place that changes day is one move, not two changes', () {
      final changes = diffPlans([
        ['Maitri Baag Zoo', 'Civic Center'],
        ['Supela Market'],
      ], [
        ['Civic Center'],
        ['Supela Market', 'Maitri Baag Zoo'],
      ]);

      // The whole point: splitting this into a removal and an addition would
      // let the owner accept half and lose the place.
      expect(changes, hasLength(1));
      expect(changes.single.kind, 'move');
      expect(changes.single.title, 'Maitri Baag Zoo');
      expect(changes.single.fromDayIndex, 0);
      expect(changes.single.dayIndex, 1);
    });

    test('an addition on its own is an addition', () {
      final changes = diffPlans([
        ['Civic Center'],
      ], [
        ['Civic Center', 'Supela Market'],
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, 'add');
      expect(changes.single.title, 'Supela Market');
      expect(changes.single.dayIndex, 0);
      expect(changes.single.fromDayIndex, isNull);
    });

    test('a removal on its own is a removal', () {
      final changes = diffPlans([
        ['Civic Center', 'Supela Market'],
      ], [
        ['Civic Center'],
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, 'remove');
      expect(changes.single.title, 'Supela Market');
    });

    test('times and case do not count as changes', () {
      // The scheduler adds and removes clock prefixes freely. Treating those
      // as edits would send the owner a page of changes that change nothing.
      final changes = diffPlans([
        ['Maitri Baag Zoo', 'civic center'],
      ], [
        ['09:30 Maitri Baag Zoo', 'Civic Center'],
      ]);
      expect(changes, isEmpty);
    });

    test('a trailing note is not part of the name', () {
      final changes = diffPlans([
        ['Supela Market'],
      ], [
        ['Supela Market - busy in the evening'],
      ]);
      expect(changes, isEmpty);
    });

    test('duplicates are counted, not merely noticed', () {
      // One coffee stop becoming two is an addition. Comparing by presence
      // alone would report nothing at all.
      final changes = diffPlans([
        ['Coffee', 'Museum'],
      ], [
        ['Coffee', 'Museum', 'Coffee'],
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, 'add');
      expect(changes.single.title, 'Coffee');
    });

    test('two of the same place moving apart gives two moves', () {
      final changes = diffPlans([
        ['Coffee', 'Coffee'],
        [],
      ], [
        [],
        ['Coffee', 'Coffee'],
      ]);
      expect(changes, hasLength(2));
      expect(changes.every((c) => c.isMove), isTrue);
      expect(changes.every((c) => c.fromDayIndex == 0), isTrue);
      expect(changes.every((c) => c.dayIndex == 1), isTrue);
    });

    test('a swap between two days is two moves', () {
      final changes = diffPlans([
        ['A'],
        ['B'],
      ], [
        ['B'],
        ['A'],
      ]);
      expect(changes, hasLength(2));
      expect(changes.every((c) => c.isMove), isTrue);
    });

    test('a new day at the end is handled', () {
      final changes = diffPlans([
        ['A'],
      ], [
        ['A'],
        ['B'],
      ]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, 'add');
      expect(changes.single.dayIndex, 1);
    });

    test('a day losing everything reports each removal', () {
      final changes = diffPlans([
        ['A', 'B'],
      ], [
        <String>[],
      ]);
      expect(changes, hasLength(2));
      expect(changes.every((c) => c.kind == 'remove'), isTrue);
    });

    test('blank entries are ignored', () {
      final changes = diffPlans([
        ['A', '  '],
      ], [
        ['A'],
      ]);
      expect(changes, isEmpty);
    });

    test('the order is stable regardless of input order', () {
      final one = diffPlans([
        ['A', 'B'],
      ], [
        ['C', 'D'],
      ]);
      final two = diffPlans([
        ['B', 'A'],
      ], [
        ['D', 'C'],
      ]);
      expect(one.map((c) => c.toString()), two.map((c) => c.toString()));
    });

    test('the new wording is what the owner is shown', () {
      // Moving a place should offer the plan's own phrasing of it, not the
      // stale one -- the owner is approving what the plan will say.
      final changes = diffPlans([
        ['maitri baag zoo'],
        <String>[],
      ], [
        <String>[],
        ['Maitri Baag Zoo'],
      ]);
      expect(changes.single.title, 'Maitri Baag Zoo');
    });
  });
}
