import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/trip_plan.dart';

/// Somebody involved in a trip, named where the name is known.
class TripPerson {
  const TripPerson({required this.uid, required this.name, required this.email});

  factory TripPerson.from(String uid, Map<String, dynamic>? profile) =>
      TripPerson(
        uid: uid,
        name: (profile?['name'] ?? '').toString().trim(),
        email: (profile?['email'] ?? '').toString().trim(),
      );

  final String uid;
  final String name;
  final String email;

  /// What to put on screen. Falls back through name, email, then a shortened
  /// uid -- never an invented placeholder, because two anonymous requests
  /// reading "A traveller" cannot be told apart.
  String get label {
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return uid.length > 10 ? '${uid.substring(0, 10)}…' : uid;
  }

  /// Shown under the name when we have both, so the owner can tell two people
  /// with the same first name apart.
  String get subtitle => name.isNotEmpty && email.isNotEmpty ? email : '';
}

/// One suggested change to a trip, waiting on its owner.
class TripProposal {
  const TripProposal({
    required this.id,
    required this.kind,
    required this.dayIndex,
    required this.title,
    required this.by,
  });

  factory TripProposal.fromDoc(String id, Map<String, dynamic> data) =>
      TripProposal(
        id: id,
        kind: (data['kind'] ?? '').toString(),
        dayIndex: (data['day'] as num?)?.toInt() ?? 0,
        title: (data['title'] ?? '').toString(),
        by: (data['by'] ?? '').toString(),
      );

  final String id;

  /// 'add' or 'remove'.
  final String kind;
  final int dayIndex;
  final String title;
  final String by;

  bool get isAdd => kind == 'add';

