/// Where the money went, as one card with three views: by kind, by day, and
/// a search.
///
/// Three views behind a switch rather than three stacked sections, because
/// the ledger is already long and every figure here is a secondary question.
/// The columns and the settlement are what people come for; this answers the
/// follow-up without pushing those off the screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../services/expense_columns.dart';
import '../services/expense_insights.dart';
import '../services/trip_sync.dart';

class ExpenseInsightsView extends StatefulWidget {
  const ExpenseInsightsView({
    super.key,
    required this.approved,
    this.tripDates = const [],
    this.nameOf,
  });

  final List<TripExpense> approved;

  /// The itinerary's days, so a date can be called "Day 2".
  final List<DateTime> tripDates;

  final String Function(String uid)? nameOf;

  @override
  State<ExpenseInsightsView> createState() => _ExpenseInsightsViewState();
}

enum _View { kinds, days, search }

class _ExpenseInsightsViewState extends State<ExpenseInsightsView> {
  _View _view = _View.kinds;
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// One colour per kind, fixed, so Food is the same colour on every trip and
  /// in every view. Chosen to stay distinguishable from one another and to
  /// sit beside the brand's own teal and orange.
  static const Map<String, Color> _kindColours = {
    'Stay': Color(0xFF1FA7C4),
    'Food': Color(0xFFF7941D),
    'Travel': Color(0xFF6366F1),
    'Activities': Color(0xFF10B981),
    'Shopping': Color(0xFFEC4899),
    'Other': Color(0xFF94A3B8),
  };

  Color _colourOf(String kind) =>
      _kindColours[kind] ??
      // A kind nobody planned for still gets a colour of its own, the same
      // one every time, rather than all sharing grey.
      Colors.primaries[kind.hashCode.abs() % Colors.primaries.length];

  @override
  Widget build(BuildContext context) {
    if (widget.approved.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(Brand.gap),
      decoration: Brand.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 16, color: Brand.teal),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Where the money went',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: Brand.tight),
          SegmentedButton<_View>(
            segments: const [
              ButtonSegment(value: _View.kinds, label: Text('By kind')),
              ButtonSegment(value: _View.days, label: Text('By day')),
              ButtonSegment(value: _View.search, label: Text('Search')),
            ],
            selected: {_view},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (choice) =>
                setState(() => _view = choice.first),
          ),
          const SizedBox(height: Brand.gap),
          switch (_view) {
            _View.kinds => _kinds(),
            _View.days => _days(),
            _View.search => _search(),
          },
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ kinds

  Widget _kinds() {
    final kinds = spendByCategory(widget.approved);
    if (kinds.isEmpty) return const SizedBox.shrink();
    final total = kinds.fold<int>(0, (sum, k) => sum + k.paise);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 104,
          height: 104,
          child: CustomPaint(
            painter: _DonutPainter(
              [for (final k in kinds) (k.paise, _colourOf(k.category))],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatRupees(total),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const Text('in all',
                      style: TextStyle(fontSize: 9, color: Brand.muted)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Brand.pad),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final k in kinds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _colourOf(k.category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(k.category,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(formatRupees(k.paise),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      SizedBox(
                        width: 38,
                        child: Text(
                          // Rounded, and never a misleading 0% for a small
                          // real amount.
                          '${math.max(1, (k.paise * 100 / total).round())}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, color: Brand.muted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- days

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  Widget _days() {
    final days = spendByDay(widget.approved, tripDates: widget.tripDates);
    if (days.isEmpty) return const SizedBox.shrink();
    final biggest = days.map((d) => d.paise).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day.dayNumber != null
                            ? 'Day ${day.dayNumber}'
                            : 'Outside trip',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: day.dayNumber != null
                              ? Brand.text
                              : Brand.muted,
                        ),
                      ),
                      Text(
                          '${day.date.day} ${_months[day.date.month - 1]}',
                          style: const TextStyle(
                              fontSize: 10, color: Brand.muted)),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 10,
                        // At least a sliver, so a day with ₹20 on it is
                        // visibly a day that had something.
                        width: math.max(
                            4, box.maxWidth * day.paise / biggest),
                        decoration: BoxDecoration(
                          color: day.dayNumber != null
                              ? Brand.teal
                              : Brand.faint,
                          borderRadius:
                              BorderRadius.circular(Brand.radiusPill),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Brand.tight),
                SizedBox(
                  width: 74,
                  child: Text(formatRupees(day.paise),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        const SizedBox(height: Brand.tight),
        // Said, because it is the one way this can mislead: an expense only
        // carries the date it was recorded, so a week of receipts typed in on
        // the way home all land on that one day.
        const Text(
          'Grouped by the day each expense was added.',
          style: TextStyle(fontSize: 10, color: Brand.faint),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- search

  Widget _search() {
    final found = searchExpenses(widget.approved, _query.text,
        nameOf: widget.nameOf);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'food, cab, Bulla…',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Brand.radiusSmall),
            ),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
        ),
        const SizedBox(height: Brand.gap),
        if (_query.text.trim().isEmpty)
          const Text('Type what it was for, what kind, or who paid.',
              style: TextStyle(fontSize: 12, color: Brand.muted))
        else if (found.isEmpty)
          const Text('Nothing matches that.',
              style: TextStyle(fontSize: 12, color: Brand.muted))
        else ...[
          Text(
            '${found.matches.length} '
            '${found.matches.length == 1 ? 'expense' : 'expenses'} · '
            '${formatRupees(found.paise)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Brand.tight),
          for (final row in found.matches.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colourOf(row.category),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.note.isEmpty ? row.category : row.note,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    widget.nameOf?.call(row.by) ?? row.byName,
                    style: const TextStyle(fontSize: 11, color: Brand.muted),
                  ),
                  const SizedBox(width: Brand.gap),
                  Text(formatRupees(row.paise),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          if (found.matches.length > 20)
            Text('and ${found.matches.length - 20} more',
                style: const TextStyle(fontSize: 11, color: Brand.muted)),
        ],
      ],
    );
  }
}

/// A ring cut into one arc per kind of spending, largest first.
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);

  final List<(int, Color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.$1);
    if (total <= 0) return;

    final stroke = size.shortestSide * 0.16;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // A hairline gap between slices so two neighbouring colours read as two
    // things rather than one smudge. Skipped for a single slice, where it
    // would leave a nick in an otherwise complete ring.
    final gap = slices.length > 1 ? 0.035 : 0.0;
    var start = -math.pi / 2;
    for (final (paise, colour) in slices) {
      final sweep = 2 * math.pi * paise / total;
      paint.color = colour;
      canvas.drawArc(rect, start + gap / 2,
          math.max(0.0, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}
