import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../services/trip_sync.dart';

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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _accessBanner(access),
                    const SizedBox(height: 16),
                    ..._days(data!),
                  ],
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
        message = 'Sign in to open this trip.';
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

  List<Widget> _days(Map<String, dynamic> data) {
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
                Text('Day ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (days[i].items.isEmpty)
                  Text('Nothing planned yet',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic))
                else
                  for (final item in days[i].items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('•  ${item.title}',
                          style: const TextStyle(fontSize: 14)),
                    ),
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
}) async {
  final sync = TripSync();
  if (!sync.canShare) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sign in first, so people know whose trip this is.'),
    ));
    return null;
  }

  final published = await sync.publish(tripId: tripId, plan: plan);
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
