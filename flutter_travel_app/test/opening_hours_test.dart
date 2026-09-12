import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/opening_hours.dart';

void main() {
  group('readHours', () {
    test('reads an ordinary day', () {
      final hours = readHours('10:00 AM – 6:00 PM');
      expect(hours.windows, hasLength(1));
      expect(hours.admits(10 * 60), isTrue);
      expect(hours.admits(17 * 60 + 59), isTrue);
      expect(hours.admits(18 * 60), isFalse);
      expect(hours.admits(9 * 60 + 59), isFalse);
    });

    test('a plain hyphen works too', () {
      expect(readHours('10:00 AM - 6:00 PM').admits(11 * 60), isTrue);
    });

    test('reads hours without minutes', () {
      expect(readHours('9 AM – 5 PM').admits(16 * 60), isTrue);
      expect(readHours('9 AM – 5 PM').admits(17 * 60), isFalse);
    });

    test('closed means closed', () {
      final hours = readHours('Closed');
      expect(hours.closed, isTrue);
      expect(hours.admits(12 * 60), isFalse);
    });

    test('open all day admits everything', () {
      expect(readHours('Open 24 hours').admits(3 * 60), isTrue);
    });

    test('two stretches, shut in between', () {
      // A temple that closes for the afternoon.
      final hours = readHours('6:00 AM – 12:00 PM, 4:00 PM – 9:00 PM');
      expect(hours.windows, hasLength(2));
      expect(hours.admits(8 * 60), isTrue);
      expect(hours.admits(14 * 60), isFalse);
      expect(hours.admits(18 * 60), isTrue);
    });

    test('a place that shuts after midnight', () {
      final hours = readHours('6:00 PM – 2:00 AM');
      expect(hours.admits(23 * 60), isTrue);
      expect(hours.admits(1 * 60), isTrue);
      expect(hours.admits(15 * 60), isFalse);
    });

    test('midday and midnight are not confused', () {
      expect(readHours('12:00 AM – 11:59 PM').admits(0), isTrue);
      final noon = readHours('12:00 PM – 5:00 PM');
      expect(noon.admits(12 * 60), isTrue);
      expect(noon.admits(11 * 60), isFalse);
    });

    test('nothing known admits everything', () {
      // Silence beats a warning invented from missing data.
      expect(readHours(null).unknown, isTrue);
      expect(readHours(null).admits(3 * 60), isTrue);
      expect(readHours('').admits(3 * 60), isTrue);
    });

    test('an unreadable line is unknown, not open', () {
      final hours = readHours('Hours vary by season');
      expect(hours.unknown, isTrue);
    });
  });

  group('findDayConflicts', () {
    test('catches a visit after closing', () {
      final conflicts = findDayConflicts(
        runningOrder: ['18:30 Mahant Ghasidas Museum'],
        hoursByPlace: {'Mahant Ghasidas Museum': '10:00 AM – 5:00 PM'},
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.place, 'Mahant Ghasidas Museum');
      expect(conflicts.single.message, contains('closes at 5:00 PM'));
      expect(conflicts.single.certain, isTrue);
    });

    test('catches a visit before opening', () {
      final conflicts = findDayConflicts(
        runningOrder: ['08:00 Maitri Baag Zoo'],
        hoursByPlace: {'Maitri Baag Zoo': '10:00 AM – 6:00 PM'},
      );
      expect(conflicts.single.message, contains('opens at 10:00 AM'));
    });

    test('catches a day the place is shut', () {
      final conflicts = findDayConflicts(
        runningOrder: ['11:00 M.P. Urja Vikas Nigam Limited'],
        hoursByPlace: {'M.P. Urja Vikas Nigam Limited': 'Closed'},
      );
      expect(conflicts.single.message, 'closed all day');
    });

    test('says nothing when the visit fits', () {
      expect(
        findDayConflicts(
          runningOrder: ['11:00 Maitri Baag Zoo'],
          hoursByPlace: {'Maitri Baag Zoo': '10:00 AM – 6:00 PM'},
        ),
        isEmpty,
      );
    });

    test('says nothing when the hours are unknown', () {
      expect(
        findDayConflicts(
          runningOrder: ['23:00 Somewhere'],
          hoursByPlace: {'Somewhere': null},
        ),
        isEmpty,
      );
    });

    test('an estimated time is flagged, but marked uncertain', () {
      // "Evening" is the scheduler's guess, not a time anybody was told.
      final conflicts = findDayConflicts(
        runningOrder: ['Evening Mahant Ghasidas Museum'],
        hoursByPlace: {'Mahant Ghasidas Museum': '10:00 AM – 5:00 PM'},
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.certain, isFalse);
    });

    test('the longer name wins', () {
      // Both are in the plan; the mention belongs to the longer one.
      final conflicts = findDayConflicts(
        runningOrder: ['19:00 Civic Center Bhilai Cg'],
        hoursByPlace: {
          'Civic Center': 'Open 24 hours',
          'Civic Center Bhilai Cg': '10:00 AM – 6:00 PM',
        },
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.place, 'Civic Center Bhilai Cg');
    });

    test('one warning per place, however often it appears', () {
      final conflicts = findDayConflicts(
        runningOrder: ['08:00 Maitri Baag Zoo', '09:00 Maitri Baag Zoo'],
        hoursByPlace: {'Maitri Baag Zoo': '10:00 AM – 6:00 PM'},
      );
      expect(conflicts, hasLength(1));
    });

    test('a line with no time is not checked', () {
      // Nothing was said about when, so nothing can be said about whether.
      expect(
        findDayConflicts(
          runningOrder: ['Visit Maitri Baag Zoo'],
          hoursByPlace: {'Maitri Baag Zoo': 'Closed'},
        ),
        isEmpty,
      );
    });

    test('an empty plan is quiet', () {
      expect(
        findDayConflicts(runningOrder: const [], hoursByPlace: const {}),
        isEmpty,
      );
    });
  });

  group('clockLabel', () {
    test('reads as a person would write it', () {
      expect(clockLabel(0), '12:00 AM');
      expect(clockLabel(9 * 60 + 5), '9:05 AM');
      expect(clockLabel(12 * 60), '12:00 PM');
      expect(clockLabel(17 * 60 + 30), '5:30 PM');
    });
  });
}
