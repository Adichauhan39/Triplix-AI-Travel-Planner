/// The trip's history of changes to its spending, folded away until wanted.
///
/// Folded because it is the answer to a question people only sometimes have --
/// "who changed the cab to 5,000?" -- and a running log open all the time
/// would push the settlement, which everybody wants, off the bottom.
library;

import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../services/trip_sync.dart';

class TripChangesView extends StatelessWidget {
  const TripChangesView({
    super.key,
    required this.tripId,
    required this.nameOf,
    this.me,
  });

  final String tripId;
  final String Function(String uid) nameOf;
  final String? me;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// "just now", "12 min ago", "3 h ago", "yesterday", "14 Sep".
  static String _when(DateTime at) {
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) return '${gap.inHours} h ago';
    if (gap.inDays == 1) return 'yesterday';
    return '${at.day} ${_months[at.month - 1]}';
  }

  static IconData _icon(String action) => switch (action) {
        'added' => Icons.add_circle_outline,
        'edited' => Icons.edit_outlined,
        'removed' => Icons.delete_outline,
        'split' => Icons.call_split,
        'approved' => Icons.check_circle_outline,
        'rejected' => Icons.cancel_outlined,
        _ => Icons.history,
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TripChange>>(
      stream: TripSync().changes(tripId),
      builder: (context, snapshot) {
        final changes = snapshot.data ?? const <TripChange>[];
        if (changes.isEmpty) return const SizedBox.shrink();

        return Container(
          decoration: Brand.card(),
          child: Theme(
            // No divider lines above and below the fold: this sits in a card
            // that already has its own edge.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: Brand.gap),
              childrenPadding:
                  const EdgeInsets.fromLTRB(Brand.gap, 0, Brand.gap, Brand.gap),
              leading: const Icon(Icons.history, size: 18, color: Brand.teal),
              title: const Text('Recent changes',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text(
                'Last: ${changes.first.summary}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Brand.muted),
              ),
              children: [
                for (final change in changes.take(25))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_icon(change.action),
                            size: 15, color: Brand.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(change.summary,
                                  style: const TextStyle(fontSize: 12)),
                              Text(
                                // The name the group knows them by, falling
                                // back to the account name written with it.
                                '${change.by == me ? 'You' : _who(change)}'
                                ' · ${_when(change.at)}',
                                style: const TextStyle(
                                    fontSize: 10, color: Brand.faint),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _who(TripChange change) {
    final known = nameOf(change.by);
    if (known.isNotEmpty && known != change.by) return known;
    return change.byName.isNotEmpty ? change.byName : 'Someone';
  }
}
