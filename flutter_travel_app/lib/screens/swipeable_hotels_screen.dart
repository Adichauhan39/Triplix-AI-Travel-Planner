import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/app_config.dart';
import '../models/hotel.dart';
import '../services/mock_data_service.dart';
import '../services/python_adk_service.dart';
import '../services/preference_learning_service.dart';

class SwipeableHotelsScreen extends StatefulWidget {
  final List<Hotel> hotels;

  const SwipeableHotelsScreen({super.key, required this.hotels});

  @override
  State<SwipeableHotelsScreen> createState() => _SwipeableHotelsScreenState();
}

class _SwipeableHotelsScreenState extends State<SwipeableHotelsScreen> {
  final PreferenceLearningService _learningService =
      PreferenceLearningService();
  final MockDataService _mockData = MockDataService();
  final PythonADKService _aiService = PythonADKService();

  late List<Hotel> _recommendedHotels;
  final List<Hotel> _cart = [];
  final List<Hotel> _rejected = [];

  @override
  void initState() {
    super.initState();
    _recommendedHotels = List.from(widget.hotels);
  }

  Future<void> _likeHotel(Hotel hotel) async {
    setState(() {
      _recommendedHotels.removeWhere((h) => h.id == hotel.id);
      if (!_cart.any((h) => h.id == hotel.id)) {
        _cart.add(hotel);
      }
      _rejected.removeWhere((h) => h.id == hotel.id);
    });

    await _learningService.recordLike(hotel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('${hotel.name} added to cart!')),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );

