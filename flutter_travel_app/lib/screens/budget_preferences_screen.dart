import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../widgets/user_progress_checkpoint.dart';
import '../providers/user_preferences_provider.dart';

class BudgetPreferencesScreen extends StatefulWidget {
  const BudgetPreferencesScreen({super.key});

  @override
  State<BudgetPreferencesScreen> createState() =>
      _BudgetPreferencesScreenState();
}

class _BudgetPreferencesScreenState extends State<BudgetPreferencesScreen> {
  bool _isTotalBudget = true;
  final TextEditingController _budgetController = TextEditingController();

  final Map<String, double> _allocations = {
    'accommodation': 0.0,
    'transportation': 0.0,
    'food': 0.0,
    'activities': 0.0,
    'shopping': 0.0,
    'miscellaneous': 0.0,
  };

  final List<Map<String, dynamic>> _budgetCategories = [
    {'id': 'accommodation', 'title': 'Accommodation', 'icon': Icons.hotel},
    {'id': 'transportation', 'title': 'Transportation', 'icon': Icons.directions_car},
    {'id': 'food', 'title': 'Food & Dining', 'icon': Icons.restaurant},
    {'id': 'activities', 'title': 'Activities', 'icon': Icons.local_activity},
    {'id': 'shopping', 'title': 'Shopping', 'icon': Icons.shopping_bag},
    {'id': 'miscellaneous', 'title': 'Emergency & Misc', 'icon': Icons.warning},
  ];

  double get _enteredBudget {
    final val = double.tryParse(_budgetController.text.replaceAll(',', ''));
    return (val != null && val > 0) ? val : 5000;
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
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
                  // Header with Progress
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
                                '2/4',
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
                          'Budget & Allocation',
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
                            // Budget Type Toggle
                            const Text(
                              'Budget Type',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _isTotalBudget = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _isTotalBudget
                                              ? AppConfig.primaryColor
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Total Budget',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _isTotalBudget
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _isTotalBudget = false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        decoration: BoxDecoration(
                                          color: !_isTotalBudget
                                              ? AppConfig.primaryColor
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Per Person',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: !_isTotalBudget
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Budget Input
                            const Text(
                              'Enter Amount',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'INR',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: TextField(
                                      controller: _budgetController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                        hintText: '5,000',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 16),

                            // Budget Allocation Section
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
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '₹${_enteredBudget.toStringAsFixed(0)} INR',
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
                            const SizedBox(height: 12),

                            // Real-time remaining budget tracker
                            Builder(
                              builder: (context) {
                                final totalAllocated = _allocations.values.fold<double>(0, (sum, v) => sum + v);
                                final allocatedAmount = _enteredBudget * totalAllocated;
                                final remaining = _enteredBudget - allocatedAmount;
                                final isNegative = remaining < 0;
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: isNegative ? Colors.red.shade50 : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isNegative ? Colors.red.shade300 : Colors.green.shade300,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isNegative ? Icons.warning_amber_rounded : Icons.account_balance_wallet,
                                            color: isNegative ? Colors.red : Colors.green.shade700,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Remaining',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${isNegative ? "-" : ""}₹${remaining.abs().toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isNegative ? Colors.red : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

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
                                  final percentage = _allocations[category['id']]! * 100;
                                  final amount = _enteredBudget * _allocations[category['id']]!;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(category['icon'] as IconData,
                                            size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            category['title'] as String,
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
                          final provider = Provider.of<UserPreferencesProvider>(context, listen: false);
                          provider.updateBudget(_enteredBudget);
                          Get.toNamed('/transport-preferences');
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

          // AI Travel Insights Checkpoint Overlay
          const UserProgressCheckpoint(),
        ],
      ),
    );
  }

  Widget _buildBudgetSlider(Map<String, dynamic> category) {
    final categoryId = category['id'] as String;
    final currentValue = _allocations[categoryId]!;
    final amount = _enteredBudget * currentValue;

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
              Icon(category['icon'] as IconData, size: 20, color: AppConfig.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category['title'] as String,
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
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: (value) => _updateAllocation(categoryId, value),
            ),
          ),
        ],
      ),
    );
  }

  void _updateAllocation(String categoryId, double newValue) {
    setState(() {
      _allocations[categoryId] = newValue;
    });
  }
}
