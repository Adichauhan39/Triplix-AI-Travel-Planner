import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/trip_sync.dart';

/// Shows the owner who has asked to help with this trip, and lets them decide.
///
/// The half that was missing: asking for access was built and enforced, but
/// nothing surfaced the request, so it sat in the database with no way to
/// accept it. A permission model with no visible approval step is the same as
/// no sharing at all.
///
/// Renders nothing at all when there is nothing waiting -- an empty
/// "no requests" panel on every trip would be noise on the screen people look
/// at most.
class TripAccessRequests extends StatefulWidget {
  const TripAccessRequests({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripAccessRequests> createState() => _TripAccessRequestsState();
}

class _TripAccessRequestsState extends State<TripAccessRequests> {
  final TripSync _sync = TripSync();

  /// Uids currently being approved or declined, so a second tap on the same
  /// row cannot fire while the first is still in flight.
  final Set<String> _busy = {};

  Future<void> _decide(String uid, {required bool allow}) async {
    setState(() => _busy.add(uid));
    final ok = allow
        ? await _sync.approve(widget.tripId, uid)
        : await _sync.deny(widget.tripId, uid);
    if (!mounted) return;
    setState(() => _busy.remove(uid));

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (allow
              ? 'They can edit this trip now.'
              : 'Request declined. They can still read the trip.')
          : 'That did not go through. Check your connection.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tripId.isEmpty || !_sync.canShare) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<TripPerson>>(
      stream: _sync.pendingRequests(widget.tripId),
      builder: (context, snapshot) {
        final waiting = snapshot.data ?? const <TripPerson>[];
        if (waiting.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                waiting.length == 1
                    ? 'Someone wants to help plan this trip'
                    : '${waiting.length} people want to help plan this trip',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'They can already read it. Approving lets them add and remove '
                'places.',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              for (final person in waiting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person.label,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            if (person.subtitle.isNotEmpty)
                              Text(person.subtitle,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (_busy.contains(person.uid))
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        TextButton(
                          onPressed: () =>
                              _decide(person.uid, allow: false),
                          child: const Text('Decline',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton(
                          onPressed: () => _decide(person.uid, allow: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Approve',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Suggested changes from collaborators, waiting on the owner.
///
/// The merge step. A collaborator's change never touches the plan directly --
/// it arrives here as a sentence the owner can accept or reject, one at a
/// time, the way a pull request is reviewed rather than pushed.
///
/// Accepting applies the change through TripPlanProvider and republishes, so
/// a suggestion that is taken goes through exactly the same path as an edit
/// the owner made themselves. One way for the plan to change, whoever
/// thought of it.
class TripProposalReview extends StatefulWidget {
  const TripProposalReview({
    super.key,
    required this.tripId,
    required this.onAccept,
  });

  final String tripId;

  /// Applies an accepted change to the local plan. Kept out of this widget so
  /// it does not need to know how a plan is edited or republished.
  final Future<void> Function(TripProposal proposal) onAccept;

  @override
  State<TripProposalReview> createState() => _TripProposalReviewState();
}

class _TripProposalReviewState extends State<TripProposalReview> {
  final TripSync _sync = TripSync();
  final Set<String> _busy = {};

  Future<void> _settle(TripProposal proposal, {required bool accept}) async {
    setState(() => _busy.add(proposal.id));
    if (accept) await widget.onAccept(proposal);
    final ok = await _sync.settleProposal(
      tripId: widget.tripId,
      proposalId: proposal.id,
      accepted: accept,
    );
    if (!mounted) return;
    setState(() => _busy.remove(proposal.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (accept ? 'Added to your trip.' : 'Suggestion dismissed.')
          : 'That did not go through. Check your connection.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tripId.isEmpty || !_sync.canShare) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<TripProposal>>(
      stream: _sync.openProposals(widget.tripId),
      builder: (context, snapshot) {
        final open = snapshot.data ?? const <TripProposal>[];
        if (open.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                open.length == 1
                    ? '1 suggested change'
                    : '${open.length} suggested changes',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Nothing changes in your trip until you accept it.',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              for (final proposal in open)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(proposal.summary,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      if (_busy.contains(proposal.id))
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        TextButton(
                          onPressed: () => _settle(proposal, accept: false),
                          child: const Text('No',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton(
                          onPressed: () => _settle(proposal, accept: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Accept',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