    if (_recommendedHotels.length <= 2) {
      _loadMoreRecommendations();
    }
  }

  Future<void> _dislikeHotel(Hotel hotel) async {
    setState(() {
      _recommendedHotels.removeWhere((h) => h.id == hotel.id);
      if (!_rejected.any((h) => h.id == hotel.id)) {
        _rejected.add(hotel);
      }
      _cart.removeWhere((h) => h.id == hotel.id);
    });

    await _learningService.recordDislike(hotel);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.close, color: Colors.white),
            SizedBox(width: 8),
            Text('Not interested'),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 1),
      ),
    );

    if (_recommendedHotels.length <= 2) {
      _loadMoreRecommendations();
    }
  }

  void _restoreRejectedHotel(Hotel hotel) {
    setState(() {
      _rejected.removeWhere((h) => h.id == hotel.id);
      if (!_recommendedHotels.any((h) => h.id == hotel.id) &&
          !_cart.any((h) => h.id == hotel.id)) {
        _recommendedHotels.insert(0, hotel);
      }
    });
  }

  Future<void> _loadMoreRecommendations() async {
    final preferences = await _learningService.getLearnedPreferences();
    final newHotels = await _mockData.getRecommendations(
      preferences: preferences,
      excludeIds: [
        ..._cart.map((h) => h.id),
        ..._rejected.map((h) => h.id),
        ..._recommendedHotels.map((h) => h.id),
      ],
    );

    setState(() {
      _recommendedHotels.addAll(newHotels);
    });
  }

  Future<void> _showHotelAiDialog(Hotel hotel) async {
    final questionController = TextEditingController();
    String aiResponse = '';
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> askAi() async {
              final question = questionController.text.trim();
              if (question.isEmpty || isLoading) return;

              setDialogState(() {
                isLoading = true;
                aiResponse = '';
              });

              final result = await _aiService.sendToManager(
                message:
                    'User is evaluating a hotel before decision. Answer the user query clearly and concisely.\n\n'
                    'Hotel: ${hotel.name}\n'
                    'City: ${hotel.city}\n'
                    'Type: ${hotel.type}\n'
                    'Price/night: ₹${hotel.pricePerNight.toStringAsFixed(0)}\n'
                    'Rating: ${hotel.rating}\n'
                    'Amenities: ${hotel.amenities.join(', ')}\n'
                    'Description: ${hotel.description}\n\n'
                    'User question: $question',
                context: {
                  'hotel': hotel.toJson(),
                  'question': question,
                  'intent': 'hotel_pre_decision_enquiry',
                },
                page: 'home',
              );

              setDialogState(() {
                isLoading = false;
                aiResponse = (result['response'] ?? '').toString().trim();
                if (aiResponse.isEmpty) {
                  aiResponse = 'I could not generate a response right now.';
                }
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.smart_toy, color: AppConfig.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ask AI about ${hotel.name}',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: questionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Example: Is this hotel good for family and airport connectivity?',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => askAi(),
                    ),
                    const SizedBox(height: 12),
                    if (isLoading)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('AI is thinking...'),
                        ],
                      ),
                    if (!isLoading && aiResponse.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                AppConfig.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          aiResponse,
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : askAi,
                  icon: const Icon(Icons.send),
                  label: const Text('Ask AI'),
                ),
              ],
            );
          },
        );
      },
    );

    questionController.dispose();
  }

  void _viewCart() {
    Get.toNamed('/cart', arguments: {'hotels': _cart});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotel Recommendations'),
        centerTitle: true,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: _viewCart,
              ),
              if (_cart.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_cart.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Recommended Hotels',
                subtitle: '${_recommendedHotels.length} cards',
                icon: Icons.recommend,
                color: AppConfig.primaryColor,
              ),
              const SizedBox(height: 10),
              if (_recommendedHotels.isEmpty)
                _buildEmptyBox(
                  message: 'No more recommendations right now.',
                  actionLabel: 'Load More',
                  onPressed: _loadMoreRecommendations,
                )
              else
                ..._recommendedHotels.map(
                  (hotel) => _buildRecommendationCard(hotel),
                ),
              const SizedBox(height: 18),
              _buildSectionHeader(
                title: 'Liked Hotels',
                subtitle: '${_cart.length} saved',
                icon: Icons.favorite,
                color: Colors.green,
              ),
              const SizedBox(height: 10),
              if (_cart.isEmpty)
                _buildEmptyBox(
                  message: 'Hotels you like will stay here.',
                )
              else
                ..._cart.map(
                  (hotel) => _buildCompactHotelCard(
                    hotel,
                    accentColor: Colors.green,
                    trailing: TextButton(
                      onPressed: () => _showHotelDetails(hotel),
                      child: const Text('Details'),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: _buildSectionHeader(
                  title: 'Not Interested',
                  subtitle: '${_rejected.length} rejected',
                  icon: Icons.close,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              if (_rejected.isEmpty)
                _buildEmptyBox(
                  message:
                      'Hotels you reject will be moved here in red section.',
                )
              else
                ..._rejected.map(
                  (hotel) => _buildCompactHotelCard(
                    hotel,
                    accentColor: Colors.red,
                    trailing: TextButton.icon(
                      onPressed: () => _restoreRejectedHotel(hotel),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Restore'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          subtitle,
          style:
              TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildEmptyBox(
      {required String message, String? actionLabel, VoidCallback? onPressed}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          if (actionLabel != null && onPressed != null)
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(Hotel hotel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppConfig.primaryColor.withValues(alpha: 0.12),
              backgroundImage: hotel.imageUrl.isNotEmpty
                  ? NetworkImage(hotel.imageUrl)
                  : null,
              child: hotel.imageUrl.isEmpty
                  ? const Icon(Icons.hotel, color: AppConfig.primaryColor)
                  : null,
            ),
            title: Text(
              hotel.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${hotel.city} • ${hotel.rating}★ • ₹${hotel.pricePerNight.toStringAsFixed(0)}/night',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showHotelDetails(hotel),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showHotelAiDialog(hotel),
                    icon: const Icon(Icons.smart_toy),
                    label: const Text('Ask AI before deciding'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _dislikeHotel(hotel),
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text('Not Interested'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _likeHotel(hotel),
                        icon: const Icon(Icons.favorite),
                        label: const Text('Keep'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHotelCard(
    Hotel hotel, {
    required Color accentColor,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Icon(Icons.hotel, color: accentColor),
        title: Text(hotel.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${hotel.city} • ₹${hotel.pricePerNight.toStringAsFixed(0)}/night'),
        trailing: trailing,
      ),
    );
  }

  Widget _buildHotelCard(Hotel hotel, {required bool isInteractive}) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background image
            hotel.imageUrl.isNotEmpty
                ? Image.network(
                    hotel.imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppConfig.primaryColor.withValues(alpha: 0.7),
                              AppConfig.accentColor.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.hotel,
                            size: 120,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppConfig.primaryColor.withValues(alpha: 0.7),
                          AppConfig.accentColor.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.hotel,
                        size: 120,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),

            // Hotel info
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hotel.city,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${hotel.rating}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            hotel.type,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₹${hotel.pricePerNight.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          '/night',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (hotel.amenities.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: hotel.amenities.take(4).map((amenity) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              amenity,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHotelDetails(Hotel hotel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                hotel.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16),
                  const SizedBox(width: 4),
                  Text(hotel.city),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hotel.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Amenities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: hotel.amenities.map((amenity) {
                  return Chip(
                    label: Text(amenity),
                    backgroundColor:
                        AppConfig.primaryColor.withValues(alpha: 0.1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Price per night',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '₹${hotel.pricePerNight.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
