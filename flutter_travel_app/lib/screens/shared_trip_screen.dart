import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../services/auth_service.dart';
import '../services/python_adk_service.dart';
import '../services/trip_sync.dart';
import '../widgets/place_detail_sheet.dart';

/// A trip somebody shared, opened from its link.
///
/// Deliberately read-first. The link is a secret, not a password -- anyone
/// holding it can forward it to a group chat -- so arriving here shows the
/// trip and offers to ask for edit access. It never grants it.
class SharedTripScreen extends StatefulWidget {
  const SharedTripScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<SharedTripScreen> createState() => _SharedTripScreenState();
}

class _SharedTripScreenState extends State<SharedTripScreen> {
  final TripSync _sync = TripSync();
  final PythonADKService _adk = PythonADKService();
  final AuthService _authService = AuthService();

  Map<String, Map<String, dynamic>> _summaries = {};
  bool _signingIn = false;

  Map<String, dynamic>? _trip;
  bool _loading = true;
  bool _asking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _sync.fetch(widget.tripId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _trip = data;
      _error = data == null
          ? 'That trip could not be found. The link may be wrong, or the trip '
              'may have been deleted.'
          : null;
    });
    if (data != null) _loadSummaries(data);
  }

  /// The photo, rating and hours for every place in the shared trip.
  ///
  /// The same call the owner's screen makes. Without it a guest saw a list of
  /// names, which is not enough to judge a day by -- and judging the day is
  /// the entire reason they were sent the link.
  Future<void> _loadSummaries(Map<String, dynamic> data) async {
    final city = (data['destination'] ?? '').toString();
    final names = <String>{
      for (final day in (data['days'] as List?) ?? const [])
        if (day is Map<String, dynamic>)
          for (final item in (day['items'] as List?) ?? const [])
            if (item is Map<String, dynamic>)
              (item['title'] ?? '').toString(),
    }..removeWhere((n) => n.isEmpty);
    if (city.isEmpty || names.isEmpty) return;

    final found = await _adk.placeSummaries(city: city, names: names.toList());
    if (!mounted || found == null) return;
    setState(() => _summaries = found);
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      debugPrint('shared trip sign-in failed: $e');
    }
    if (!mounted) return;
    setState(() => _signingIn = false);
    // Reload: what this person may do depends entirely on who they now are.
    await _load();
  }

  /// What this user may do, recomputed whenever the trip is (re)loaded.
  TripAccess _access = TripAccess.signedOut;

  /// Suggests a place for a day. Goes to the owner, not into the plan.
  Future<void> _suggestPlace(int dayIndex) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Suggest a place for Day ${dayIndex + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Maitri Baag Zoo',
          ),
          onSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Suggest'),
          ),
        ],
      ),
    );
    if (!mounted || title == null || title.isEmpty) return;

    final ok = await _sync.proposeAdd(
      tripId: widget.tripId,
      dayIndex: dayIndex,
      title: title,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Suggested. The trip owner decides whether it goes in.'
          : 'That suggestion could not be sent.'),
    ));
  }

  Future<void> _requestAccess() async {
    setState(() => _asking = true);
    final ok = await _sync.requestAccess(widget.tripId);
    if (!mounted) return;
    setState(() => _asking = false);
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Asked for edit access. The trip owner decides.'),
      ));
    } else {
      setState(() => _error =
          'That request could not be sent. Check you are signed in, then try '
          'again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _trip;
    final where = (data?['destination'] ?? '').toString().split(',').first;
    final access = data == null
        ? TripAccess.signedOut
        : TripSync.accessOf(data, FirebaseAuth.instance.currentUser?.uid);
    _access = access;

    return Scaffold(
      appBar: AppBar(
        title: Text(where.isEmpty ? 'Shared trip' : 'Trip to $where'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text(_error!, textAlign: TextAlign.center)),
                )
              : StreamBuilder<List<TripProposal>>(
                  stream: _sync.openProposals(widget.tripId),
                  builder: (context, snapshot) {
                    // Everyone sees the same trip. Suggestions sit on top of
                    // it, marked, until the owner takes them -- so a
                    // contributor can see what they asked for without it
                    // pretending to be part of the plan.
                    final pending = snapshot.data ?? const <TripProposal>[];
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _accessBanner(access),
                        if (pending.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _pendingNote(pending.length),
                        ],
                        const SizedBox(height: 16),
                        ..._days(data!, pending),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _accessBanner(TripAccess access) {
    late final String message;
    Widget? action;

    switch (access) {
      case TripAccess.owner:
        message = 'This is your trip. You decide who can change it.';
      case TripAccess.editor:
        message = 'You can edit this trip.';
      case TripAccess.pending:
        // Said plainly. The alternative is somebody tapping "ask" repeatedly,
        // wondering whether the first one worked.
        message = 'You have asked to edit this trip. Waiting for the owner.';
      case TripAccess.viewer:
        message = 'You can read this trip. Ask the owner to make changes.';
        action = _asking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: _requestAccess,
                child: const Text('Ask to edit'),
              );
      case TripAccess.signedOut:
        // Every rule requires a signed-in account, and a proposal is stamped
        // with the author's uid by the rules themselves -- so a change is
        // provably from a real account rather than from whoever holds the
        // link. That only works if signing in is reachable from here.
        message = 'Sign in to open this trip.';
        action = _signingIn
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _signIn,
                child: const Text('Sign in'),
              );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          if (action != null) action,
        ],
      ),
    );
  }

  /// One place, with its photo, and openable for reviews, map and the AI.
  ///
  /// Tapping opens the same PlaceDetailSheet the owner uses, so a guest gets
  /// the photographs, the reviews and the question box rather than a name on
  /// a line. Nothing here can change the trip -- the sheet is read-only, and
  /// changes go through the suggestion flow.
  Widget _placeRow(String title, String city) {
    final summary = _summaries[title] ?? const {};
    final name = (summary['name'] ?? title).toString();
    final photo = (summary['photo'] ?? '').toString();
    final rating = summary['rating'];

    return InkWell(
      onTap: () => PlaceDetailSheet.show(context, name: name, city: city),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: photo.isEmpty
                  ? Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey[200],
                      child: Icon(Icons.place_outlined,
                          size: 18, color: Colors.grey[500]))
                  : Image.network(photo,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 44, height: 44, color: Colors.grey[200])),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14)),
                  if (rating != null)
                    Text('$rating ★',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  /// The confirmed legs and the running order for one day, as the owner
  /// sees them.
  List<Widget> _runningOrder(Map<String, dynamic> data, PlanDay day) {
    final key = day.date.toIso8601String().split('T').first;
    final fixed = [
      for (final line in ((data['fixed'] as Map?)?[key] as List?) ?? const [])
        line.toString()
    ];
    final notes = [
      for (final line in ((data['notes'] as Map?)?[key] as List?) ?? const [])
        line.toString()
    ];
    if (fixed.isEmpty && notes.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      for (final line in fixed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(Icons.flight_takeoff, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(line, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      if (notes.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suggested running order',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700])),
              const SizedBox(height: 4),
              for (final line in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('•  $line',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
    ];
  }

  /// Says how many suggestions are waiting, so the state of the trip is
  /// legible before scrolling through it.
  Widget _pendingNote(int count) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        count == 1
            ? '1 suggestion is waiting for the owner. It is shown below, and '
                'is not part of the trip yet.'
            : '$count suggestions are waiting for the owner. They are shown '
                'below, and are not part of the trip yet.',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// One suggested place, shown in the day it is meant for but visibly not
  /// part of it.
  ///
  /// Greyed and labelled rather than hidden: somebody who has just suggested
  /// something needs to see it landed, and somebody reading the trip needs to
  /// know it has not been agreed.
  Widget _pendingRow(TripProposal proposal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Icon(proposal.isAdd ? Icons.add : Icons.remove,
                size: 18, color: Colors.blue.shade400),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proposal.title,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic)),
                Text(
                  proposal.isAdd
                      ? 'Suggested — waiting for the owner'
                      : 'Suggested for removal — waiting for the owner',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _days(Map<String, dynamic> data,
      [List<TripProposal> pending = const []]) {
    final days = ((data['days'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanDay.fromJson)
        .toList();
    if (days.isEmpty) {
      return [const Text('This trip has nothing planned yet.')];
    }
    return [
      for (var i = 0; i < days.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Day ${i + 1}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    // Editors suggest; they do not write. The owner's copy is
                    // the trip, the same way a branch is not the master.
                    if (_access == TripAccess.editor ||
                        _access == TripAccess.owner)
                      TextButton.icon(
                        onPressed: () => _suggestPlace(i),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Suggest a place',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (days[i].items.isEmpty)
                  Text('Nothing planned yet',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic))
                else
                  for (final item in days[i].items)
                    _placeRow(item.title,
                        (data['destination'] ?? '').toString()),
                  for (final proposal in pending)
                    if (proposal.dayIndex == i) _pendingRow(proposal),
                  ..._runningOrder(data, days[i]),
              ],
            ),
          ),
        ),
    ];
  }
}

/// Publishes a trip and copies its link.
///
/// Published on share rather than on every edit, deliberately: a trip nobody
/// has shared has no reason to leave the device, and writing every keystroke
/// to Firestore would spend the free tier on documents no one will ever open.
Future<String?> shareTrip({
  required BuildContext context,
  required String tripId,
  required TripPlan plan,
  Map<String, List<String>> notes = const {},
  Map<String, List<String>> fixed = const {},
}) async {
  final sync = TripSync();
  if (!sync.canShare) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sign in first, so people know whose trip this is.'),
    ));
    return null;
  }

  final published = await sync.publish(
      tripId: tripId, plan: plan, notes: notes, fixed: fixed);
  if (!context.mounted) return null;
  if (!published) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('This trip could not be shared. Check your connection.'),
    ));
    return null;
  }

  final link = TripSync.shareLink(tripId);
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return link;

  // Says what the link actually does. "Shared" on its own invites people to
  // assume it is private to whoever they sent it to.
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('Link copied. Anyone with it can read your trip.'),
    action: SnackBarAction(
      label: 'Show',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share this trip'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  ));
  return link;
}
