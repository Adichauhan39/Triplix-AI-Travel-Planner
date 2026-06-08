import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/user_preferences_provider.dart';
import '../services/python_adk_service.dart';
import '../widgets/user_progress_checkpoint.dart';

class DestinationPreferencesScreen extends StatefulWidget {
  const DestinationPreferencesScreen({super.key});

  @override
  State<DestinationPreferencesScreen> createState() =>
      _DestinationPreferencesScreenState();
}

class _DestinationPreferencesScreenState
    extends State<DestinationPreferencesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PythonADKService _adkService = PythonADKService();

  // AI-generated categories for the entered city
  List<Map<String, dynamic>> _aiCategories = [];
  final Set<String> _selectedActivities = {};
  bool _isLoading = false;
  String _loadedCity = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCityInterests() async {
    final city = _searchController.text.trim();
    if (city.isEmpty) return;
    if (city.toLowerCase() == _loadedCity.toLowerCase()) return;

    setState(() {
      _isLoading = true;
      _aiCategories = [];
      _selectedActivities.clear();
    });

    try {
      // Step 1: Check if the city name is ambiguous
      final disambResult = await _adkService.disambiguateCity(city: city);
      if (!mounted) return;

      String resolvedCity = city;

      if (disambResult['success'] == true &&
          disambResult['ambiguous'] == true) {
        final options =
            List<Map<String, dynamic>>.from(disambResult['options'] ?? []);
        if (options.length > 1) {
          // Show disambiguation dialog
          final picked = await _showDisambiguationDialog(city, options);
          if (!mounted) return;
          if (picked == null) {
            // User cancelled
            setState(() => _isLoading = false);
            return;
          }
          resolvedCity = picked;
          _searchController.text = resolvedCity;
        }
      }

      // Step 2: Fetch interests for the resolved city
      final result =
          await _adkService.getDestinationInterests(city: resolvedCity);
      if (result['success'] == true && mounted) {
        final categories =
            List<Map<String, dynamic>>.from(result['categories'] ?? []);
        setState(() {
          _aiCategories = categories;
          _loadedCity = resolvedCity;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showDisambiguationDialog(
      String query, List<Map<String, dynamic>> options) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppConfig.primaryColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Did you mean?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$query" matches multiple places:',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final name = option['name'] ?? query;
              final desc = option['description'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(name),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  static const List<Color> _categoryColors = [
    Color(0xFFFF5722),
    Color(0xFF9C27B0),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF607D8B),
    Color(0xFF795548),
  ];

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'terrain':
        return Icons.terrain;
      case 'museum':
        return Icons.museum;
      case 'spa':
        return Icons.spa;
      case 'movie':
        return Icons.movie;
      case 'forest':
        return Icons.forest;
      case 'camera_alt':
        return Icons.camera_alt;
      case 'restaurant':
        return Icons.restaurant;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'temple_hindu':
        return Icons.temple_hindu;
      case 'nightlife':
        return Icons.nightlife;
      case 'sports':
        return Icons.sports;
      case 'park':
        return Icons.park;
      case 'coffee':
        return Icons.coffee;
      case 'architecture':
        return Icons.architecture;
      default:
        return Icons.local_activity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppConfig.primaryGradient,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(AppConfig.paddingMedium),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Get.back(),
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                            ),
                            const Expanded(
                              child: Text(
                                '1/4',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Where to next?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppConfig.paddingMedium),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppConfig.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Search Input with Explore Button
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      onSubmitted: (_) => _fetchCityInterests(),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Enter your destination (e.g., Bangalore)',
                                        prefixIcon: Icon(Icons.search,
                                            color: Colors.grey),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: AppConfig.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ElevatedButton(
                                    onPressed:
                                        _isLoading ? null : _fetchCityInterests,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Explore',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Loading state
                            if (_isLoading)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text(
                                        'Discovering interests for your destination...',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Empty state
                            if (!_isLoading && _aiCategories.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Column(
                                    children: [
                                      Icon(Icons.explore,
                                          size: 64,
                                          color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Enter a destination above and tap Explore\nto see area-specific interests',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // AI-generated categories
                            if (!_isLoading && _aiCategories.isNotEmpty) ...[
                              Text(
                                'Things to do in $_loadedCity',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select the activities you\'re interested in',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ..._aiCategories.asMap().entries.map((entry) {
                                final index = entry.key;
                                final category = entry.value;
                                final color = _categoryColors[
                                    index % _categoryColors.length];
                                final activities = List<String>.from(
                                    category['activities'] ?? []);
                                final iconName =
                                    category['icon'] ?? 'local_activity';
                                final title = category['title'] ?? 'Category';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              _getIcon(iconName),
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: color,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: activities.map((activity) {
                                          final isSelected =
                                              _selectedActivities
                                                  .contains(activity);
                                          return FilterChip(
                                            label: Text(
                                              activity,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                fontSize: 12,
                                              ),
                                            ),
                                            selected: isSelected,
                                            onSelected: (_) {
                                              setState(() {
                                                if (isSelected) {
                                                  _selectedActivities
                                                      .remove(activity);
                                                } else {
                                                  _selectedActivities
                                                      .add(activity);
                                                }
                                              });
                                            },
                                            backgroundColor: Colors.grey[100],
                                            selectedColor: color,
                                            checkmarkColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Next Button
                  Padding(
                    padding: const EdgeInsets.all(AppConfig.paddingMedium),
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppConfig.primaryGradient,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          final provider = Provider.of<UserPreferencesProvider>(
                              context,
                              listen: false);
                          // Save destination and selected activities
                          provider.updateDestination(_loadedCity);
                          provider.updateActivities(
                              _selectedActivities.toList());
                          Get.toNamed('/budget-preferences');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const UserProgressCheckpoint(),
        ],
      ),
    );
  }
}
