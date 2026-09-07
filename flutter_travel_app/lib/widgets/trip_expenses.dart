import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/expense_words.dart';
import '../services/expense_columns.dart';
import '../services/share_link.dart' as sharing;
import 'expense_columns_view.dart';
import '../services/settle_up.dart';
import '../services/trip_sync.dart';

/// What everyone on a trip has spent, and who owes whom.
///
/// Each traveller adds their own rows and they appear for everybody at once.
/// The settlement underneath is the thing people actually want at the end of a
/// trip -- a list of expenses is bookkeeping, "Priya owes you 950" is the
/// answer.
class TripExpenses extends StatefulWidget {
  const TripExpenses({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripExpenses> createState() => _TripExpensesState();
}

class _TripExpensesState extends State<TripExpenses> {
  final TripSync _sync = TripSync();

  List<TripPerson> _people = const [];
  String _nickname = '';
  bool _loadingPeople = true;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    final people = await _sync.members(widget.tripId);
    final mine = await _sync.nickname(widget.tripId);
    final owner = await _sync.isOwnerOf(widget.tripId);
    if (!mounted) return;
    setState(() {
      _people = people;
      _nickname = mine;
      _isOwner = owner;
      _loadingPeople = false;
    });
    // Asked once, and only when there is somebody to be told apart from.
    if (mine.isEmpty && people.length > 1) _askNickname();
  }

  /// Asks what this person wants to be called on this trip.
  Future<void> _askNickname() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What should we call you?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shown beside what you pay for, so everyone can tell whose '
              'is whose.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Adi'),
              onSubmitted: (v) =>
                  Navigator.pop(dialogContext, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    await _sync.setNickname(tripId: widget.tripId, nickname: name);
    if (!mounted) return;
    setState(() => _nickname = name);
    _loadPeople();
  }

