import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/app_config.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import 'mock_booking_screen.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final CardSwiperController _controller = CardSwiperController();
  final ApiService _api = ApiService();

  String _selectedType = 'hotels';
  List<Map<String, dynamic>> _recommendations = [];
  final List<Map<String, dynamic>> _likedItems = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getSwipeRecommendations(type: _selectedType);
      setState(() {
        _recommendations = List<Map<String, dynamic>>.from(
            data['cards'] ?? data['recommendations'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading recommendations: $e')),
        );
      }
    }
  }

  bool _handleSwipe(
      int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (previousIndex >= _recommendations.length) return true;

    final item = _recommendations[previousIndex];
    final action = direction == CardSwiperDirection.right ? 'like' : 'dislike';

    // Update local state
    final provider = context.read<AppProvider>();
    provider.recordSwipe(action == 'like');

    // Track liked items
    if (action == 'like') {
      _likedItems.add(item);
    }

    // Send to backend asynchronously
    _api
        .handleSwipe(
      cardId: item['id']?.toString() ?? '',
      action: action,
      type: _selectedType,
      cardData: item,
    )
        .catchError((e) {
      print('Error tracking swipe: $e');
      return <String, dynamic>{};
    });

    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'like'
              ? '❤️ Added to favorites!'
              : '👎 Not interested'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // When 2 items are liked, show compare/book dialog
    if (_likedItems.length == 2) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showCompareOrBookDialog();
      });
    }

    return true;
  }

  void _showCompareOrBookDialog() {
    final item1 = _likedItems[0];
    final item2 = _likedItems[1];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.favorite, color: AppConfig.primaryColor),
            SizedBox(width: 8),
            Expanded(
              child: Text('You liked 2 options!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniCard(item: item1, type: _selectedType),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('VS',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            _MiniCard(item: item2, type: _selectedType),
            const SizedBox(height: 16),
            const Text(
              'What would you like to do?',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showComparison(item1, item2);
            },
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Compare'),
            style: TextButton.styleFrom(
              foregroundColor: AppConfig.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _bookBoth(item1, item2);
            },
            icon: const Icon(Icons.shopping_cart),
            label: const Text('Book Both'),
            style: FilledButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showComparison(Map<String, dynamic> item1, Map<String, dynamic> item2) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _ComparisonSheet(
          item1: item1,
          item2: item2,
          type: _selectedType,
          scrollController: scrollController,
          onBookItem: (item) {
            Navigator.pop(ctx);
            _bookSingle(item);
          },
          onBookBoth: () {
            Navigator.pop(ctx);
            _bookBoth(item1, item2);
          },
        ),
      ),
    ).then((_) {
      // Clear liked items after comparison is dismissed
      _likedItems.clear();
    });
  }

  void _bookBoth(Map<String, dynamic> item1, Map<String, dynamic> item2) {
    _likedItems.clear();
    final isHotel = _selectedType == 'hotels';
    final isTravel = _selectedType == 'travel';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MockBookingScreen(
          acceptedHotels: isHotel ? [item1, item2] : [],
          acceptedTransport: isTravel ? [item1, item2] : [],
          acceptedDestinations: (!isHotel && !isTravel) ? [item1, item2] : [],
        ),
      ),
    );
  }

  void _bookSingle(Map<String, dynamic> item) {
    _likedItems.clear();
    final isHotel = _selectedType == 'hotels';
    final isTravel = _selectedType == 'travel';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MockBookingScreen(
          acceptedHotels: isHotel ? [item] : [],
          acceptedTransport: isTravel ? [item] : [],
          acceptedDestinations: (!isHotel && !isTravel) ? [item] : [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover & Swipe'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            onPressed: () => _showInsights(provider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Type Selector
          FadeInDown(
            child: _TypeSelector(
              selectedType: _selectedType,
              onChanged: (type) {
                setState(() => _selectedType = type);
                _likedItems.clear();
                _loadRecommendations();
              },
            ),
          ),

          const SizedBox(height: 16),

          // Stats Bar
          FadeInDown(
            delay: const Duration(milliseconds: 100),
            child: _StatsBar(
              totalSwipes: provider.totalSwipes,
              likesCount: provider.likesCount,
              dislikesCount: provider.dislikesCount,
              acceptanceRate: provider.acceptanceRate,
            ),
          ),

          const SizedBox(height: 16),

          // Swipe Cards - must remain in constrained space
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _recommendations.isEmpty
                    ? _EmptyState(onRefresh: _loadRecommendations)
                    : FadeIn(
                        child: CardSwiper(
                          controller: _controller,
                          cardsCount: _recommendations.length,
                          onSwipe: _handleSwipe,
                          numberOfCardsDisplayed: 3,
                          backCardOffset: const Offset(0, 40),
                          padding: const EdgeInsets.all(24),
                          cardBuilder: (context, index, percentThresholdX,
                              percentThresholdY) {
                            return _SwipeCard(
                              item: _recommendations[index],
                              type: _selectedType,
                            );
                          },
                        ),
                      ),
          ),

          // Action Buttons
          FadeInUp(
            child: _ActionButtons(
              onDislike: () => _controller.swipe(CardSwiperDirection.left),
              onLike: () => _controller.swipe(CardSwiperDirection.right),
              onUndo: () => _controller.undo(),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showInsights(AppProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your Preference Insights',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _InsightRow(
              icon: Icons.thumb_up,
              label: 'Total Likes',
              value: provider.likesCount.toString(),
              color: Colors.green,
            ),
            _InsightRow(
              icon: Icons.thumb_down,
              label: 'Total Dislikes',
              value: provider.dislikesCount.toString(),
              color: Colors.red,
            ),
            _InsightRow(
              icon: Icons.trending_up,
              label: 'Acceptance Rate',
              value: '${provider.acceptanceRate.toStringAsFixed(1)}%',
              color: AppConfig.primaryColor,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.brain,
                      color: AppConfig.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.totalSwipes < 5
                          ? 'Swipe ${5 - provider.totalSwipes} more items to get personalized recommendations!'
                          : 'Your recommendations are now personalized based on ${provider.totalSwipes} swipes!',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final String selectedType;
  final Function(String) onChanged;

  const _TypeSelector({
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _TypeChip(
              icon: Icons.hotel,
              label: 'Hotels',
              isSelected: selectedType == 'hotels',
              onTap: () => onChanged('hotels'),
            ),
            _TypeChip(
              icon: Icons.place,
              label: 'Destinations',
              isSelected: selectedType == 'destinations',
              onTap: () => onChanged('destinations'),
            ),
            _TypeChip(
              icon: Icons.flight,
              label: 'Travel',
              isSelected: selectedType == 'travel',
              onTap: () => onChanged('travel'),
            ),
            _TypeChip(
              icon: Icons.attractions,
              label: 'Attractions',
              isSelected: selectedType == 'attractions',
              onTap: () => onChanged('attractions'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppConfig.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int totalSwipes;
  final int likesCount;
  final int dislikesCount;
  final double acceptanceRate;

  const _StatsBar({
    required this.totalSwipes,
    required this.likesCount,
    required this.dislikesCount,
    required this.acceptanceRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppConfig.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
              icon: Icons.swipe, label: 'Total', value: totalSwipes.toString()),
          _StatItem(
              icon: Icons.favorite,
              label: 'Likes',
              value: likesCount.toString()),
          _StatItem(
              icon: Icons.close,
              label: 'Dislikes',
              value: dislikesCount.toString()),
          _StatItem(
              icon: Icons.percent,
              label: 'Rate',
              value: '${acceptanceRate.toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _SwipeCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String type;

  const _SwipeCard({required this.item, required this.type});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background Image
            if (item['image'] != null ||
                item['image_url'] != null ||
                item['photo'] != null)
              Positioned.fill(
                child: Image.network(
                  (item['image'] ?? item['image_url'] ?? item['photo'])
                      as String,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: const BoxDecoration(
                        gradient: AppConfig.primaryGradient,
                      ),
                      child: const Center(
                        child:
                            Icon(Icons.image, size: 100, color: Colors.white54),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      decoration: const BoxDecoration(
                        gradient: AppConfig.primaryGradient,
                      ),
                      child: const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white54)),
                    );
                  },
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: AppConfig.primaryGradient,
                  ),
                  child: const Center(
                    child: Icon(Icons.image, size: 100, color: Colors.white54),
                  ),
                ),
              ),

            // Content Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (item['city'] != null)
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            item['city'],
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item['rating'] != null) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            item['rating'].toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (item['price'] != null) ...[
                          const Icon(Icons.currency_rupee,
                              color: Colors.greenAccent, size: 16),
                          Text(
                            item['price'].toString(),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item['description'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        item['description'],
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onDislike;
  final VoidCallback onLike;
  final VoidCallback onUndo;

  const _ActionButtons({
    required this.onDislike,
    required this.onLike,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.close,
            color: AppConfig.errorColor,
            onPressed: onDislike,
          ),
          _ActionButton(
            icon: Icons.undo,
            color: Colors.grey,
            onPressed: onUndo,
            size: 50,
          ),
          _ActionButton(
            icon: Icons.favorite,
            color: AppConfig.successColor,
            onPressed: onLike,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 65,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: size * 0.45),
        onPressed: onPressed,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No more recommendations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check back later for more!',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String type;

  const _MiniCard({required this.item, required this.type});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] ?? 'Unknown';
    final price = item['price'] ?? item['price_per_night'] ?? '';
    final rating = item['rating'];
    final image = item['image'] ?? item['image_url'] ?? item['photo'];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: image != null
                ? Image.network(
                    image,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 50,
                      height: 50,
                      color: AppConfig.primaryColor.withValues(alpha: 0.2),
                      child: const Icon(Icons.image, size: 24),
                    ),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    color: AppConfig.primaryColor.withValues(alpha: 0.2),
                    child: const Icon(Icons.image, size: 24),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (rating != null)
                  Row(children: [
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text('$rating', style: const TextStyle(fontSize: 12)),
                  ]),
              ],
            ),
          ),
          if (price.toString().isNotEmpty)
            Text('₹$price',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor,
                    fontSize: 13)),
        ],
      ),
    );
  }
}

