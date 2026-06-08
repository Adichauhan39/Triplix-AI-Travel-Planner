import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:animate_do/animate_do.dart';
import '../config/app_config.dart';
import '../models/hotel.dart';
import '../services/mock_data_service.dart';
import '../services/preference_learning_service.dart';

class SwipeableHotelsScreen extends StatefulWidget {
  final List<Hotel> hotels;

  const SwipeableHotelsScreen({super.key, required this.hotels});

  @override
  State<SwipeableHotelsScreen> createState() => _SwipeableHotelsScreenState();
}

class _SwipeableHotelsScreenState extends State<SwipeableHotelsScreen>
    with SingleTickerProviderStateMixin {
  final PreferenceLearningService _learningService =
      PreferenceLearningService();
  final MockDataService _mockData = MockDataService();

  late List<Hotel> _remainingHotels;
  final List<Hotel> _cart = [];
  final List<Hotel> _rejected = [];

  int _currentIndex = 0;
  double _dragDistance = 0;
  bool _isDragging = false;

  late AnimationController _animationController;
  late Animation<Offset> slideAnimation;

  @override
  void initState() {
    super.initState();
    _remainingHotels = List.from(widget.hotels);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(2, 0),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onSwipeRight() async {
    if (_currentIndex >= _remainingHotels.length) return;

    final hotel = _remainingHotels[_currentIndex];
    setState(() {
      _cart.add(hotel);
    });

    // Learn from this preference
    await _learningService.recordLike(hotel);

    // Animate card out
    await _animationController.forward();

    setState(() {
      _currentIndex++;
    });

    _animationController.reset();

    // Show feedback
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

    // Load more recommendations if running low
    if (_currentIndex >= _remainingHotels.length - 2) {
      _loadMoreRecommendations();
    }
  }

  void _onSwipeLeft() async {
    if (_currentIndex >= _remainingHotels.length) return;

    final hotel = _remainingHotels[_currentIndex];
    setState(() {
      _rejected.add(hotel);
    });

    // Learn from this rejection
    await _learningService.recordDislike(hotel);

    // Animate card out
    slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-2, 0),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    await _animationController.forward();

    setState(() {
      _currentIndex++;
    });

    _animationController.reset();

    // Show feedback
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

    // Load more recommendations if running low
    if (_currentIndex >= _remainingHotels.length - 2) {
      _loadMoreRecommendations();
    }
  }

  Future<void> _loadMoreRecommendations() async {
    final preferences = await _learningService.getLearnedPreferences();
    final newHotels = await _mockData.getRecommendations(
      preferences: preferences,
      excludeIds: [
        ..._cart.map((h) => h.id),
        ..._rejected.map((h) => h.id),
        ..._remainingHotels.map((h) => h.id),
      ],
    );

    setState(() {
      _remainingHotels.addAll(newHotels);
    });
  }

  void _viewCart() {
    Get.toNamed('/cart', arguments: {'hotels': _cart});
  }

  @override
  Widget build(BuildContext context) {
    final hasMoreCards = _currentIndex < _remainingHotels.length;
    final currentHotel = hasMoreCards ? _remainingHotels[_currentIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swipe Hotels'),
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
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Hotel ${_currentIndex + 1} of ${_remainingHotels.length}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${_cart.length} in cart',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: hasMoreCards
                        ? _currentIndex / _remainingHotels.length
                        : 1.0,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppConfig.primaryColor,
                    ),
                  ),
                ],
              ),
            ),

            // Card Stack
            Expanded(
              child: hasMoreCards
                  ? Stack(
                      children: [
                        // Next card (preview)
                        if (_currentIndex + 1 < _remainingHotels.length)
                          Center(
                            child: Transform.scale(
                              scale: 0.9,
                              child: Opacity(
                                opacity: 0.5,
                                child: _buildHotelCard(
                                  _remainingHotels[_currentIndex + 1],
                                  isInteractive: false,
                                ),
                              ),
                            ),
                          ),

                        // Current card
                        Center(
                          child: GestureDetector(
                            onHorizontalDragStart: (details) {
                              setState(() {
                                _isDragging = true;
                                _dragDistance = 0;
                              });
                            },
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _dragDistance += details.delta.dx;
                              });
                            },
                            onHorizontalDragEnd: (details) {
                              setState(() {
                                _isDragging = false;
                              });

                              if (_dragDistance > 100) {
                                _onSwipeRight();
                              } else if (_dragDistance < -100) {
                                _onSwipeLeft();
                              } else {
                                setState(() {
                                  _dragDistance = 0;
                                });
                              }
                            },
                            child: Transform.translate(
                              offset: Offset(_dragDistance, 0),
                              child: Transform.rotate(
                                angle: _dragDistance / 1000,
                                child: _buildHotelCard(
                                  currentHotel!,
                                  isInteractive: true,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Swipe indicators
                        if (_isDragging) ...[
                          if (_dragDistance > 50)
                            Positioned(
                              top: 100,
                              right: 50,
                              child: FadeIn(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.favorite,
                                          color: Colors.white, size: 32),
                                      SizedBox(width: 8),
                                      Text(
                                        'LIKE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (_dragDistance < -50)
                            Positioned(
                              top: 100,
                              left: 50,
                              child: FadeIn(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    children: [
                                      Text(
                                        'NOPE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.close,
                                          color: Colors.white, size: 32),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No more hotels!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You\'ve reviewed all available hotels',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_cart.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: _viewCart,
                              icon: const Icon(Icons.shopping_cart),
                              label: Text('View Cart (${_cart.length})'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),

            // Action buttons
            if (hasMoreCards)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Dislike button
                    FloatingActionButton(
                      heroTag: 'dislike',
                      onPressed: _onSwipeLeft,
                      backgroundColor: Colors.white,
                      child:
                          const Icon(Icons.close, color: Colors.red, size: 32),
                    ),

                    // Info button
                    FloatingActionButton(
                      heroTag: 'info',
                      onPressed: () {
                        _showHotelDetails(currentHotel!);
                      },
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.info_outline,
                          color: AppConfig.primaryColor, size: 28),
                    ),

                    // Like button
                    FloatingActionButton(
                      heroTag: 'like',
                      onPressed: _onSwipeRight,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.favorite,
                          color: Colors.green, size: 32),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
