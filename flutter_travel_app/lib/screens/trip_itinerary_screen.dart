import 'package:flutter/material.dart';

class TripItineraryScreen extends StatelessWidget {
  const TripItineraryScreen({
    super.key,
    required this.tripTitle,
    required this.dateRange,
    required this.days,
  });

  final String tripTitle;
  final String dateRange;
  final List<Map<String, String>> days;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Itinerary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: const Icon(Icons.flight),
              ),
              title: Text(tripTitle),
              subtitle: Text(dateRange),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(days.length, (i) {
            final day = days[i];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.circle,
                        size: 12,
                        color: Colors.blue[700],
                      ),
                    ),
                    if (i < days.length - 1)
                      Container(width: 2, height: 60, color: Colors.grey[300]),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day['date'] ?? 'Day ${i + 1}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            day['title'] ?? 'Plan',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(day['desc'] ?? ''),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
