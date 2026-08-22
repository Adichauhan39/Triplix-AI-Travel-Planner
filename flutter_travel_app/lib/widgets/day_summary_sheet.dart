import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../services/python_adk_service.dart';
import 'place_detail_sheet.dart';

/// A whole day at once: every place on it, with its photo, rating and hours.
///
/// Opening places one at a time meant three taps and three waits to find out
/// what a day actually looks like — and no way to compare them. The lookups
/// run in parallel here, so one tap answers the question the day card raises.
///
/// Everything shown is Google's data for that specific place. A place that
/// can't be found is listed with its name and nothing else rather than being
/// hidden, since it is still on the user's plan.
class DaySummarySheet extends StatefulWidget {
  const DaySummarySheet({
    super.key,
    required this.day,
    required this.dayNumber,
    required this.city,
  });

  final PlanDay day;
  final int dayNumber;
  final String city;

  static Future<void> show(
    BuildContext context, {
    required PlanDay day,
    required int dayNumber,
    required String city,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          DaySummarySheet(day: day, dayNumber: dayNumber, city: city),
    );
  }

  @override
  State<DaySummarySheet> createState() => _DaySummarySheetState();
}

class _DaySummarySheetState extends State<DaySummarySheet> {
  final PythonADKService _adk = PythonADKService();
  static final DateFormat _dayLabel = DateFormat('EEEE, d MMM');

  /// Keyed by the item's title, so a place that fails to load simply has no
  /// entry rather than shifting the others out of order.
  Map<String, Map<String, dynamic>> _details = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final titles = widget.day.items.map((i) => i.title).toList();
    if (titles.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    // In parallel: a day holds two or three places, and doing them in sequence
    // would stack their round trips into a wait long enough to feel broken.
    final results = await Future.wait(titles.map(
      (title) => _adk.placeDetails(name: title, city: widget.city),
    ));

    if (!mounted) return;
    final map = <String, Map<String, dynamic>>{};
    for (var i = 0; i < titles.length; i++) {
      final detail = results[i];
      if (detail != null) map[titles[i]] = detail;
    }
    setState(() {
      _details = map;
      _loading = false;
    });
  }

  /// The one line of opening hours worth showing on a summary: whether the
  /// place is open on the day this plan puts it on.
  ///
  /// This is the check the user cannot easily make themselves — a zoo closed
  /// on Mondays quietly ruins a Monday.
  String? _hoursForThisDay(Map<String, dynamic> place) {
    final lines = (place['opening_hours'] as List?) ?? const [];
    if (lines.isEmpty) return null;
    final weekday = DateFormat('EEEE').format(widget.day.date);
    for (final raw in lines) {
      final text = raw.toString();
      if (!text.toLowerCase().startsWith(weekday.toLowerCase())) continue;
      final split = text.indexOf(':');
      if (split == -1) return null;
      return text.substring(split + 1).trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Day ${widget.dayNumber}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text(_dayLabel.format(widget.day.date),
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.day.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text('Nothing planned for this day yet.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.day.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildPlace(widget.day.items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlace(PlanItem item) {
    final place = _details[item.title];
    final photos = (place?['photos'] as List?) ?? const [];
    final rating = (place?['rating'] as num?)?.toDouble() ?? 0;
    final hours = place == null ? null : _hoursForThisDay(place);
    final closed = hours != null && hours.toLowerCase().contains('closed');

    return InkWell(
      onTap: () => PlaceDetailSheet.show(context,
          name: item.title, city: widget.city),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
            child: photos.isEmpty
                ? Container(width: 76, height: 76, color: Colors.grey[200])
                : Image.network(
                    photos.first.toString(),
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 76, height: 76, color: Colors.grey[200]),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    if (item.addedByAssistant)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('suggested',
                            style: TextStyle(
                                fontSize: 10, color: Colors.amber.shade900)),
                      ),
                  ],
                ),
                if (rating > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.star, size: 13, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text('$rating',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                if (hours != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      // Named for this day, because that is the fact that
                      // matters: "closed on the day you're going" is the one
                      // thing worth interrupting a plan for.
                      closed ? 'Closed on this day' : 'Open $hours',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            closed ? FontWeight.w700 : FontWeight.normal,
                        color: closed ? Colors.red[700] : Colors.grey[700],
                      ),
                    ),
                  ),
                if (place == null && !_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('No details found',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
        ],
      ),
    );
  }
}
