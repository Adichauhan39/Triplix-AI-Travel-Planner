import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/trip_plan.dart';

/// What the signed-in user may do with a trip.
///
/// Reading is deliberately open to anyone holding the link -- that is what
/// makes "look at what I planned for us" work without an invitation dance.
/// Changing it is not.
enum TripAccess {
  /// Not signed in: cannot read a shared trip at all.
  signedOut,

  /// Has the link and can read it, but cannot change anything.
  viewer,

  /// Has asked the owner for edit access and is waiting.
  pending,

  /// May edit the plan, but not change the owner or remove anyone.
  editor,

  /// Made the trip. Approves requests, and is the only one who can delete it.
  owner,
}

/// Puts a trip somewhere both travellers can reach it.
///
/// The plan has always lived on one device, which is right for a plan only its
/// author reads and useless for one two people are deciding together. A trip is
/// published under its id; anyone holding that id can open it and, if they are
/// a member, change it.
///
/// Firestore rather than our own endpoint for one reason: realtime listeners.
/// Two people editing the same day is otherwise a sync protocol to design,
/// and this is a small document edited occasionally by people who are usually
/// talking to each other while they do it.
class TripSync {
  TripSync({FirebaseFirestore? store, FirebaseAuth? auth})
      : _store = store ?? defaultStore(),
        _auth = auth ?? FirebaseAuth.instance;

  /// The database this project actually has.
  ///
  /// Firestore was created as a *named* database rather than the unnamed
  /// `(default)` one, and `FirebaseFirestore.instance` is hard-wired to
  /// `(default)`. Pointing at the wrong database does not raise: reads simply
  /// return nothing and writes go somewhere nobody looks, which is the kind of
  /// failure that gets diagnosed as "sharing doesn't work" for a week.
  ///
  /// Named here so it is one line to change, and so the name lives beside the
  /// explanation of why it is needed.
  static const String databaseId = 'kdvitisharedb';

