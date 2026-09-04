import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../config/app_config.dart';
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
    final link = TripSync.shareLink(widget.tripId);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Link copied. Whoever opens it can ask to join and add spending.'),
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

    final ok = await _sync.addExpense(
      tripId: widget.tripId,
      paise: rupeesToPaise(rupees),
      note: note.text.trim().isEmpty ? 'Expense' : note.text.trim(),
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
              const SizedBox(height: 8),
              for (final row in approved) _row(row),
              const SizedBox(height: 10),
              _breakdown(approved),
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
                      'RS ${row.rupees.toStringAsFixed(2)}',
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

  Widget _row(TripExpense expense) {
    final mine = expense.by == _uid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.note, style: const TextStyle(fontSize: 13)),
                Text('${_nameOf(expense.by, expense.byName)} paid',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          Text('₹${expense.rupees.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          // Only your own rows are yours to remove; the rules enforce the
          // same thing, so a hidden button is not the only guard.
          if (mine)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.grey[500]),
              onPressed: () =>
                  _sync.removeExpense(widget.tripId, expense.id),
            ),
        ],
      ),
    );
  }

  Widget _totals(List<TripExpense> rows) {
    final total = rows.fold<int>(0, (sum, r) => sum + r.paise);
    final heads = _people.isEmpty ? 1 : _people.length;
    return Text(
      '₹${(total / 100).toStringAsFixed(2)} spent'
      '${_people.length > 1 ? '  ·  ₹${(total / 100 / heads).toStringAsFixed(2)} each' : ''}',
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
  String _nameOf(String uid, [String fallback = '']) {
    if (uid == _uid) return 'You';
    for (final person in _people) {
      if (person.uid == uid && person.name.isNotEmpty) return person.name;
    }
    if (fallback.isNotEmpty) return fallback;
    for (final person in _people) {
      if (person.uid == uid) return person.label;
    }
    return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
  }

  /// Money as people write it: whole where it is whole, grouped Indian-style.
  String _rupees(int paise) {
    final value = paise.abs() / 100;
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(2);
    final parts = text.split('.');
    var whole = parts[0];
    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      var rest = whole.substring(0, whole.length - 3);
      final groups = <String>[];
      while (rest.length > 2) {
        groups.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) groups.insert(0, rest);
      whole = '${groups.join(',')},$last3';
    }
    return '₹$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// The split, shown as columns.
  ///
  /// "arjun owes You 900" is a conclusion; this is the working behind it. A
  /// group splitting a bill wants to check the arithmetic, and a single
  /// sentence gives them nothing to check.
  ///
  /// Balance is what this person has put in beyond their share: positive means
  /// the group owes them, negative means they owe the group. Every balance
  /// sums to zero, which is the property that makes the settlement below it
  /// trustworthy.
  Widget _breakdown(List<TripExpense> rows) {
    if (_people.length < 2) return const SizedBox.shrink();

    final paid = <String, int>{};
    for (final row in rows) {
      paid[row.by] = (paid[row.by] ?? 0) + row.paise;
    }
    final total = rows.fold<int>(0, (sum, r) => sum + r.paise);
    final shares = fairShares(total, [for (final p in _people) p.uid]);

    // The people who paid most first: the ones owed money are the ones who
    // care most about this table being right.
    final people = [..._people]..sort((a, b) =>
        (paid[b.uid] ?? 0).compareTo(paid[a.uid] ?? 0));

    Widget cell(String text,
            {bool bold = false, Color? color, TextAlign align = TextAlign.right}) =>
        Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1.4),
          2: FlexColumnWidth(1.4),
          3: FlexColumnWidth(1.5),
        },
        children: [
          TableRow(
            children: [
              cell('Who', bold: true, align: TextAlign.left),
              cell('Paid', bold: true),
              cell('Share', bold: true),
              cell('Balance', bold: true),
            ],
          ),
          for (final person in people)
            TableRow(
              children: () {
                final put = paid[person.uid] ?? 0;
                final share = shares[person.uid] ?? 0;
                final balance = put - share;
                final color = balance == 0
                    ? Colors.grey.shade600
                    : balance > 0
                        ? Colors.green.shade700
                        : Colors.red.shade700;
                return [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: cell(_nameOf(person.uid), align: TextAlign.left),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: cell(_rupees(put)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: cell(_rupees(share)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: cell(
                      balance == 0
                          ? '—'
                          : '${balance > 0 ? '+' : '−'}${_rupees(balance)}',
                      bold: true,
                      color: color,
                    ),
                  ),
                ];
              }(),
            ),
        ],
      ),
    );
  }

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
                  '${name(debt.to)} ₹${debt.rupees.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}
