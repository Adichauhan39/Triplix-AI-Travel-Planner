import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/trip_sync.dart';

/// A trip document as Firestore hands it back.
Map<String, dynamic> trip({
  List<String> members = const ['owner-uid'],
  List<String> requests = const [],
  List<String>? money,
  List<String> moneyRequests = const [],
}) =>
    {
      'owner': 'owner-uid',
      'members': members,
      'requests': requests,
      if (money != null) 'money': money,
      'money_requests': moneyRequests,
    };

void main() {
  group('the two grants are separate', () {
    test('approved for the plan does not open the ledger', () {
      final data = trip(members: ['owner-uid', 'priya'], money: ['owner-uid']);
      expect(TripSync.accessOf(data, 'priya'), TripAccess.editor);
      expect(TripSync.accessOf(data, 'priya', scope: TripScope.money),
          TripAccess.viewer);
    });

    test('approved for the ledger does not open the plan', () {
      final data = trip(money: ['owner-uid', 'surendra']);
      expect(TripSync.accessOf(data, 'surendra', scope: TripScope.money),
          TripAccess.editor);
      expect(TripSync.accessOf(data, 'surendra'), TripAccess.viewer);
    });

    test('the owner has both, with nobody to ask', () {
      final data = trip(money: const []);
      expect(TripSync.accessOf(data, 'owner-uid'), TripAccess.owner);
      expect(TripSync.accessOf(data, 'owner-uid', scope: TripScope.money),
          TripAccess.owner);
    });

    test('waiting in one queue is not waiting in the other', () {
      final data = trip(moneyRequests: ['surendra']);
      expect(TripSync.accessOf(data, 'surendra', scope: TripScope.money),
          TripAccess.pending);
      expect(TripSync.accessOf(data, 'surendra'), TripAccess.viewer);
    });

    test('asking for the plan is not asking for the money', () {
      final data = trip(requests: ['priya']);
      expect(TripSync.accessOf(data, 'priya'), TripAccess.pending);
      expect(TripSync.accessOf(data, 'priya', scope: TripScope.money),
          TripAccess.viewer);
    });

    test('signed out has neither', () {
      expect(TripSync.accessOf(trip(), null), TripAccess.signedOut);
      expect(TripSync.accessOf(trip(), null, scope: TripScope.money),
          TripAccess.signedOut);
    });
  });

  group('trips that existed before the ledger had its own list', () {
    // The regression that would hurt most: a friend who can add spending
    // today must not lose it because the field was renamed under them.
    test('members keep the money access they already had', () {
      final old = {
        'owner': 'owner-uid',
        'members': ['owner-uid', 'priya'],
        'requests': <String>[],
      };
      expect(TripSync.accessOf(old, 'priya', scope: TripScope.money),
          TripAccess.editor);
      expect(TripSync.spendersOf(old), ['owner-uid', 'priya']);
    });

    test('an empty money list means nobody, not everybody', () {
      // Once the list exists it is the only thing consulted -- otherwise
      // removing the last person from the ledger would silently fall back to
      // the whole membership.
      final data = trip(members: ['owner-uid', 'priya'], money: const []);
      expect(TripSync.spendersOf(data), isEmpty);
      expect(TripSync.accessOf(data, 'priya', scope: TripScope.money),
          TripAccess.viewer);
    });

    test('a stranger gets nothing either way', () {
      final old = {'owner': 'owner-uid', 'members': ['owner-uid']};
      expect(TripSync.accessOf(old, 'nobody', scope: TripScope.money),
          TripAccess.viewer);
    });
  });

  group('the fields each scope reads', () {
    test('are not the same fields', () {
      expect(tripMemberField(TripScope.trip), 'members');
      expect(tripMemberField(TripScope.money), 'money');
      expect(tripRequestField(TripScope.trip), 'requests');
      expect(tripRequestField(TripScope.money), 'money_requests');
    });
  });

  group('the link says which door it opens', () {
    test('the ledger link lands on the money', () {
      expect(
        TripSync.shareLink('abc123',
            base: 'https://triplix.app', scope: TripScope.money),
        'https://triplix.app/#/trip/abc123/money',
      );
    });

    test('the trip link is unchanged, so links already sent still work', () {
      expect(
        TripSync.shareLink('abc123', base: 'https://triplix.app'),
        'https://triplix.app/#/trip/abc123',
      );
    });
  });
}