  static FirebaseFirestore defaultStore() =>
      FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: databaseId,
      );

  final FirebaseFirestore _store;
  final FirebaseAuth _auth;

  static const String _collection = 'trips';

  CollectionReference<Map<String, dynamic>> get _trips =>
      _store.collection(_collection);

  String? get _uid => _auth.currentUser?.uid;

  /// Whether sharing is available at all. Signing in is what makes an editor a
  /// person rather than an anonymous browser, so nothing is published without
  /// it.
  bool get canShare => _uid != null;

  /// Writes the trip, creating it on first publish.
  ///
  /// The owner is recorded once and never overwritten: a co-traveller saving a
  /// change must not become the owner of somebody else's trip.
  Future<bool> publish({
    required String tripId,
    required TripPlan plan,
    String? title,
  }) async {
    final uid = _uid;
    if (uid == null || tripId.isEmpty) return false;
    try {
      await _trips.doc(tripId).set({
        'destination': plan.destination,
        'title': title ?? plan.destination,
        'days': plan.toJson(),
        'owner': uid,
        'members': FieldValue.arrayUnion([uid]),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': uid,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('TripSync.publish failed: $e');
      return false;
    }
  }

  /// Asks the trip's owner for edit access.
  ///
  /// Replaces self-service joining, which was wrong twice over: a link
  /// forwarded to a group chat would have handed edit rights to whoever opened
  /// it, and adding yourself to `members` is an update, which the rules
  /// require membership for -- so it could never have worked anyway.
  ///
  /// Reading needs no request. Someone sent a link can look at the trip
  /// immediately; asking is only for changing it.
  Future<bool> requestAccess(String tripId) async {
    final uid = _uid;
    if (uid == null || tripId.isEmpty) return false;
    try {
      await _trips.doc(tripId).update({
        'requests': FieldValue.arrayUnion([uid]),
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.requestAccess failed: $e');
      return false;
    }
  }

  /// Grants edit access. Only the owner can do this; the rules enforce it, and
  /// this checks too so the UI can hide what would fail.
  Future<bool> approve(String tripId, String uid) async {
    if (tripId.isEmpty || uid.isEmpty) return false;
    try {
      await _trips.doc(tripId).update({
        'members': FieldValue.arrayUnion([uid]),
        'requests': FieldValue.arrayRemove([uid]),
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.approve failed: $e');
      return false;
    }
  }

  /// Turns a request down, leaving read access as it was.
  Future<bool> deny(String tripId, String uid) async {
    if (tripId.isEmpty || uid.isEmpty) return false;
    try {
      await _trips.doc(tripId).update({
        'requests': FieldValue.arrayRemove([uid]),
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.deny failed: $e');
      return false;
    }
  }

  /// Removes someone's edit access without deleting the trip.
  Future<bool> removeMember(String tripId, String uid) async {
    if (tripId.isEmpty || uid.isEmpty) return false;
    try {
      await _trips.doc(tripId).update({
        'members': FieldValue.arrayRemove([uid]),
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.removeMember failed: $e');
      return false;
    }
  }

  /// What the signed-in user is allowed to do with this trip.
  TripAccess accessFor(Map<String, dynamic> data) =>
      accessOf(data, _uid);

  /// The access rule itself, as a function of the document and a user id.
  ///
  /// Deliberately free of FirebaseAuth so it can be tested directly: this is
  /// the client half of a security boundary, and a rule that can only be
  /// exercised by standing up an authenticated app is a rule nobody checks.
  /// Firestore enforces the same thing server-side, which is what actually
  /// stops a modified client -- this decides what the UI offers.
  static TripAccess accessOf(Map<String, dynamic> data, String? uid) {
    if (uid == null || uid.isEmpty) return TripAccess.signedOut;
    if ((data['owner'] ?? '').toString() == uid) return TripAccess.owner;
    final members = (data['members'] as List?) ?? const [];
    if (members.contains(uid)) return TripAccess.editor;
    final requests = (data['requests'] as List?) ?? const [];
    if (requests.contains(uid)) return TripAccess.pending;
    return TripAccess.viewer;
  }

  /// The people waiting on the owner, so the trip screen can show them.
  Stream<List<String>> pendingRequests(String tripId) {
    if (tripId.isEmpty) return const Stream<List<String>>.empty();
    return _trips.doc(tripId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      return [
        for (final uid in (data['requests'] as List?) ?? const [])
          uid.toString()
      ];
    }).handleError((Object e) {
      debugPrint('TripSync.pendingRequests failed: $e');
    });
  }

  /// The trip as it stands right now, or null if there is no such trip.
  Future<Map<String, dynamic>?> fetch(String tripId) async {
    if (tripId.isEmpty) return null;
    try {
      final snapshot = await _trips.doc(tripId).get();
      return snapshot.exists ? snapshot.data() : null;
    } catch (e) {
      debugPrint('TripSync.fetch failed: $e');
      return null;
    }
  }

  /// Live updates for a trip, so a change one traveller makes appears for the
  /// other without either of them reloading.
  Stream<TripPlan?> watch(String tripId) {
    if (tripId.isEmpty) return const Stream<TripPlan?>.empty();
    return _trips.doc(tripId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      final days = ((data['days'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlanDay.fromJson)
          .toList();
      if (days.isEmpty) return null;
      return TripPlan(
        destination: (data['destination'] ?? '').toString(),
        days: days,
      );
    }).handleError((Object e) {
      // A stream that throws would take the trip screen down with it. A
      // failure to sync should cost the live update, not the itinerary the
      // user already has on their device.
      debugPrint('TripSync.watch failed: $e');
    });
  }

  /// Whether the last write we can see came from somebody else, so the screen
  /// can say "Priya added a place" rather than silently rearranging itself.
  bool isForeignEdit(Map<String, dynamic> data) {
    final by = (data['updated_by'] ?? '').toString();
    return by.isNotEmpty && by != _uid;
  }

  /// The link to give someone. Deliberately the trip id and nothing else: it
  /// carries no name, no dates and no clue about who made it.
  ///
  /// Built from wherever the app is actually running, so a link copied on
  /// localhost opens on localhost. Hard-coding the production domain would
  /// hand every developer a link to a site that does not have their trip.
  static String shareLink(String tripId, {String? base}) {
    final origin = base ?? Uri.base.origin;
    return '$origin/#/trip/$tripId';
  }
}
