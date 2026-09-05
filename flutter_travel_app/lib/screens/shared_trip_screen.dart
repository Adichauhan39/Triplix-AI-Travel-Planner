import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../services/auth_service.dart';
import '../services/python_adk_service.dart';
import '../services/expense_words.dart';
import '../services/plan_diff.dart';
import '../services/settle_up.dart';
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

class _SharedTripScreenState extends State<SharedTripScreen>
    with SingleTickerProviderStateMixin {
  final TripSync _sync = TripSync();

  /// Plan and Money. Built once here rather than by a DefaultTabController,
  /// because the bar lives in the AppBar and the view lives in the body, and
  /// they have to be the same controller.
  late final TabController _tabs = TabController(length: 2, vsync: this);
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

  @override
  void dispose() {
    _tabs.dispose();
    _request.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Asked before fetching, not after it fails.
    //
    // The rule is `allow get: if signedIn()`, so a signed-out read is rejected
    // by the database and comes back indistinguishable from a deleted trip --
    // which is what this screen used to tell people their link was. Nobody
    // signed out can see a trip, so ask them in first and say why.
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() {
        _loading = false;
        _trip = null;
        _error = null;
      });
      return;
    }

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
    if (data == null) return;
    _loadSummaries(data);
    await _ensureNickname();
  }

  /// Whether this visit has already put the name question on screen. Without
  /// it a rebuild while the dialog is open would stack a second one behind it.
  bool _nicknameAsked = false;

  /// Takes a name the moment somebody arrives, before they ask for anything.
  ///
  /// The owner is about to be shown a row and asked to approve it. A row that
  /// says "Adi · adi@gmail.com" is a decision they can make; a row that says
  /// "kJ2xQ8fP…" is not. Asked on arrival rather than at the point of
  /// requesting access, because plenty of people open a link, read the trip
  /// and add what they paid without ever tapping "Ask to join".
  Future<void> _ensureNickname() async {
    if (_nicknameAsked || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // The owner is asked too.
    //
    // This used to skip them, reasoning that somebody who named the trip need
    // not introduce themselves to it. That had it backwards: a name is not for
    // its owner, it is for everybody else. The owner reads their own rows as
    // "You", while every friend reads "Rahul owes <owner> 600" -- and with no
    // profiles entry that rendered a truncated uid to the whole group. It also
    // meant the question never appeared once while testing with your own link.

    final existing = await _sync.nickname(widget.tripId);
    if (existing.isNotEmpty || !mounted) return;

    _nicknameAsked = true;
    final chosen = await _askNickname();
    if (chosen == null || !mounted) return;

    // Falls back to the Google account name so the field is never left empty:
    // an empty name means this runs again on the next visit, and means the
    // owner is back to approving a uid.
    final account =
        (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    final name = chosen.isNotEmpty ? chosen : account;
    if (name.isEmpty) return;

    await _sync.setNickname(tripId: widget.tripId, nickname: name);
    if (mounted) setState(() {});
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

    // Checked against real places before it is sent.
    //
    // A typed name goes to the owner and, if taken, into the plan -- where a
    // misspelling has no coordinates, so it anchors no route and finds no
    // photo. Resolving here means the owner approves a real place rather than
    // somebody's typing.
    final resolved = await _resolveName(title);
    if (!mounted || resolved == null) return;

    final ok = await _sync.proposeAdd(
      tripId: widget.tripId,
      dayIndex: dayIndex,
      title: resolved,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Suggested. The trip owner decides whether it goes in.'
          : 'That suggestion could not be sent.'),
    ));
  }

  /// Turns what somebody typed into a place that exists, asking them first.
  ///
  /// Returns the name to use, or null if they backed out. Falls back to the
  /// typed text whenever the lookup finds nothing or fails: a guest with no
  /// connection should still be able to suggest "the fort by the lake" and
  /// have the owner work out what they meant. Being unable to spell it is not
  /// a reason to lose the suggestion.
  Future<String?> _resolveName(String typed) async {
    final city = (_trip?['destination'] ?? '').toString();
    if (city.isEmpty) return typed;

    // A spinner, because this is a network round trip and the dialog has just
    // closed -- without it the tap looks ignored.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    // Null means the call failed, which is not the same as "no such place" --
    // both fall back to the typed text rather than losing the suggestion.
    final matches =
        await _adk.suggestPlaces(city: city, text: typed) ?? const [];
    if (!mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();

    final names = [
      for (final match in matches) (match['name'] ?? '').toString().trim(),
    ]..removeWhere((n) => n.isEmpty);
    if (names.isEmpty) return typed;

    // Already right: an exact match needs no confirming.
    if (names.first.toLowerCase() == typed.toLowerCase()) return typed;

    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Did you mean?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You typed "$typed".',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            for (final name in names.take(4))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text(name, style: const TextStyle(fontSize: 13)),
                onTap: () => Navigator.pop(dialogContext, name),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            // Their words, kept. The list is a suggestion, not a gate.
            onPressed: () => Navigator.pop(dialogContext, typed),
            child: Text('Use "$typed"'),
          ),
        ],
      ),
    );
  }

  /// Asks what to be called, then asks the owner for access.
  ///
  /// The name comes first because it is what the owner sees when deciding,
  /// and what every expense will be filed under afterwards. A list of Google
  /// account names is not how a group of friends refers to itself.
  Future<String?> _askNickname() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What should we call you?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shown to the trip owner, and beside anything you pay for.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Adi'),
              onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Use my account name'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAccess() async {
    // Already introduced themselves on the way in -- asking twice reads as the
    // app having forgotten.
    var nickname = await _sync.nickname(widget.tripId);
    if (!mounted) return;
    if (nickname.isEmpty) {
      final asked = await _askNickname();
      // Dismissed rather than answered: they have not asked for anything yet.
      if (!mounted || asked == null) return;
      nickname = asked;
    }

    setState(() => _asking = true);
    final ok = await _sync.requestAccess(widget.tripId, nickname: nickname);
    if (!mounted) return;
    setState(() => _asking = false);
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Asked to join. Once the owner says yes, you can add '
            'what you paid.'),
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

    final ready = !_loading &&
        FirebaseAuth.instance.currentUser != null &&
        _error == null &&
        data != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(where.isEmpty ? 'Shared trip' : 'Trip to $where'),
        centerTitle: true,
        // Only once there is something to switch between. A tab bar over an
        // error or a sign-in prompt offers a choice that leads nowhere.
        bottom: ready
            ? TabBar(
                controller: _tabs,
                labelColor: AppConfig.primaryColor,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: AppConfig.primaryColor,
                tabs: const [
                  Tab(icon: Icon(Icons.map_outlined), text: 'Plan'),
                  Tab(
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      text: 'Money'),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FirebaseAuth.instance.currentUser == null
              ? _signInGate()
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text(_error!, textAlign: TextAlign.center)),
                    )
                  : StreamBuilder<List<TripProposal>>(
                      stream: _sync.openProposals(widget.tripId),
                      builder: (context, snapshot) {
                        // Everyone sees the same trip. Suggestions sit on top
                        // of it, marked, until the owner takes them -- so a
                        // contributor can see what they asked for without it
                        // pretending to be part of the plan.
                        final pending =
                            snapshot.data ?? const <TripProposal>[];
                        return Column(
                          children: [
                            // Above the tabs, not inside one. What you are
                            // allowed to do applies to both halves, and
                            // repeating it in each would be two banners
                            // saying the same thing.
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _accessBanner(access),
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _tabs,
                                children: [
                                  Column(
                                    children: [
                                      Expanded(
                                        child: ListView(
                                          padding: const EdgeInsets.all(16),
                                          children: [
                                            if (pending.isNotEmpty) ...[
                                              _pendingNote(pending.length),
                                              const SizedBox(height: 16),
                                            ],
                                            ..._days(data!, pending),
                                          ],
                                        ),
                                      ),
                                      // Under the plan, not the ledger: it
                                      // edits days, and the same box under
                                      // the money would be answering a
                                      // question nobody asked there.
                                      _requestBar(),
                                    ],
                                  ),
                                  ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [_spending(access)],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared spending
  // ---------------------------------------------------------------------------

  /// Rupees, as people write them. Whole where it is whole: "1,400" reads as
  /// money, "1400.00" reads as a database column.
  String _money(int paise) {
    final rupees = paise / 100;
    final text = rupees == rupees.roundToDouble()
        ? rupees.round().toString()
        : rupees.toStringAsFixed(2);
    // Indian grouping: 1,40,000 rather than 140,000.
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

  /// Who a uid is, on this trip.
  ///
  /// Prefers the nickname they chose here over their Google name, because that
  /// is the name the rest of the group actually uses. Falls back to a short
  /// uid rather than "Unknown" so two unnamed people stay apart.
  String _nameFor(String uid, List<TripExpense> rows) {
    if (uid == FirebaseAuth.instance.currentUser?.uid) return 'You';
    final profiles = (_trip?['profiles'] as Map?) ?? const {};
    final chosen = ((profiles[uid] as Map?)?['name'] ?? '').toString().trim();
    if (chosen.isNotEmpty) return chosen;
    for (final row in rows) {
      if (row.by == uid && row.byName.isNotEmpty) return row.byName;
    }
    return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
  }

  /// Everyone the bill is divided between: the approved members of the trip.
  ///
  /// Not "everyone who paid" -- a member who has paid nothing still owes their
  /// share, and leaving them out would quietly hand their part to the others.
  List<String> get _people {
    final members = (_trip?['members'] as List?) ?? const [];
    final people = [for (final m in members) m.toString()]
      ..removeWhere((m) => m.isEmpty);
    return people;
  }

  Widget _spending(TripAccess access) {
    final canAdd = access == TripAccess.owner || access == TripAccess.editor;
    final isOwner = access == TripAccess.owner;
    final me = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<TripExpense>>(
      stream: _sync.expenses(widget.tripId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <TripExpense>[];
        // Only approved money moves. A pending row is a claim, and counting it
        // in the settlement before the owner has seen it is exactly what the
        // approval step exists to prevent.
        final approved = [for (final r in rows) if (r.isApproved) r];
        final waiting = [for (final r in rows) if (r.isPending) r];

        final paid = <String, int>{};
        for (final row in approved) {
          paid[row.by] = (paid[row.by] ?? 0) + row.paise;
        }
        final people = _people;
        final total = approved.fold<int>(0, (sum, r) => sum + r.paise);
        final debts = people.length > 1
            ? settleUp(paidPaise: paid, people: people)
            : const <Debt>[];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Shared spending',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (canAdd)
                    TextButton.icon(
                      onPressed: _addExpense,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                ],
              ),
              if (total > 0)
                Text(
                  people.length > 1
                      ? '${_money(total)} so far · '
                          '${_money(total ~/ people.length)} each'
                      : '${_money(total)} so far',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                )
              else
                Text(
                  canAdd
                      ? 'Nothing yet. Add what you paid and it is split '
                          'between everyone on the trip.'
                      : 'Nothing yet.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),

              // Who owes whom. The one line everybody actually opens this for.
              if (debts.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final debt in debts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _owingLine(debt, rows, me),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],

              // The owner's queue. Shown to the owner only: to everybody else
              // a pending row of their own is already visible below, marked.
              if (isOwner && waiting.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Waiting for you to approve',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade800)),
                const SizedBox(height: 4),
                for (final row in waiting) _awaitingRow(row, rows),
              ],

              if (rows.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 8),
                for (final row in rows)
                  if (!(isOwner && row.isPending)) _expenseRow(row, rows, me),
              ],

              // The way in, put where the money is.
              //
              // Adding an expense needs the owner's approval, and the only
              // route to asking for it was a button called "Ask to edit" in
              // the banner above -- which is about the plan. Somebody sent
              // this link to split a bill never reads that as the way to do
              // it. Same request underneath; asked where they are standing.
              if (!canAdd && access != TripAccess.signedOut) ...[
                const SizedBox(height: 12),
                if (access == TripAccess.pending)
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 15, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'You have asked to join. Once the owner says yes, '
                          'you can add what you paid.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _asking ? null : _requestAccess,
                      icon: _asking
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.group_add, size: 18),
                      label: Text(_asking
                          ? 'Asking…'
                          : 'Ask to join and add my spending'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// "Priya owes you 600" -- phrased from the reader's side where they are in
  /// it, because "Priya owes Aditya" makes the reader work out whether that is
  /// them.
  String _owingLine(Debt debt, List<TripExpense> rows, String? me) {
    final from = _nameFor(debt.from, rows);
    final to = _nameFor(debt.to, rows);
    final amount = _money(debt.paise);
    if (debt.from == me) return 'You owe $to $amount';
    if (debt.to == me) return '$from owes you $amount';
    return '$from owes $to $amount';
  }

  Widget _awaitingRow(TripExpense row, List<TripExpense> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_nameFor(row.by, rows)} · '
              '${row.note.isEmpty ? row.category : row.note}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(_money(row.paise),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Approve',
            icon: const Icon(Icons.check, size: 18, color: Colors.green),
            onPressed: () => _settle(row, true),
          ),
          IconButton(
            tooltip: 'Reject',
            icon: const Icon(Icons.close, size: 18, color: Colors.red),
            onPressed: () => _settle(row, false),
          ),
        ],
      ),
    );
  }

  Widget _expenseRow(TripExpense row, List<TripExpense> rows, String? me) {
    final rejected = row.status == 'rejected';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_nameFor(row.by, rows)} · '
              '${row.note.isEmpty ? row.category : row.note}',
              style: TextStyle(
                fontSize: 13,
                color: rejected ? Colors.grey : null,
                decoration: rejected ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (row.isPending)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('waiting',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange.shade800)),
            ),
          Text(
            _money(row.paise),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: rejected ? Colors.grey : null,
              decoration: rejected ? TextDecoration.lineThrough : null,
            ),
          ),
          if (_expenseMenu(row) case final menu?) menu,
        ],
      ),
    );
  }

  Future<void> _settle(TripExpense row, bool approved) async {
    final ok = await _sync.settleExpense(
      tripId: widget.tripId,
      expenseId: row.id,
      approved: approved,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('That could not be saved. Check your connection.'),
    ));
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
          ? ((_access == TripAccess.owner)
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
        content: Text(
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

  /// The edit/delete menu, shown only to people the rules would actually let
  /// through: the row's author, or the trip's owner. Offering it to anybody
  /// else would produce a button that fails.
  Widget? _expenseMenu(TripExpense row) {
    final mine = row.by == FirebaseAuth.instance.currentUser?.uid;
    if (!mine && !(_access == TripAccess.owner)) return null;
    return PopupMenuButton<String>(
      tooltip: 'Change this expense',
      icon: Icon(Icons.more_vert, size: 16, color: Colors.grey.shade600),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 17),
            SizedBox(width: 10),
            Text('Edit'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 17, color: Colors.red),
            SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
      onSelected: (choice) =>
          choice == 'edit' ? _editExpense(row) : _deleteExpense(row),
    );
  }

  /// Offers a spelling correction before an expense is filed.
  ///
  /// Returns the note to use. Corrected on the device against a small
  /// vocabulary rather than by asking a model: an expense note is a few words
  /// from a stable list, so this settles it instantly, offline and for
  /// nothing, where a model call would cost a request each time and still
  /// need checking.
  Future<TidyNote?> _confirmNote(String raw) async {
    final tidy = tidyNote(raw);
    if (!tidy.corrected) return tidy;

    final keep = await showDialog<bool>(
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
    if (keep == null) return null; // dismissed: file nothing
    return keep
        ? tidy
        : TidyNote(
            note: raw.trim(), category: tidy.category, corrected: false);
  }

  /// Adds what this person paid.
  ///
  /// Rupees in, paise stored: money is kept as whole paise everywhere so a
  /// three-way split of 100 does not lose a third of a paisa per person and
  /// leave the settlement failing to balance.
  Future<void> _addExpense() async {
    final amount = TextEditingController();
    final note = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What did you pay for?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'What for?',
                hintText: 'Dinner, taxi, tickets…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (added != true || !mounted) return;

    final rupees = double.tryParse(amount.text.trim());
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter an amount, like 450.'),
      ));
      return;
    }

    final tidy = await _confirmNote(note.text);
    if (!mounted || tidy == null) return;

    final ok = await _sync.addExpense(
      tripId: widget.tripId,
      paise: rupeesToPaise(rupees),
      note: tidy.note,
      category: tidy.category,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (_access == TripAccess.owner
              ? 'Added.'
              : 'Added. The trip owner approves it before it counts.')
          : 'That could not be saved. Check your connection.'),
    ));
  }

  final TextEditingController _request = TextEditingController();
  bool _applyingRequest = false;

  /// Plain English, turned into proposals.
  ///
  /// Runs the same plan adjuster the owner's box runs, which answers with the
  /// whole plan as it would be afterwards. An owner can take that answer
  /// directly; a guest cannot, because their edit has to arrive as something
  /// approved one piece at a time. So the two versions are diffed and the
  /// difference is filed -- which also means the owner reads "Move the palace
  /// from Day 1 to Day 2" rather than a replaced itinerary they have to
  /// compare by eye.
  Future<void> _sendRequest() async {
    final text = _request.text.trim();
    final data = _trip;
    if (text.isEmpty || _applyingRequest || data == null) return;

    setState(() => _applyingRequest = true);

    final before = _dayTitles(data);
    final updated = await _adk.adjustPlan(
      days: (data['days'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[],
      request: text,
      destination: (data['destination'] ?? '').toString(),
    );
    if (!mounted) return;

    if (updated == null) {
      setState(() => _applyingRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That could not be worked out. Try naming the place '
            'and the day.'),
      ));
      return;
    }

    final after = [
      for (final day in updated)
        [
          for (final item in (day['items'] as List?) ?? const [])
            if (item is Map<String, dynamic>) (item['title'] ?? '').toString(),
        ],
    ];

    final changes = diffPlans(before, after);
    if (changes.isEmpty) {
      setState(() => _applyingRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That would not change anything.'),
      ));
      return;
    }

    // Shown before it is sent. The adjuster is a model, and a guest should
    // see what is about to go to the owner in their name.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suggest these changes?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final change in changes.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      change.kind == 'add'
                          ? Icons.add_circle_outline
                          : change.isMove
                              ? Icons.swap_horiz
                              : Icons.remove_circle_outline,
                      size: 16,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_readChange(change),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            if (changes.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('…and ${changes.length - 8} more',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
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
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _applyingRequest = false);
      return;
    }

    for (final change in changes) {
      switch (change.kind) {
        case 'add':
          await _sync.proposeAdd(
            tripId: widget.tripId,
            dayIndex: change.dayIndex,
            title: change.title,
          );
        case 'remove':
          await _sync.proposeRemove(
            tripId: widget.tripId,
            dayIndex: change.dayIndex,
            title: change.title,
          );
        case 'move':
          await _sync.proposeMove(
            tripId: widget.tripId,
            fromDayIndex: change.fromDayIndex ?? 0,
            dayIndex: change.dayIndex,
            title: change.title,
          );
      }
    }

    if (!mounted) return;
    setState(() {
      _applyingRequest = false;
      _request.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_access == TripAccess.owner
          ? 'Sent. Accept them on your trip page to apply them.'
          : 'Sent to the owner. They go in when accepted.'),
    ));
  }

  String _readChange(PlanChange change) => switch (change.kind) {
        'add' => 'Add ${change.title} to Day ${change.dayIndex + 1}',
        'remove' => 'Remove ${change.title} from Day ${change.dayIndex + 1}',
        _ => 'Move ${change.title} from Day ${(change.fromDayIndex ?? 0) + 1} '
            'to Day ${change.dayIndex + 1}',
      };

  /// The plan as plain lists of titles, for comparison.
  List<List<String>> _dayTitles(Map<String, dynamic> data) => [
        for (final day in (data['days'] as List?) ?? const [])
          if (day is Map<String, dynamic>)
            [
              for (final item in (day['items'] as List?) ?? const [])
                if (item is Map<String, dynamic>)
                  (item['title'] ?? '').toString(),
            ],
      ];

  Widget _requestBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _request,
              enabled: !_applyingRequest,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendRequest(),
              decoration: InputDecoration(
                hintText: 'e.g. move the palace to Day 2',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _applyingRequest
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton.filled(
                  onPressed: _sendRequest,
                  icon: const Icon(Icons.arrow_upward),
                  style: IconButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                  ),
                ),
        ],
      ),
    );
  }

  /// The whole screen, for somebody who is not signed in.
  ///
  /// Not a banner over the trip: there is no trip to put it over. The database
  /// refuses the read, so this is all there is until they sign in -- and
  /// saying so plainly beats a page that looks broken.
  Widget _signInGate() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_travel,
                size: 44, color: AppConfig.primaryColor),
            const SizedBox(height: 16),
            const Text(
              'Someone shared a trip with you',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to open it. The owner sees who you are, and approves '
              'you before you can change the plan or add what you paid.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 260,
              child: _signingIn
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _signIn,
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Continue with Google'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppConfig.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              'New here? Signing in makes your account.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
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
        message = 'You can edit this trip and add what you paid.';
      case TripAccess.pending:
        // Said plainly. The alternative is somebody tapping "ask" repeatedly,
        // wondering whether the first one worked.
        message = 'You have asked to join this trip. Waiting for the owner.';
      case TripAccess.viewer:
        message = 'You can read this trip. Ask the owner to join in — one '
            'approval covers changing the plan and adding spending.';
        action = _asking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: _requestAccess,
                child: const Text('Ask to join'),
              );
      case TripAccess.signedOut:
        // Every rule requires a signed-in account, and a proposal is stamped
        // with the author's uid by the rules themselves -- so a change is
        // provably from a real account rather than from whoever holds the
        // link. That only works if signing in is reachable from here.
        // Reached only if the session ends while the screen is open; the
        // body shows _signInGate() before this can normally be seen.
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
  /// The actions a guest has on one place: the owner's, held for approval.
  ///
  /// Shown to anyone signed in, because the proposals rule allows anyone
  /// signed in to file one. A guest who cannot edit is exactly the person most
  /// likely to notice that a place is on the wrong day.
  Widget _placeActions(int dayIndex, String title, int dayCount) {
    return PopupMenuButton<String>(
      tooltip: 'Suggest a change',
      icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade600),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'remove',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18),
            SizedBox(width: 10),
            Text('Suggest removing'),
          ]),
        ),
        for (var day = 0; day < dayCount; day++)
          if (day != dayIndex)
            PopupMenuItem(
              value: 'move:$day',
              child: Row(children: [
                const Icon(Icons.swap_horiz, size: 18),
                const SizedBox(width: 10),
                Text('Move to Day ${day + 1}'),
              ]),
            ),
      ],
      onSelected: (choice) async {
        final ok = choice == 'remove'
            ? await _sync.proposeRemove(
                tripId: widget.tripId,
                dayIndex: dayIndex,
                title: title,
              )
            : await _sync.proposeMove(
                tripId: widget.tripId,
                fromDayIndex: dayIndex,
                dayIndex: int.parse(choice.split(':')[1]),
                title: title,
              );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? (_access == TripAccess.owner
                  ? 'Suggested. Accept it on your trip page to apply it.'
                  : 'Suggested. It goes in when the owner accepts it.')
              : 'That could not be sent. Check your connection.'),
        ));
      },
    );
  }

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
                    // Anyone signed in, which is what the rules already
                    // allow: a suggestion is a request, not a change, and
                    // the people most likely to have one are exactly the
                    // guests who cannot edit.
                    if (_access != TripAccess.signedOut)
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
                    Row(
                      children: [
                        Expanded(
                          child: _placeRow(item.title,
                              (data['destination'] ?? '').toString()),
                        ),
                        if (_access != TripAccess.signedOut)
                          _placeActions(i, item.title, days.length),
                      ],
                    ),
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
