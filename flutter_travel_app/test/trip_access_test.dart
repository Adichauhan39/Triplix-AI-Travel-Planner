import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_travel_app/services/trip_sync.dart';

/// The access rules are the security boundary, so the mapping from a trip
/// document to what somebody may do with it is worth testing directly —
/// separately from Firestore, which enforces the same thing server-side.
void main() {
  Map<String, dynamic> trip({
    String owner = 'owner-uid',
    List<String> members = const ['owner-uid'],
    List<String> requests = const [],
  }) =>
      {'owner': owner, 'members': members, 'requests': requests};

  test('the owner owns it', () {
    expect(TripSync.accessOf(trip(), 'owner-uid'), TripAccess.owner);
  });

  test('someone with the link can read but not edit', () {
    expect(TripSync.accessOf(trip(), 'stranger'), TripAccess.viewer);
  });

  test('an approved traveller can edit', () {
    expect(
      TripSync.accessOf(trip(members: ['owner-uid', 'priya']), 'priya'),
      TripAccess.editor,
    );
  });

  test('someone who has asked is pending, not an editor', () {
    expect(
      TripSync.accessOf(trip(requests: ['priya']), 'priya'),
      TripAccess.pending,
      // The whole point of the request flow: asking is not the same as being
      // granted, and a forwarded link must not confer edit rights.
    );
  });

  test('signed out means no access at all', () {
    expect(TripSync.accessOf(trip(), null), TripAccess.signedOut);
  });

  test('a missing members list does not crash or grant access', () {
    expect(TripSync.accessOf({'owner': 'owner-uid'}, 'priya'),
        TripAccess.viewer);
  });

  test('the share link carries the id and nothing else', () {
    const id = 'k7m2p9qrst34';
    final link = TripSync.shareLink(id, base: 'https://triplix.app');
    expect(link, 'https://triplix.app/#/trip/$id');

    // And on localhost it points at localhost, so a copied link opens the
    // trip a developer actually has.
    expect(TripSync.shareLink(id, base: 'http://localhost:8080'),
        'http://localhost:8080/#/trip/$id');
    // No name, no dates, no hint about who made it.
    expect(link.split('/').last, id);
  });

  group('who is asking', () {
    test('a name is shown when we have one', () {
      final p = TripPerson.from('uid1', {'name': 'Priya', 'email': 'p@x.com'});
      expect(p.label, 'Priya');
      expect(p.subtitle, 'p@x.com',
          reason: 'the email tells two Priyas apart');
    });

    test('the email stands in when there is no name', () {
      final p = TripPerson.from('uid1', {'name': '', 'email': 'p@x.com'});
      expect(p.label, 'p@x.com');
      expect(p.subtitle, isEmpty, reason: 'never the same thing twice');
    });

    test('an unknown person is a shortened uid, not a placeholder', () {
      // "A traveller" would make two simultaneous requests identical, and the
      // owner is being asked to decide between them.
      final p = TripPerson.from('abcdefghijklmnop', null);
      expect(p.label, 'abcdefghij…');
    });
  });
}
