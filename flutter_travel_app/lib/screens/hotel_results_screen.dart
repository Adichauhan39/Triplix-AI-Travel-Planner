import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../models/hotel.dart';
import '../services/affiliate_links.dart';
import '../providers/hotel_shortlist_provider.dart';
import 'hotel_shortlist_screen.dart';

class HotelResultsScreen extends StatelessWidget {
  const HotelResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map<String, dynamic>?;
    final dynamic hotelData = args?['hotels'];
    final List<Hotel> hotels = [];

    // Parse hotel data safely for web compatibility
    if (hotelData != null && hotelData is List) {
      for (var item in hotelData) {
        try {
          if (item is Map) {
            // Convert to Map<String, dynamic> if needed
            final hotelMap = Map<String, dynamic>.from(item);
            hotels.add(Hotel.fromJson(hotelMap));
          } else if (item is Hotel) {
            hotels.add(item);
          }
        } catch (e) {
          print('Error parsing hotel: $e');
        }
      }
    }

    final criteria = args?['criteria'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text('Results (${hotels.length})'),
        actions: [
          Consumer<HotelShortlistProvider>(
            builder: (context, shortlist, _) => IconButton(
              tooltip: 'Selected Hotel',
              icon: Badge(
                label: Text('${shortlist.hotels.length}'),
                isLabelVisible: shortlist.hotels.isNotEmpty,
                child: const Icon(Icons.favorite),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HotelShortlistScreen(),
                  ),
                );
              },
            ),
          ),
          if (hotels.isNotEmpty)
            IconButton(
              tooltip: 'Swipe Mode',
              icon: const Icon(Icons.swipe),
              onPressed: () {
                Get.toNamed('/swipeable-hotels', arguments: {'hotels': hotels});
              },
            ),
        ],
      ),
      body: hotels.isEmpty
          ? const Center(child: Text('No hotels matched your search'))
          : Column(
              children: [
                _CriteriaBar(criteria: criteria),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: hotels.length,
                    padding: const EdgeInsets.all(AppConfig.paddingMedium),
                    itemBuilder: (context, index) =>
                        _HotelResultCard(hotel: hotels[index]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CriteriaBar extends StatelessWidget {
  final Map<String, dynamic> criteria;
  const _CriteriaBar({required this.criteria});

  @override
  Widget build(BuildContext context) {
    if (criteria.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppConfig.primaryColor.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: criteria.entries.map((e) {
          final value = e.value;
          if (value == null) return const SizedBox.shrink();
          String display;
          if (value is List && value.isNotEmpty) {
            display = value.join(', ');
          } else {
            display = value.toString();
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppConfig.primaryColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.label_important,
                    size: 14, color: AppConfig.primaryColor),
                const SizedBox(width: 4),
                Text('${e.key}: $display',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HotelResultCard extends StatelessWidget {
  final Hotel hotel;
  const _HotelResultCard({required this.hotel});

  @override
  Widget build(BuildContext context) {
    final hasAI = hotel.aiMatchScore != null || hotel.whyRecommended != null;
    return Consumer<HotelShortlistProvider>(
      builder: (context, shortlist, _) {
        final isShortlisted = shortlist.isShortlisted(hotel);
        return Stack(
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: hasAI ? 3 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
                side: hasAI
                    ? BorderSide(
                        color: Colors.deepPurple.withValues(alpha: 0.3),
                        width: 1.5)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: () => shortlist.toggle(hotel),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color:
                                  AppConfig.primaryColor.withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(AppConfig.radiusSmall),
                            ),
                            child: hotel.imageUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                        AppConfig.radiusSmall),
                                    child: Image.network(
                                      hotel.imageUrl,
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return const Icon(Icons.hotel,
                                            size: 36,
                                            color: AppConfig.primaryColor);
                                      },
                                    ),
                                  )
                                : const Icon(Icons.hotel,
                                    size: 36, color: AppConfig.primaryColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(hotel.name,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(hotel.city,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(hotel.rating.toString(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(
                                        '₹${hotel.pricePerNight.toInt()}/night',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppConfig.successColor)),
                                  ],
                                ),
                                if (hotel.whyRecommended != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.purple.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.deepPurple
                                              .withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      hotel.whyRecommended!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: AppConfig.textSecondary),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                if (hotel.highlights != null &&
                                    hotel.highlights!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: hotel.highlights!
                                        .take(3)
                                        .map((h) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurple
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(h,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.deepPurple,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ))
                                        .toList(),
                                  ),
                                ] else if (hotel.amenities.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    children: hotel.amenities
                                        .take(3)
                                        .map((a) => Chip(
                                            label: Text(a,
                                                style: const TextStyle(
                                                    fontSize: 10))))
                                        .toList(),
                                  ),
                                ],
                                if (hotel.perfectFor != null) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.check_circle,
                                          size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          hotel.perfectFor!,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => AffiliateLinks.open(
                            AffiliateLinks.aviasalesHotelSearch(hotel: hotel),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Book on Aviasales'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppConfig.radiusSmall),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: Icon(
                    isShortlisted ? Icons.favorite : Icons.favorite_border,
                    color: isShortlisted ? Colors.redAccent : Colors.grey,
                  ),
                  onPressed: () => shortlist.toggle(hotel),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
