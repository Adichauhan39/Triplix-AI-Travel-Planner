import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/expense_sheet.dart';

import '../config/app_config.dart';
import '../config/features.dart';
import '../services/expense_words.dart';
import '../services/expense_columns.dart';
import 'expense_columns_view.dart';
import 'expense_insights_view.dart';
import '../models/trip_plan.dart';
import '../services/receipt_store.dart';
import 'receipt_sheet.dart';
import 'settle_up_sheet.dart';
import 'share_sheet.dart';
import 'split_picker.dart';
import 'trip_access_requests.dart';
import 'trip_changes_view.dart';
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

  /// The itinerary's days, so spending by date can be labelled "Day 2".
  List<DateTime> _tripDates = const [];

  /// Where the trip is to, for the sheet's title.
  String _tripName = '';

  bool _makingSheet = false;
  String _nickname = '';
  bool _loadingPeople = true;
  bool _isOwner = false;

  /// What has already been paid back.
  ///
  /// Held in state and listened to rather than fetched inside build: the
  /// settlement needs it alongside the expenses, and a second StreamBuilder
  /// wrapped round the whole ledger would rebuild the tree for a list that
  /// changes once a trip.
  List<TripPayment> _payments = const [];
  StreamSubscription<List<TripPayment>>? _paymentsSub;

  /// Which rows have a bill. Metadata only -- the photos themselves are in
  /// their own documents and are fetched when somebody asks to see one, so
  /// this listener costs nothing however many receipts a trip collects.
  final ReceiptStore _receiptStore = ReceiptStore();
  Map<String, ReceiptInfo> _receipts = const {};
  StreamSubscription<Map<String, ReceiptInfo>>? _receiptsSub;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _paymentsSub = _sync.payments(widget.tripId).listen((rows) {
      if (mounted) setState(() => _payments = rows);
    });
    _receiptsSub = _receiptStore.watch(widget.tripId).listen((found) {
      if (mounted) setState(() => _receipts = found);
    });
  }

  @override
  void dispose() {
    _paymentsSub?.cancel();
    _receiptsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    // The people with budget access, not plan access: those are two
    // different lists, and splitting by the plan's charged the wrong people.
    final people = await _sync.splitPeople(widget.tripId);
    final mine = await _sync.nickname(widget.tripId);
    final owner = await _sync.isOwnerOf(widget.tripId);
    final trip = await _sync.fetch(widget.tripId);
    if (!mounted) return;
    setState(() {
      _people = people;
      _nickname = mine;
      _isOwner = owner;
      _loadingPeople = false;
      _tripName = (trip?['destination'] ?? '').toString().split(',').first;
      _tripDates = [
        for (final day in ((trip?['days'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanDay.fromJson))
          day.date
      ];
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
              style: TextStyle(fontSize: 13, color: AppConfig.textSecondary),
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
    // Copies first, then offers where to send it. The old order -- sheet
    // first, copy only if there was no sheet -- left desktop users with
    // nothing on the clipboard, which is the one thing share must never do.
    await showShareSheet(
      context,
      link: TripSync.shareLink(widget.tripId, scope: TripScope.money),
      message: 'Come and split the costs of this trip with me on Triplix.',
      note: 'Whoever opens it signs in, tells you their name, and waits for you to approve them before anything they add counts.',
    );
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Widget _note(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConfig.cardColor,
          borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
          border: Border.all(color: AppConfig.borderColor),
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
            // Amount first, and focused.
            //
            // "What was it" was first and autofocused, so the number went into
            // the note, Amount stayed empty, and the only thing the dialog
            // could say was that the amount was not greater than zero. It was
            // telling the truth about a field nobody had been pointed at.
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                hintText: '500',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'What was it',
                hintText: 'Taxi to the zoo',
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

    // Named, so it is obvious which box is empty. "Enter an amount greater
    // than zero" is true and says nothing about where to type it.
    final typedAmount = amount.text.trim();
    final rupees = double.tryParse(typedAmount);
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(typedAmount.isEmpty
            ? 'Put the amount in the ₹ box at the top.'
            : '"$typedAmount" is not an amount I can read. Try 500.'),
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
            // Who has asked to join the MONEY, approved here rather than on
            // the trip page. Two separate queues: letting somebody help pick
            // restaurants is not the same decision as letting them into
            // everybody's accounts, and the owner should be looking at the
            // ledger when they make this one.
            if (_isOwner)
              TripAccessRequests(
                tripId: widget.tripId,
                scope: TripScope.money,
              ),
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
                if (kPaymentsEnabled)
                IconButton(
                  tooltip: 'Your UPI id, so people can pay you back',
                  icon: const Icon(Icons.account_balance_wallet_outlined,
                      size: 18),
                  onPressed: _askUpiId,
                ),
                // The sheet, for the end of the trip. Offered only once
                // there is something on it -- a PDF saying "nothing recorded"
                // is not a thing anybody wants to download.
                if (approved.isNotEmpty)
                  IconButton(
                    tooltip: 'Download the spending as a PDF',
                    icon: _makingSheet
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    onPressed:
                        _makingSheet ? null : () => _downloadSheet(approved),
                  ),
                IconButton(
                  tooltip: 'Share this trip and its spending',
                  icon: const Icon(Icons.ios_share, size: 18),
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
                  style: TextStyle(fontSize: 12, color: AppConfig.textTertiary),
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
                // The owner may change any row: they are the one holding
                // the whole group's receipts, and a ledger whose keeper
                // cannot fix somebody's typo stays wrong. Everybody else
                // corrects their own, which is what the rules allow -- a
                // button that Firestore would refuse is worse than no button.
                canChange: (row) => _isOwner || row.by == _uid,
                canDelete: (row) => _isOwner || row.by == _uid,
                onEdit: _editExpense,
                onDelete: _deleteExpense,
                onShared: _setShared,
                onSplitWith: _pickWhoShares,
                onReceipt: _receiptFor,
                hasReceipt: (row) => _receipts.containsKey(row.id),
              ),
              const SizedBox(height: 10),
              // Where it went, between the columns and the settlement: the
              // columns say who paid, this says on what, and neither pushes
              // the settlement -- the line people act on -- off the screen.
              ExpenseInsightsView(
                approved: approved,
                tripDates: _tripDates,
                nameOf: _nameOf,
              ),
              const SizedBox(height: 10),
              _settlement(approved, _payments),
              const SizedBox(height: 10),
              // Last, and folded: "who changed the cab to 5,000?" is a
              // question people only sometimes have, and it must not push
              // the settlement off the screen to answer it.
              TripChangesView(
                tripId: widget.tripId,
                nameOf: _nameOf,
                me: _uid,
              ),
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
        color: AppConfig.cardColor,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: AppConfig.borderColor),
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
            style: TextStyle(fontSize: 11, color: AppConfig.textSecondary),
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
                          approved: false,
                          label: row.note.isEmpty ? row.category : row.note),
                      child: const Text('No',
                          style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton(
                      onPressed: () => _sync.settleExpense(
                          tripId: widget.tripId,
                          expenseId: row.id,
                          approved: true,
                          label: row.note.isEmpty ? row.category : row.note),
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

    // Named, so it is obvious which box is empty. "Enter an amount greater
    // than zero" is true and says nothing about where to type it.
    final typedAmount = amount.text.trim();
    final rupees = double.tryParse(typedAmount);
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(typedAmount.isEmpty
            ? 'Put the amount in the ₹ box at the top.'
            : '"$typedAmount" is not an amount I can read. Try 500.'),
      ));
      return;
    }

    final tidy = await _confirmNote(
        note.text.trim().isEmpty ? 'Expense' : note.text.trim());
    if (!mounted || tidy == null) return;

    final ok = await _sync.editExpense(
      tripId: widget.tripId,
      expenseId: row.id,
      // So the history can say what it was as well as what it became.
      previousPaise: row.paise,
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
    final ok = await _sync.removeExpense(widget.tripId, row.id,
        label: '${row.note.isEmpty ? row.category : row.note} \u00B7 ${formatRupees(row.paise)}');
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('That could not be deleted. Check your connection.'),
    ));
  }

  /// Takes an expense out of the split, or puts it back.
  /// Attaches a bill to a row, or shows the one that is there.
  Future<void> _receiptFor(TripExpense row) async {
    final mine = _receipts[row.id];
    final has = mine != null;

    final choice = await askAboutReceipt(
      context,
      has: has,
      canRemove: has && (mine.by == _uid || _isOwner),
    );
    if (choice == null || !mounted) return;

    final title = row.note.isEmpty ? row.category : row.note;

    switch (choice) {
      case ReceiptAction.view:
        await showReceipt(
          context,
          store: _receiptStore,
          tripId: widget.tripId,
          expenseId: row.id,
          title: title,
        );
      case ReceiptAction.remove:
        final ok = await _receiptStore.remove(
            tripId: widget.tripId, expenseId: row.id);
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That could not be removed.'),
          ));
        }
      case ReceiptAction.camera:
      case ReceiptAction.gallery:
        // Said before the wait, because shrinking a camera photo takes a
        // second or two and a screen that does nothing reads as broken.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saving the bill...'),
          duration: Duration(seconds: 2),
        ));
        final problem = await _receiptStore.attach(
          tripId: widget.tripId,
          expenseId: row.id,
          fromCamera: choice == ReceiptAction.camera,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(problem ?? 'Bill attached.'),
        ));
    }
  }

  /// Closes a debt: pays it, and records what was paid.
  Future<void> _settle(Debt debt) async {
    final payee = _people.firstWhere(
      (p) => p.uid == debt.to,
      orElse: () => TripPerson(uid: debt.to, name: '', email: ''),
    );

    final result = await showSettleUpSheet(
      context,
      debt: debt,
      fromName: _nameOf(debt.from),
      toName: _nameOf(debt.to),
      toUpiId: payee.upi,
      iAmPayer: debt.from == _uid,
      tripLabel: 'Triplix trip',
    );
    if (result == null || !mounted) return;

    final ok = await _sync.recordPayment(
      tripId: widget.tripId,
      from: debt.from,
      to: debt.to,
      paise: result.paise,
      method: result.method,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Recorded: ${_nameOf(debt.from)} paid ${_nameOf(debt.to)} '
              '${formatRupees(result.paise)}.'
          : 'That did not save. Check your connection.'),
    ));
  }

  /// Takes back a payment that did not happen.
  Future<void> _unpay(TripPayment payment) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this payment?'),
        content: Text(
          '${_nameOf(payment.from)} paying ${_nameOf(payment.to)} '
          '${formatRupees(payment.paise)} will go back to being owed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _sync.removePayment(widget.tripId, payment.id);
  }

  /// Where somebody puts their own UPI id, so the people who owe them can pay
  /// in one tap instead of asking for their number.
  Future<void> _askUpiId() async {
    final controller = TextEditingController(
      text: _people
          .firstWhere(
            (p) => p.uid == _uid,
            orElse: () => const TripPerson(uid: '', name: '', email: ''),
          )
          .upi,
    );

    final upi = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your UPI id'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shown to whoever owes you, so they can pay you from the '
              'settlement. Nothing is taken from your account -- this only '
              'fills in their payment screen.',
              style: TextStyle(fontSize: 13, color: AppConfig.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'yourname@okhdfcbank',
                labelText: 'UPI id',
              ),
              onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (upi == null || !mounted) return;

    // An id without an @ is a typo, and one saved wrong sends somebody's
    // money to the wrong place.
    if (upi.isNotEmpty && !upi.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A UPI id looks like name@bank. Check it and try '
            'again.'),
      ));
      return;
    }

    final ok = await _sync.setUpiId(tripId: widget.tripId, upi: upi);
    if (!mounted) return;
    if (ok) _loadPeople();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (upi.isEmpty
              ? 'UPI id removed.'
              : 'Saved. People who owe you can now pay you in one tap.')
          : 'That did not save. Check your connection.'),
    ));
  }

  /// Makes the spending sheet and hands it over.
  ///
  /// Built on the device, from the same columns and settlement the screen
  /// shows, so it works with no signal and cannot disagree with the app. On a
  /// phone it opens the share sheet; on a laptop the browser saves the file.
  Future<void> _downloadSheet(List<TripExpense> approved) async {
    setState(() => _makingSheet = true);
    try {
      final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');

      final bytes = await buildExpenseSheet(
        tripName: _tripName,
        approved: approved,
        // Built with nobody as "me": the sheet goes to the whole group.
        columns: buildExpenseColumns(
            approved: approved, people: _people, me: null),
        debts: settlementFor(
          approved: approved,
          people: [for (final p in _people) p.uid],
          repaid: [
            for (final payment in _payments)
              Repayment(
                  from: payment.from, to: payment.to, paise: payment.paise)
          ],
        ),
        nameOf: (uid) => uid == _uid
            ? (_nickname.isNotEmpty ? _nickname : _nameOf(uid))
            : _nameOf(uid),
        regularFont: regular.buffer.asUint8List(),
        boldFont: bold.buffer.asUint8List(),
      );

      final safe = _tripName.isEmpty
          ? 'trip'
          : _tripName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await Share.shareXFiles(
        [
          XFile.fromData(bytes,
              name: 'triplix-$safe-spending.pdf',
              mimeType: 'application/pdf')
        ],
        text: 'Our spending on the $_tripName trip',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('The sheet could not be made. ($e)'),
      ));
    } finally {
      if (mounted) setState(() => _makingSheet = false);
    }
  }

  /// Asks who this expense is divided between.
  Future<void> _pickWhoShares(TripExpense row) async {
    final chosen = await askWhoShares(
      context,
      row: row,
      people: _people,
      me: _uid,
      needsApproval: !_isOwner,
    );
    // null is "cancelled", an empty answer is "everyone, equally". Treating
    // them alike would silently put a row back into the whole group's split
    // whenever somebody closed the dialog.
    if (chosen == null || !mounted) return;

    // Exact amounts and a list of people are two ways of saying the same
    // thing, so exactly one of them is written and the other is cleared.
    final ok = chosen.isExact
        ? await _sync.setShares(
            tripId: widget.tripId,
            expenseId: row.id,
            shares: chosen.shares,
            label: row.note.isEmpty ? row.category : row.note,
          )
        : await _sync.setSharedWith(
            tripId: widget.tripId,
            expenseId: row.id,
            people: chosen.people,
            label: row.note.isEmpty ? row.category : row.note,
          );
    if (!mounted) return;

    final waiting = _isOwner ? '' : ' Waiting for the owner to approve.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (chosen.isExact
              ? 'Saved the exact amounts.$waiting'
              : chosen.people.isEmpty
                  ? 'Back to everyone.$waiting'
                  : 'Split between ${chosen.people.length}.$waiting')
          : 'That did not save. Check your connection.'),
    ));
  }

  Future<void> _setShared(TripExpense row, bool shared) async {
    final ok = await _sync.setShared(
      tripId: widget.tripId,
      expenseId: row.id,
      shared: shared,
      label: row.note.isEmpty ? row.category : row.note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (shared
              ? 'Back in the split.'
              : 'Taken out of the split. Nobody else owes a share of it.')
          : 'That could not be saved. Check your connection.'),
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
                style: TextStyle(fontSize: 13, color: AppConfig.textSecondary)),
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
    // Only the shared rows. This used to add everything, so a personal
    // expense inflated both the total and the "each" beneath it, and the
    // columns two lines down disagreed with their own heading.
    final total = sharedTotal(rows);
    final personal = personalTotal(rows);
    final heads = _people.isEmpty ? 1 : _people.length;
    return Text(
      '${formatRupees(total)} shared'
      '${_people.length > 1 ? '  ·  ${formatRupees(total ~/ heads)} each' : ''}'
      '${personal > 0 ? '  ·  ${formatRupees(personal)} just theirs' : ''}',
      style: TextStyle(fontSize: 12, color: AppConfig.textSecondary),
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
  Widget _settlement(List<TripExpense> rows, List<TripPayment> repaid) {
    if (_people.length < 2) {
      return Text(
        'Invite the people you are travelling with and this will split '
        'what everyone paid.',
        style: TextStyle(fontSize: 11, color: AppConfig.textTertiary),
      );
    }

    // The one shared calculation, so this line, the shared link and the
    // downloaded sheet cannot give three answers to one question.
    final debts = settlementFor(
      approved: rows,
      people: [for (final p in _people) p.uid],
      repaid: [
        for (final payment in repaid)
          Repayment(from: payment.from, to: payment.to, paise: payment.paise)
      ],
    );

    String name(String uid) => _nameOf(uid);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConfig.cardColor,
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        border: Border.all(color: AppConfig.borderColor),
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
                style: TextStyle(fontSize: 12, color: AppConfig.textSecondary))
          else
            for (final debt in debts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${name(debt.from)} '
                        '${debt.from == _uid ? 'owe' : 'owes'} '
                        '${name(debt.to)} ${formatRupees(debt.paise)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    // Offered to the two people in it, and to the owner, who
                    // is usually the one holding the cash. Anyone else would
                    // be recording a payment they know nothing about -- and
                    // the rules would refuse it.
                    if (kPaymentsEnabled &&
                        (debt.from == _uid || debt.to == _uid || _isOwner))
                      TextButton(
                        onPressed: () => _settle(debt),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                        ),
                        child: Text(
                            debt.from == _uid ? 'Pay' : 'Settle up',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),

          // What has already been paid back, so the settlement shrinking is
          // explained rather than mysterious.
          if (repaid.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Text('Already paid back',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppConfig.textSecondary)),
            for (final payment in repaid)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 13, color: AppConfig.successColor),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${name(payment.from)} paid ${name(payment.to)} '
                        '${formatRupees(payment.paise)}'
                        '${payment.method == 'upi' ? ' by UPI' : ''}',
                        style: TextStyle(
                            fontSize: 11, color: AppConfig.textSecondary),
                      ),
                    ),
                    // Removable, not editable: a payment either happened or
                    // it did not, and only whoever recorded it or the owner
                    // may take it back.
                    if (payment.by == _uid || _isOwner)
                      IconButton(
                        tooltip: 'This did not happen -- remove it',
                        icon: const Icon(Icons.close, size: 13),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        onPressed: () => _unpay(payment),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