class _ComparisonSheet extends StatelessWidget {
  final Map<String, dynamic> item1;
  final Map<String, dynamic> item2;
  final String type;
  final ScrollController scrollController;
  final Function(Map<String, dynamic>) onBookItem;
  final VoidCallback onBookBoth;

  const _ComparisonSheet({
    required this.item1,
    required this.item2,
    required this.type,
    required this.scrollController,
    required this.onBookItem,
    required this.onBookBoth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: scrollController,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          const Text('Compare Options',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),

          // Side-by-side cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _CompareColumn(
                      item: item1, type: type, label: 'Option A')),
              const SizedBox(width: 12),
              Expanded(
                  child: _CompareColumn(
                      item: item2, type: type, label: 'Option B')),
            ],
          ),

          const SizedBox(height: 20),

          // Comparison rows
          _CompareRow(
            label: 'Price',
            value1: '₹${item1['price'] ?? item1['price_per_night'] ?? 'N/A'}',
            value2: '₹${item2['price'] ?? item2['price_per_night'] ?? 'N/A'}',
            icon: Icons.currency_rupee,
          ),
          _CompareRow(
            label: 'Rating',
            value1: '${item1['rating'] ?? 'N/A'} ⭐',
            value2: '${item2['rating'] ?? 'N/A'} ⭐',
            icon: Icons.star,
          ),
          if (type == 'hotels') ...[
            _CompareRow(
              label: 'Type',
              value1: item1['type']?.toString() ?? 'N/A',
              value2: item2['type']?.toString() ?? 'N/A',
              icon: Icons.hotel,
            ),
            _CompareRow(
              label: 'City',
              value1: item1['city']?.toString() ?? 'N/A',
              value2: item2['city']?.toString() ?? 'N/A',
              icon: Icons.location_on,
            ),
          ],
          if (type == 'travel') ...[
            _CompareRow(
              label: 'Duration',
              value1: item1['duration']?.toString() ?? 'N/A',
              value2: item2['duration']?.toString() ?? 'N/A',
              icon: Icons.timer,
            ),
            _CompareRow(
              label: 'Type',
              value1: item1['type']?.toString() ?? 'N/A',
              value2: item2['type']?.toString() ?? 'N/A',
              icon: Icons.directions,
            ),
          ],

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onBookItem(item1),
                  icon: const Icon(Icons.check),
                  label: const Text('Book A'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConfig.primaryColor,
                    side: const BorderSide(color: AppConfig.primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onBookItem(item2),
                  icon: const Icon(Icons.check),
                  label: const Text('Book B'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConfig.primaryColor,
                    side: const BorderSide(color: AppConfig.primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onBookBoth,
              icon: const Icon(Icons.shopping_cart),
              label: const Text('Book Both'),
              style: FilledButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareColumn extends StatelessWidget {
  final Map<String, dynamic> item;
  final String type;
  final String label;

  const _CompareColumn(
      {required this.item, required this.type, required this.label});

  @override
  Widget build(BuildContext context) {
    final image = item['image'] ?? item['image_url'] ?? item['photo'];

    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: image != null
              ? Image.network(
                  image,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: AppConfig.primaryColor.withValues(alpha: 0.15),
                    child: const Center(
                        child: Icon(Icons.image, size: 40, color: Colors.grey)),
                  ),
                )
              : Container(
                  height: 120,
                  color: AppConfig.primaryColor.withValues(alpha: 0.15),
                  child: const Center(
                      child: Icon(Icons.image, size: 40, color: Colors.grey)),
                ),
        ),
        const SizedBox(height: 8),
        Text(item['name'] ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String value1;
  final String value2;
  final IconData icon;

  const _CompareRow({
    required this.label,
    required this.value1,
    required this.value2,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value1,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Column(
            children: [
              Icon(icon, size: 16, color: AppConfig.primaryColor),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          Expanded(
            child: Text(value2,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
