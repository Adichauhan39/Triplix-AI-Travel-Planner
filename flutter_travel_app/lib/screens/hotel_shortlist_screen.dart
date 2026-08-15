import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/hotel.dart';
import '../models/confirmed_booking.dart';
import '../providers/hotel_shortlist_provider.dart';
import '../services/affiliate_links.dart';
import '../widgets/booking_confirm_prompt.dart';

/// The one hotel the user has picked for their trip. Purely in-app — the
/// third-party redirect only fires when "Book on Booking.com" is tapped.
class HotelShortlistScreen extends StatelessWidget {
  const HotelShortlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Selected Hotel'), centerTitle: true),
      body: Consumer<HotelShortlistProvider>(
        builder: (context, shortlist, _) {
          final hotels = shortlist.hotels;
          if (hotels.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppConfig.paddingLarge),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border,
                        size: 56, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No hotel selected yet.\nTap the heart on a hotel to select it for your trip.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppConfig.paddingMedium),
            itemCount: hotels.length,
            itemBuilder: (context, index) =>
                _ShortlistCard(hotel: hotels[index]),
          );
        },
      ),
    );
  }
}

class _ShortlistCard extends StatelessWidget {
  final Hotel hotel;
  const _ShortlistCard({required this.hotel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  ),
                  child: hotel.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppConfig.radiusSmall),
                          child: Image.network(
                            hotel.imageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.hotel,
                                size: 32,
                                color: AppConfig.primaryColor),
                          ),
                        )
                      : const Icon(Icons.hotel,
                          size: 32, color: AppConfig.primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hotel.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(hotel.city,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(hotel.rating.toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const Spacer(),
                          Text(
                            '₹${hotel.pricePerNight.toInt()}/night',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppConfig.successColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.favorite, color: Colors.redAccent),
                  tooltip: 'Remove from shortlist',
                  onPressed: () =>
                      context.read<HotelShortlistProvider>().remove(hotel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // Booking happens on Aviasales, which never tells us the
                // outcome — asking once the user returns is the only way this
                // reaches the itinerary.
                onPressed: () => BookingConfirmPrompt.launchAndConfirm(
                  context,
                  launch: () => AffiliateLinks.open(
                    AffiliateLinks.aviasalesHotelSearch(hotel: hotel),
                  ),
                  kind: BookingKind.hotel,
                  title: hotel.name,
                  startDate: DateTime.now(),
                  knownHotelName: hotel.name,
                  city: hotel.city,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Book on Aviasales'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConfig.radiusSmall),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
