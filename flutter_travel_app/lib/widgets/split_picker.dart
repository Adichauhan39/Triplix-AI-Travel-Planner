/// Who one expense is divided between, and how much each of them owes.
///
/// The split used to be all or nothing: everybody, or nobody. A dinner three
/// of five people went to had to be either the whole group's or filed as "just
/// mine", which credits the payer with nothing -- so the honest answer, "it
/// was just us three", could not be recorded at all.
///
/// Equal between the people who were there covers most of it. What it cannot
/// say is that one person had the ₹900 thali and another a ₹200 chai, and
/// halving that bill is a worse answer than not recording the meal. So there
/// is a second mode with a box per person, and it will not save until the
/// amounts add up to the bill -- money that does not add up is what makes a
/// shared ledger stop being believed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/brand.dart';
import '../services/expense_columns.dart';
import '../services/settle_up.dart';
import '../services/trip_sync.dart';

/// How an expense should be divided.
class SplitChoice {
  const SplitChoice({required this.people, required this.shares});

  /// Who shares it. Empty means everyone, which is what a row with nothing
  /// set has always meant.
  final List<String> people;

  /// Exact amounts per person, in paise. Empty means divide equally.
  final Map<String, int> shares;

  bool get isExact => shares.isNotEmpty;
}

/// Asks who shares an expense and how.
///
/// Returns null when the person backs out, which must not be confused with an
/// empty answer: one means "leave it alone", the other means "everyone,
/// equally".
Future<SplitChoice?> askWhoShares(
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

  return showDialog<SplitChoice>(
    context: context,
    builder: (dialogContext) => _SplitDialog(
      row: row,
      people: people,
      me: me,
      needsApproval: needsApproval,
    ),
  );
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({
    required this.row,
    required this.people,
    required this.me,
    required this.needsApproval,
  });

  final TripExpense row;
  final List<TripPerson> people;
  final String? me;
  final bool needsApproval;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  /// Who is in. Nothing set means everyone, so that is where the boxes start.
  late final Set<String> _chosen = {
    ...(widget.row.sharedWith.isEmpty
        ? widget.people.map((p) => p.uid)
        : widget.row.sharedWith
            .where((uid) => widget.people.any((p) => p.uid == uid))),
  };

  /// True once somebody asks for exact amounts. Starts on for a row that
  /// already has them, so opening the dialog does not quietly flatten a split
  /// somebody set up carefully.
  late bool _exact = widget.row.shares.isNotEmpty;

  late final Map<String, TextEditingController> _fields = {
    for (final person in widget.people)
      person.uid: TextEditingController(
        text: _startingAmount(person.uid),
      ),
  };

  /// What to put in a person's box when the dialog opens.
  ///
  /// Their stored share if the row has one, otherwise their equal portion --
  /// so switching to exact amounts starts from what they owe now rather than
  /// from an empty form.
  String _startingAmount(String uid) {
    final stored = widget.row.shares[uid];
    if (stored != null && stored > 0) return (stored / 100).toStringAsFixed(2);

    final party = _partyAtStart();
    if (!party.contains(uid)) return '';
    final equal = fairShares(widget.row.paise, party);
    return ((equal[uid] ?? 0) / 100).toStringAsFixed(2);
  }

  List<String> _partyAtStart() {
    if (widget.row.shares.isNotEmpty) {
      return widget.row.shares.keys.toList();
    }
    if (widget.row.sharedWith.isNotEmpty) {
      return widget.row.sharedWith
          .where((uid) => widget.people.any((p) => p.uid == uid))
          .toList();
    }
    return widget.people.map((p) => p.uid).toList();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// The typed amounts, in paise, for everybody with something in their box.
  Map<String, int> get _typed {
    final out = <String, int>{};
    _fields.forEach((uid, field) {
      final value = double.tryParse(field.text.trim().replaceAll(',', ''));
      if (value != null && value > 0) out[uid] = rupeesToPaise(value);
    });
    return out;
  }

  int get _assigned => _typed.values.fold(0, (sum, paise) => sum + paise);

  /// What is left to account for. Zero is the only figure that may be saved.
  int get _left => widget.row.paise - _assigned;

  String _nameFor(TripPerson person) =>
      person.uid == widget.me ? 'You' : person.label;

  void _save() {
    if (_exact) {
      Navigator.pop(
        context,
        SplitChoice(people: const [], shares: _typed),
      );
      return;
    }
    Navigator.pop(
      context,
      SplitChoice(
        // Everybody is expressed as an empty list, the same as a row that
        // was never touched -- so there is one representation of "everyone"
        // rather than two that have to agree.
        people: _chosen.length == widget.people.length
            ? const []
            : _chosen.toList(),
        shares: const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final everyone = _chosen.length == widget.people.length;
    final canSave = _exact ? _left == 0 && _typed.isNotEmpty : _chosen.isNotEmpty;

    return AlertDialog(
      backgroundColor: Brand.surface,
      title: const Text('Split between', style: Brand.heading),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.row.note.isEmpty ? widget.row.category : widget.row.note}'
              ' · ${formatRupees(widget.row.paise)}',
              style: Brand.caption,
            ),
            const SizedBox(height: Brand.gap),

            // Equal or exact. Two taps apart, because equal is what almost
            // every row wants and exact is the exception.
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Equally')),
                ButtonSegment(value: true, label: Text('Exact amounts')),
              ],
              selected: {_exact},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              onSelectionChanged: (choice) =>
                  setState(() => _exact = choice.first),
            ),
            const SizedBox(height: Brand.gap),

            if (!_exact) ...[
              CheckboxListTile(
                value: everyone,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Brand.teal,
                checkColor: Colors.white,
                title: const Text('Everyone',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                onChanged: (want) => setState(() {
                  _chosen.clear();
                  if (want == true) {
                    _chosen.addAll(widget.people.map((p) => p.uid));
                  }
                }),
              ),
              const Divider(height: 1, color: Brand.hairline),
              for (final person in widget.people)
                CheckboxListTile(
                  value: _chosen.contains(person.uid),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Brand.teal,
                  checkColor: Colors.white,
                  title: Text(_nameFor(person),
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  onChanged: (want) => setState(() {
                    if (want == true) {
                      _chosen.add(person.uid);
                    } else {
                      _chosen.remove(person.uid);
                    }
                  }),
                ),
              const SizedBox(height: Brand.tight),
              // The arithmetic before they commit to it: "₹1,800 between 3"
              // is the thing actually being decided.
              Text(
                _chosen.isEmpty
                    ? 'Nobody selected. Pick at least one person, or take the '
                        'expense out of the split instead.'
                    : '${formatRupees(widget.row.paise)} between '
                        '${_chosen.length} · '
                        '${formatRupees(widget.row.paise ~/ _chosen.length)} '
                        'each',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _chosen.isEmpty ? Brand.danger : Brand.muted,
                ),
              ),
            ] else ...[
              for (final person in widget.people)
                Padding(
                  padding: const EdgeInsets.only(bottom: Brand.tight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_nameFor(person),
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(
                        width: 108,
                        child: TextField(
                          controller: _fields[person.uid],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            prefixText: '₹',
                            isDense: true,
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Brand.radiusSmall),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Brand.tight),
              // Nothing saves while this is not zero. A ledger where the
              // parts do not add up to the bill is worse than no ledger.
              Text(
                _left == 0
                    ? 'Adds up to ${formatRupees(widget.row.paise)}.'
                    : _left > 0
                        ? '${formatRupees(_left)} still to account for.'
                        : '${formatRupees(-_left)} more than the bill.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _left == 0 ? Brand.good : Brand.danger,
                ),
              ),
              if (_left != 0)
                TextButton(
                  onPressed: _spreadRemainder,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Spread the rest evenly',
                      style: TextStyle(fontSize: 12)),
                ),
            ],

            if (widget.needsApproval) ...[
              const SizedBox(height: Brand.tight),
              const Text(
                'This changes what other people owe, so it goes to the trip '
                'owner to approve first.',
                style: Brand.caption,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: canSave ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Brand.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// Puts whatever is unaccounted for onto the people who already have an
  /// amount, so the last few rupees of an odd bill are one tap rather than
  /// arithmetic in somebody's head.
  void _spreadRemainder() {
    final current = _typed;
    final party =
        current.keys.isNotEmpty ? current.keys.toList() : _chosen.toList();
    if (party.isEmpty) return;

    final target = fairShares(widget.row.paise, party);
    setState(() {
      for (final uid in party) {
        _fields[uid]?.text = ((target[uid] ?? 0) / 100).toStringAsFixed(2);
      }
      // Anybody not in the party is not in this expense.
      for (final entry in _fields.entries) {
        if (!party.contains(entry.key)) entry.value.text = '';
      }
    });
  }
}