  /// Copies the trip link. One trip, one link -- sharing the budget and
  /// sharing the plan are the same act, because they describe one journey.
  Future<void> _shareLink() async {
    // Straight to the share sheet, with the clipboard as the fallback.
    // Copying left people to go and find WhatsApp themselves; on a phone,
    // which is where these get sent, the sheet is one tap to the right
    // conversation.
    final outcome = await sharing.shareLink(
      TripSync.shareLink(widget.tripId),
      message: 'Come and split the costs of this trip with me on Triplix.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sharing.shareMessageFor(
        outcome,
        copied: 'Link copied. Whoever opens it can ask to join and add '
            'spending.',
      )),
    ));
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Widget _note(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(message, style: const TextStyle(fontSize: 12)),
      );

  Future<void> _add() async {
    final amount = TextEditingController();
    final note = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What did you pay for?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: note,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'What was it',
                hintText: 'Taxi to the zoo',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
              onSubmitted: (_) => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted || saved != true) return;

    final rupees = double.tryParse(amount.text.trim());
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter an amount greater than zero.'),
      ));
      return;
    }

    // Spelling checked before it lands in a list several people read. Offered
    // rather than applied: it is somebody's money, and a note relabelled
    // behind their back is worse than the typo was.
    final typed = note.text.trim().isEmpty ? 'Expense' : note.text.trim();
    final tidy = await _confirmNote(typed);
    if (!mounted || tidy == null) return;

    final ok = await _sync.addExpense(
      tripId: widget.tripId,
      paise: rupeesToPaise(rupees),
      note: tidy.note,
      category: tidy.category,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('That could not be saved. Check your connection.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Says why rather than vanishing. An empty panel where a shared ledger
    // should be reads as a broken feature, and the two reasons it can be
    // empty have completely different fixes.
    if (!_sync.canShare) {
      return _note('Sign in to share spending with the people you are '
          'travelling with.');
    }
    if (widget.tripId.isEmpty) {
      return _note('Plan a trip first. Shared spending belongs to a trip, so '
          'there is nothing to share yet.');
    }

    return StreamBuilder<List<TripExpense>>(
      stream: _sync.expenses(widget.tripId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <TripExpense>[];
        // Rejected rows are simply gone from view: keeping them would leave
        // an argument on the screen after it has been settled.
        final approved = [for (final r in rows) if (r.isApproved) r];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Shared spending',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: _nickname.isEmpty
                      ? 'Set your name'
                      : 'You are "$_nickname"',
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  onPressed: _askNickname,
                ),
                IconButton(
                  tooltip: 'Copy the link to share this trip and its spending',
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: _shareLink,
                ),
                TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  _loadingPeople
                      ? 'Loading…'
                      : 'Nothing spent yet. Whoever pays adds it here, and '
                          'everyone sees it.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              )
            else ...[
              // Waiting first: it is the only part that needs somebody to do
              // something.
              if (rows.any((r) => r.isPending)) ...[
                _pendingBlock([for (final r in rows) if (r.isPending) r]),
                const SizedBox(height: 12),
              ],
              _totals(approved),
              const SizedBox(height: 10),
              // One column per person, their expenses underneath, ending in
              // what they paid, owe and are up or down by.
              //
              // This replaces a flat list plus a separate paid/share/balance
              // table. A group reads a ledger by person -- working out what
              // any one of them spent meant scanning every row and adding up
              // -- and having "Paid" in two places on one screen invited
              // people to check one against the other.
              ExpenseColumnsView(
                expenses: approved,
                people: _people,
                me: _uid,
                // The rules allow the row's author or the trip's owner, so
                // the menu is offered to exactly those two.
                canChange: (row) => row.by == _uid || _isOwner,
                onEdit: _editExpense,
                onDelete: _deleteExpense,
              ),
              const SizedBox(height: 10),
              _settlement(approved),
            ],
          ],
        );
      },
    );
  }

  /// Expenses waiting on the trip owner.
  ///
  /// Shown to everybody, not just the owner: somebody who has just added a
  /// row needs to see that it landed and is waiting, or they will add it
  /// again.
  Widget _pendingBlock(List<TripExpense> pending) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isOwner
                ? (pending.length == 1
                    ? '1 expense is waiting for you'
                    : '${pending.length} expenses are waiting for you')
                : 'Waiting for the trip owner',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _isOwner
                ? 'Nothing counts towards the split until you accept it.'
                : 'These do not count towards the split yet.',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          for (final row in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${row.note}  ·  ${_nameOf(row.by, row.byName)} paid '
                      '${formatRupees(row.paise)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_isOwner) ...[
                    TextButton(
                      onPressed: () => _sync.settleExpense(
                          tripId: widget.tripId,
                          expenseId: row.id,
                          approved: false),
                      child: const Text('No',
                          style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton(
                      onPressed: () => _sync.settleExpense(
                          tripId: widget.tripId,
                          expenseId: row.id,
                          approved: true),
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
  }

  /// Corrects an expense. Yours if you wrote it; anything if you own the trip.
  Future<void> _editExpense(TripExpense row) async {
    final amount =
        TextEditingController(text: (row.paise / 100).toStringAsFixed(2));
    final note = TextEditingController(text: row.note);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Correct this expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: note,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'What was it'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount', prefixText: '₹ '),
              onSubmitted: (_) => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || saved != true) return;

    final rupees = double.tryParse(amount.text.trim());
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter an amount greater than zero.'),
      ));
      return;
    }

    final tidy = await _confirmNote(
        note.text.trim().isEmpty ? 'Expense' : note.text.trim());
    if (!mounted || tidy == null) return;

    final ok = await _sync.editExpense(
      tripId: widget.tripId,
      expenseId: row.id,
      paise: rupeesToPaise(rupees),
      note: tidy.note,
      category: tidy.category,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (_isOwner
              ? 'Updated.'
              : 'Updated. A changed amount goes back to the owner.')
          : 'That could not be saved. Check your connection.'),
    ));
  }

  /// Removes an expense, after asking.
  ///
  /// Confirmed because it is other people's arithmetic too: a row vanishing
  /// changes what everybody owes, and there is no undo.
  Future<void> _deleteExpense(TripExpense row) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text(
            'This changes what everyone owes, and it cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    final ok = await _sync.removeExpense(widget.tripId, row.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('That could not be deleted. Check your connection.'),
    ));
  }

  /// Offers a spelling correction before an expense is filed.
  ///
  /// Returns the note to use, or null if the person backed out. Corrected on
  /// the device against a small vocabulary rather than by asking a model: an
  /// expense note is a few words from a stable list, so this settles it
  /// instantly, offline and for nothing, where a model call would cost a
  /// request each time and still have to be checked.
  Future<TidyNote?> _confirmNote(String raw) async {
    final tidy = tidyNote(raw);
    if (!tidy.corrected) return tidy;

    final use = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Did you mean?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You typed "${raw.trim()}".',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.check, size: 16),
              const SizedBox(width: 8),
              Text(tidy.note,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
        actions: [
          TextButton(
            // Their words, kept. Somebody's own shorthand is not a mistake.
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep "${raw.trim()}"'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    if (use == null) return null;
    return use
        ? tidy
        : TidyNote(
            note: raw.trim(), category: tidy.category, corrected: false);
  }

  Widget _totals(List<TripExpense> rows) {
    final total = rows.fold<int>(0, (sum, r) => sum + r.paise);
    final heads = _people.isEmpty ? 1 : _people.length;
    return Text(
      '${formatRupees(total)} spent'
      '${_people.length > 1 ? '  ·  ${formatRupees(total ~/ heads)} each' : ''}',
      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
    );
  }

  /// One name per person, everywhere on this screen.
  ///
  /// TripExpense.label falls back to `by_name` -- the Google account name
  /// copied onto the row when it was written. The settlement used the trip
  /// profile instead, so the same person read as "Aditya Chauhan paid" on one
  /// line and "arjun owes You" three lines below. The nickname they chose for
  /// this trip wins: it is what the group calls them, and it is what the owner
  /// approved them under.
  String _nameOf(String uid, [String fallback = '']) => displayName(
        uid,
        me: _uid,
        people: _people,
        expenses: fallback.isEmpty
            ? const []
            : [
                TripExpense(
                  id: '',
                  by: uid,
                  byName: fallback,
                  paise: 0,
                  note: '',
                  category: '',
                  at: DateTime.now(),
                )
              ],
      );

  /// Who owes whom, or nothing at all when it is already even.
  Widget _settlement(List<TripExpense> rows) {
    if (_people.length < 2) {
      return Text(
        'Invite the people you are travelling with and this will split '
        'what everyone paid.',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      );
    }

    final paid = <String, int>{};
    for (final row in rows) {
      paid[row.by] = (paid[row.by] ?? 0) + row.paise;
    }
    final debts = settleUp(
      paidPaise: paid,
      people: [for (final p in _people) p.uid],
    );

    String name(String uid) => _nameOf(uid);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Settling up',
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (debts.isEmpty)
            Text('Everyone has paid their share.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]))
          else
            for (final debt in debts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${name(debt.from)} '
                  '${debt.from == _uid ? 'owe' : 'owes'} '
                  '${name(debt.to)} ${formatRupees(debt.paise)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}