  /// How the change reads to the person deciding on it.
  String get summary => isAdd
      ? 'Add $title to Day ${dayIndex + 1}'
      : 'Remove $title from Day ${dayIndex + 1}';
}

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
  /// [notes] is the running order per ISO date, and [fixed] the confirmed
  /// flights and hotels per ISO date.
  ///
  /// Published because they are the plan. A day carries only its date and its
  /// places, so without these a guest opened the link and saw a list of names
  /// -- not when to set off, not which hotel, not the flight. The part worth
  /// sharing was the part that never left the owner's screen.
  Future<bool> publish({
    required String tripId,
    required TripPlan plan,
    String? title,
    Map<String, List<String>> notes = const {},
    Map<String, List<String>> fixed = const {},
  }) async {
    final uid = _uid;
    if (uid == null || tripId.isEmpty) return false;
    try {
      final doc = _trips.doc(tripId);
      final existing = await doc.get();

      if (!existing.exists) {
        // Plain values, not FieldValue transforms.
        //
        // Security rules cannot see the result of arrayUnion, increment or
        // serverTimestamp: transforms are applied after the rule runs, so
        // `request.resource.data.members` reads as absent. The create rule
        // requires the author to be in members, so writing members with
        // arrayUnion made that rule permanently unsatisfiable -- every first
        // publish was rejected, which is why sharing did nothing at all.
        await doc.set({
          'destination': plan.destination,
          'title': title ?? plan.destination,
          'days': plan.toJson(),
          'notes': notes,
          'fixed': fixed,
          'owner': uid,
          'members': [uid],
          'requests': <String>[],
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': uid,
        });
        return true;
      }

      // Re-publishing touches the plan and nothing else. Members and requests
      // are deliberately absent: re-sending the whole document would wipe the
      // people who had been approved, and the rules forbid a member changing
      // them at all.
      await doc.update({
        'destination': plan.destination,
        'title': title ?? plan.destination,
        'days': plan.toJson(),
        'notes': notes,
        'fixed': fixed,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': uid,
      });
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
      // Read, extend, write the whole list -- not arrayUnion.
      //
      // The person asking is not the owner, so their write has to satisfy the
      // rule that they are adding themselves and removing nobody. That rule
      // reads request.resource.data.requests, which does not contain the
      // result of a transform, so an arrayUnion write could never pass it.
      //
      // Owner-side calls (approve, deny, removeMember) may keep using
      // transforms: the owner is allowed outright and no rule inspects what
      // they wrote.
      final doc = _trips.doc(tripId);
      final snapshot = await doc.get();
      if (!snapshot.exists) return false;

      final existing = [
        for (final entry in (snapshot.data()?['requests'] as List?) ?? const [])
          entry.toString()
      ];
      if (existing.contains(uid)) return true;

      // The asker's name travels with the request. The owner was being shown
      // a raw uid and asked to decide whether to trust it, which is not a
      // decision anybody can make. Written from the signed-in account, and the
      // rules allow each person to write only their own entry -- so a name in
      // this list cannot be somebody else's.
      final user = _auth.currentUser;
      final profiles =
          Map<String, dynamic>.from(snapshot.data()?['profiles'] as Map? ?? {});
      profiles[uid] = {
        'name': (user?.displayName ?? '').trim(),
        'email': (user?.email ?? '').trim(),
      };

      await doc.update({
        'requests': [...existing, uid],
        'profiles': profiles,
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

  /// The people waiting on the owner, named where we know the name.
  Stream<List<TripPerson>> pendingRequests(String tripId) {
    if (tripId.isEmpty) return const Stream<List<TripPerson>>.empty();
    return _trips.doc(tripId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final profiles = (data['profiles'] as Map?) ?? const {};
      return [
        for (final entry in (data['requests'] as List?) ?? const [])
          TripPerson.from(
            entry.toString(),
            (profiles[entry.toString()] as Map?)?.cast<String, dynamic>(),
          )
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

  // --- Proposals ------------------------------------------------------
  //
  // Changes from anyone other than the owner are proposed, not applied. The
  // trip document is the master copy and only its owner writes to it; a
  // collaborator writes a proposal, and the owner accepts or rejects it.
  //
  // Item-level, not a whole-document diff. "Add Maitri Baag Zoo to Day 2" is
  // something an owner can judge on its own and accept while rejecting the
  // rest. A diff of the entire plan is all-or-nothing, and unreadable in the
  // one place it needs to be read.
  //
  // This is also a simpler security story than shared write access: nobody but
  // the owner can alter the plan, so there is no conflict to resolve and no
  // rule that has to reason about which parts of a document changed.

  CollectionReference<Map<String, dynamic>> _proposalsOf(String tripId) =>
      _trips.doc(tripId).collection('proposals');

  /// Suggests adding a place to a day.
  Future<bool> proposeAdd({
    required String tripId,
    required int dayIndex,
    required String title,
  }) =>
      _propose(tripId, {
        'kind': 'add',
        'day': dayIndex,
        'title': title.trim(),
      });

  /// Suggests dropping a place from a day.
  Future<bool> proposeRemove({
    required String tripId,
    required int dayIndex,
    required String title,
  }) =>
      _propose(tripId, {
        'kind': 'remove',
        'day': dayIndex,
        'title': title.trim(),
      });

  Future<bool> _propose(String tripId, Map<String, dynamic> change) async {
    final uid = _uid;
    if (uid == null || tripId.isEmpty) return false;
    if ((change['title'] ?? '').toString().isEmpty) return false;
    try {
      await _proposalsOf(tripId).add({
        ...change,
        'by': uid,
        'state': 'open',
        'created_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.propose failed: $e');
      return false;
    }
  }

  /// Everything still awaiting the owner, oldest first.
  Stream<List<TripProposal>> openProposals(String tripId) {
    if (tripId.isEmpty) return const Stream<List<TripProposal>>.empty();
    return _proposalsOf(tripId)
        .where('state', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TripProposal.fromDoc(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex)))
        .handleError((Object e) {
      debugPrint('TripSync.openProposals failed: $e');
    });
  }

  /// Marks a proposal accepted or rejected.
  ///
  /// The plan itself is changed by the caller through TripPlanProvider and
  /// then republished, so an accepted proposal goes through exactly the same
  /// path as an edit the owner made themselves -- one way for the plan to
  /// change, whoever suggested it.
  Future<bool> settleProposal({
    required String tripId,
    required String proposalId,
    required bool accepted,
  }) async {
    if (tripId.isEmpty || proposalId.isEmpty) return false;
    try {
      await _proposalsOf(tripId).doc(proposalId).update({
        'state': accepted ? 'accepted' : 'rejected',
        'settled_at': FieldValue.serverTimestamp(),
        'settled_by': _uid,
      });
      return true;
    } catch (e) {
      debugPrint('TripSync.settleProposal failed: $e');
      return false;
    }
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
