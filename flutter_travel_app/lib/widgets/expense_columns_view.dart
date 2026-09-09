import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/expense_columns.dart';
import '../services/trip_sync.dart';

/// Shared spending, one column per traveller.
///
/// Used by both ledgers -- the owner's Budget tab and the Money tab of a
/// shared link -- so a guest sees what the owner sees. They had drifted apart:
/// only one of them ever had the paid/share/balance figures at all.
///
/// The columns end with those figures rather than repeating them in a separate
/// table underneath, so "Paid" appears once on the screen instead of twice.
class ExpenseColumnsView extends StatelessWidget {
  const ExpenseColumnsView({
    super.key,
    required this.expenses,
    required this.people,
    required this.me,
    this.canChange,
    this.onEdit,
    this.onDelete,
    this.onShared,
  });

  /// The rows that count. Pending and rejected ones are not money anybody owes
  /// yet, and belong to whatever the calling screen does with them.
  final List<TripExpense> expenses;
  final List<TripPerson> people;
  final String? me;

  /// Whether this viewer may touch a given row. Asked rather than assumed, so
  /// each screen keeps its own rule and no button appears that Firestore would
  /// refuse.
  final bool Function(TripExpense)? canChange;
  final void Function(TripExpense)? onEdit;
  final void Function(TripExpense)? onDelete;

  /// Takes a row out of the split, or puts it back.
  final void Function(TripExpense, bool shared)? onShared;

  static const double _columnWidth = 168;

  @override
  Widget build(BuildContext context) {
    final columns = buildExpenseColumns(
      approved: expenses,
      people: people,
      me: me,
    );
    if (columns.isEmpty) return const SizedBox.shrink();

    // Sideways rather than squashed. Five travellers in the width of a phone
    // would leave every column too narrow to read a note in, so the columns
    // keep their width and the strip scrolls -- while the page itself does not.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: Colors.grey.shade200,
                ),
              SizedBox(
                width: _columnWidth,
                child: _column(context, columns[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _column(BuildContext context, PersonColumn column) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                column.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (!column.inSplit)
              Tooltip(
                message: 'Paid for something but is no longer on this trip, '
                    'so the split does not include them.',
                child: Icon(Icons.info_outline,
                    size: 13, color: Colors.orange.shade700),
              ),
          ],
        ),
        const SizedBox(height: 6),

        if (column.expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('Nothing yet',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic)),
          )
        else
          for (final row in column.expenses) _expense(row),

        const SizedBox(height: 8),
        Container(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 6),

        _figure('Paid', formatRupees(column.paid)),
        if (column.personal > 0)
          _figure('Just theirs', formatRupees(column.personal),
              color: Colors.grey.shade600),
        // Nothing is claimed for somebody outside the split: the settlement
        // divides between members and will never pay them back, so a balance
        // here would be a number that never comes true.
        _figure('Share', column.inSplit ? formatRupees(column.share) : '—'),
        if (column.inSplit)
          _figure(
            'Balance',
            column.balance == 0
                ? '—'
                : '${column.balance > 0 ? '+' : '−'}'
                    '${formatRupees(column.balance)}',
            bold: true,
            color: column.balance == 0
                ? Colors.grey.shade600
                : column.balance > 0
                    ? Colors.green.shade700
                    : Colors.red.shade700,
          )
        else
          _figure('Balance', '—', color: Colors.grey.shade500),
      ],
    );
  }

  Widget _expense(TripExpense row) {
    final changeable = canChange?.call(row) ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.note.isEmpty ? row.category : row.note,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      formatRupees(row.paise),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: row.shared ? null : Colors.grey.shade600,
                      ),
                    ),
                    // Said on the row itself. A number quietly missing from
                    // the total below is the kind of thing people argue about.
                    if (!row.shared) ...[
                      const SizedBox(width: 5),
                      Text('just theirs',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (changeable)
            SizedBox(
              width: 22,
              child: PopupMenuButton<String>(
                tooltip: 'Change this expense',
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert,
                    size: 15, color: Colors.grey.shade600),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 17),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ]),
                  ),
                  // Out of the split, or back into it. The money stays on the
                  // trip either way -- this is about who owes for it, not
                  // about whether it happened.
                  PopupMenuItem(
                    value: 'split',
                    child: Row(children: [
                      Icon(
                          row.shared
                              ? Icons.person_outline
                              : Icons.group_outlined,
                          size: 17),
                      const SizedBox(width: 10),
                      Text(row.shared
                          ? 'Just mine — take out of the split'
                          : 'Put back in the split'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 17, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
                onSelected: (choice) => switch (choice) {
                  'edit' => onEdit?.call(row),
                  'split' => onShared?.call(row, !row.shared),
                  _ => onDelete?.call(row),
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? AppConfig.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
