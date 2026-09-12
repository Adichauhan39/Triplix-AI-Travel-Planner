/// Who one expense is divided between.
///
/// The split used to be all or nothing: everybody, or nobody. A dinner three
/// of five people went to had to be either the whole group's or filed as "just
/// mine", which credits the payer with nothing -- so the honest answer, "it
/// was just us three", could not be recorded at all.
library;

import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../services/expense_columns.dart';
import '../services/trip_sync.dart';

/// Asks who shares an expense, and returns their uids.
///
/// An empty list means everybody, which is what an expense with nothing set
/// has always meant -- so "select all" and "select none of the exceptions"
/// are the same answer, and the dialog returns the simpler one.
///
/// Returns null when the person backs out, which must not be confused with an
/// empty list: one means "leave it alone", the other means "everyone".
Future<List<String>?> askWhoShares(
  BuildContext context, {
  required TripExpense row,
  required List<TripPerson> people,
  required String? me,
  required bool needsApproval,
}) async {
  if (people.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('There is nobody else on this trip yet, so there is '
          'nothing to split.'),
    ));
    return null;
  }

  // Nothing set means everyone, so that is where the boxes start.
  final chosen = <String>{
    ...(row.sharedWith.isEmpty
        ? people.map((p) => p.uid)
        : row.sharedWith.where((uid) => people.any((p) => p.uid == uid))),
  };

  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setState) {
        final everyone = chosen.length == people.length;

        return AlertDialog(
          backgroundColor: Brand.surface,
          title: const Text('Split between', style: Brand.heading),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${row.note.isEmpty ? row.category : row.note} · '
                  '${formatRupees(row.paise)}',
                  style: Brand.caption,
                ),
                const SizedBox(height: Brand.gap),

                // One tap for the common case, rather than five.
                CheckboxListTile(
                  value: everyone,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Brand.teal,
                  checkColor: Colors.white,
                  title: const Text('Everyone',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  onChanged: (want) => setState(() {
                    chosen.clear();
                    if (want == true) {
                      chosen.addAll(people.map((p) => p.uid));
                    }
                  }),
                ),
                const Divider(height: 1, color: Brand.hairline),

                for (final person in people)
                  CheckboxListTile(
                    value: chosen.contains(person.uid),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Brand.teal,
                    checkColor: Colors.white,
                    title: Text(
                      person.uid == me ? 'You' : person.label,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (want) => setState(() {
                      if (want == true) {
                        chosen.add(person.uid);
                      } else {
                        chosen.remove(person.uid);
                      }
                    }),
                  ),

                const SizedBox(height: Brand.tight),
                // The arithmetic, before they commit to it. "₹1,800 between
                // 3" is the thing they are actually deciding.
                Text(
                  chosen.isEmpty
                      ? 'Nobody selected. Pick at least one person, or take '
                          'the expense out of the split instead.'
                      : '${formatRupees(row.paise)} between ${chosen.length} '
                          '· ${formatRupees(row.paise ~/ chosen.length)} each',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: chosen.isEmpty ? Brand.danger : Brand.muted,
                  ),
                ),
                if (needsApproval) ...[
                  const SizedBox(height: Brand.tight),
                  const Text(
                    'This changes what other people owe, so it goes to the '
                    'trip owner to approve first.',
                    style: Brand.caption,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              // No empty answer. An empty list already means "everybody" in
              // the stored row, so letting it through here would silently do
              // the opposite of what the boxes show.
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        chosen.length == people.length
                            ? <String>[]
                            : chosen.toList(),
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Brand.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
