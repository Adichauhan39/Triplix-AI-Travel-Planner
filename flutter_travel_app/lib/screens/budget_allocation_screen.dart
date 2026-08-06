import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/user_preferences_provider.dart';
import '../utils/currency_input_formatter.dart';

class BudgetAllocationScreen extends StatefulWidget {
  const BudgetAllocationScreen({super.key});

  @override
  State<BudgetAllocationScreen> createState() => _BudgetAllocationScreenState();
}

class _BudgetAllocationScreenState extends State<BudgetAllocationScreen> {
  double _totalBudget = 5000; // Default budget
  final Map<String, double> _allocations = {
    'accommodation': 0.3,
    'transportation': 0.2,
    'food': 0.15,
    'activities': 0.15,
    'shopping': 0.1,
    'miscellaneous': 0.1,
  };
  final Map<String, TextEditingController> _allocationAmountControllers = {};

  @override
  void initState() {
    super.initState();
    final formatter = groupedNumberFormat('INR');
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      final amount = _totalBudget * (_allocations[categoryId] ?? 0);
      _allocationAmountControllers[categoryId] =
          TextEditingController(text: formatter.format(amount.round()));
    }
    // Get budget from provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<UserPreferencesProvider>(context, listen: false);
      if (provider.preferences.budget != null &&
          provider.preferences.budget! > 0) {
        setState(() {
          _totalBudget = provider.preferences.budget!;
        });
        _syncAllocationAmountControllers();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _allocationAmountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  final List<Map<String, dynamic>> _budgetCategories = [
    {'id': 'accommodation', 'title': 'Accommodation', 'icon': Icons.hotel},
    {
      'id': 'transportation',
      'title': 'Transportation',
      'icon': Icons.directions_car
    },
    {'id': 'food', 'title': 'Food & Dining', 'icon': Icons.restaurant},
    {
      'id': 'activities',
      'title': 'Activities & Experiences',
      'icon': Icons.local_activity
    },
    {
      'id': 'shopping',
      'title': 'Shopping & Souvenirs',
      'icon': Icons.shopping_bag
    },
    {
      'id': 'miscellaneous',
      'title': 'Emergency & Miscellaneous',
      'icon': Icons.warning
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppConfig.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with Progress
              Padding(
                padding: const EdgeInsets.all(AppConfig.paddingMedium),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Get.back(),
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'How will you split your spend?',
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
                        // Total Budget Summary
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppConfig.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Total Trip Budget',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '₹${_totalBudget.toStringAsFixed(0)} INR',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'Budget Allocation',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Budget Sliders
                        ..._budgetCategories
                            .map((category) => _buildBudgetSlider(category)),
                        const SizedBox(height: 24),

                        // Allocation Summary
                        const Text(
                          'Allocation Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: _budgetCategories.map((category) {
                              final percentage =
                                  _allocations[category['id']]! * 100;
                              final amount =
                                  _totalBudget * _allocations[category['id']]!;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(category['icon'],
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        category['title'],
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    Text(
                                      '${percentage.toStringAsFixed(0)}% / ₹${amount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppConfig.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
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
                      // Calculate total budget from allocations
                      final totalBudget = _allocations.values.fold<double>(
                          0,
                          (sum, allocation) =>
                              sum + (allocation * _totalBudget));
                      // Save budget to provider
                      final provider = Provider.of<UserPreferencesProvider>(
                          context,
                          listen: false);
                      provider.updateBudget(totalBudget);
                      Get.toNamed('/additional-context');
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
    );
  }

  Widget _buildBudgetSlider(Map<String, dynamic> category) {
    final categoryId = category['id'];
    final currentValue = _allocations[categoryId]!;
    final amount = _totalBudget * currentValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category['icon'], size: 20, color: AppConfig.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category['title'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              Text(
                '${(currentValue * 100).toStringAsFixed(0)}% • ₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConfig.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppConfig.primaryColor,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: AppConfig.primaryColor,
              overlayColor: AppConfig.primaryColor.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: currentValue,
              min: 0.0, // Minimum 0% (allow zero allocation)
              max: 0.6, // Maximum 60%
              divisions: 60, // Steps of 1%
              onChanged: (value) => _updateAllocation(categoryId, value),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allocationAmountControllers[categoryId],
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    CurrencyInputFormatter(currencyCode: 'INR'),
                  ],
                  onChanged: (value) =>
                      _updateAllocationFromAmount(categoryId, value),
                  decoration: InputDecoration(
                    hintText: 'Enter value directly',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'INR',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _updateAllocation(String categoryId, double newValue) {
    setState(() {
      // Calculate the difference
      final oldValue = _allocations[categoryId]!;
      final difference = newValue - oldValue;

      // Update the target category
      _allocations[categoryId] = newValue;

      // Distribute the difference among other categories proportionally
      final otherCategories = _allocations.entries
          .where((entry) => entry.key != categoryId)
          .toList();

      final totalOtherAllocation = otherCategories.fold<double>(
        0,
        (sum, entry) => sum + entry.value,
      );

      if (totalOtherAllocation > 0) {
        for (final entry in otherCategories) {
          final proportion = entry.value / totalOtherAllocation;
          final adjustment = difference * proportion;
          _allocations[entry.key] = (entry.value - adjustment).clamp(0.01, 1.0);
        }
      }

      // Normalize to ensure total is 100%
      _normalizeAllocations();
    });
    _syncAllocationAmountControllers();
  }

  void _updateAllocationFromAmount(String categoryId, String rawValue) {
    final parsed = double.tryParse(rawValue.replaceAll(',', '').trim());
    if (parsed == null || _totalBudget <= 0) return;

    final clampedAmount = parsed.clamp(0, _totalBudget);
    final ratio = clampedAmount / _totalBudget;
    _updateAllocation(categoryId, ratio);
  }

  void _syncAllocationAmountControllers({String? skipCategoryId}) {
    final formatter = groupedNumberFormat('INR');
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      if (categoryId == skipCategoryId) continue;

      final controller = _allocationAmountControllers[categoryId];
      if (controller == null) continue;

      final amount = _totalBudget * (_allocations[categoryId] ?? 0);
      final text = formatter.format(amount.round());
      if (controller.text != text) {
        controller.value = controller.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  void _normalizeAllocations() {
    final total =
        _allocations.values.fold<double>(0, (sum, value) => sum + value);
    if (total != 1.0) {
      final factor = 1.0 / total;
      _allocations.updateAll((key, value) => value * factor);
    }
  }
}
