import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../utils/currency_input_formatter.dart';
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
  late String _selectedCurrencyCode;
  static const List<String> _supportedCurrencyCodes = [
    'USD',
    'EUR',
    'GBP',
    'INR',
    'JPY',
    'CNY',
    'AUD',
    'CAD',
    'SGD',
    'AED',
  ];

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
    {
      'id': 'transportation',
      'title': 'Transportation',
      'icon': Icons.directions_car
    },
    {'id': 'food', 'title': 'Food & Dining', 'icon': Icons.restaurant},
    {'id': 'activities', 'title': 'Activities', 'icon': Icons.local_activity},
    {'id': 'shopping', 'title': 'Shopping', 'icon': Icons.shopping_bag},
    {'id': 'miscellaneous', 'title': 'Emergency & Misc', 'icon': Icons.warning},
  ];
  final Map<String, TextEditingController> _allocationAmountControllers = {};

  double? get _enteredBudget {
    final val = double.tryParse(_budgetController.text.replaceAll(',', ''));
    return (val != null && val > 0) ? val : null;
  }

  /// Re-applies the grouping separators after the currency dropdown changes
  /// so switching from USD (100,000) to INR (1,00,000) reformats live.
  void _reformatBudgetForCurrency() {
    final current = _enteredBudget;
    if (current == null) return;
    final formatted =
        groupedNumberFormat(_selectedCurrencyCode).format(current.round());
    _budgetController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _defaultCurrencyForLocale(Locale locale) {
    const countryToCurrency = {
      'US': 'USD',
      'CA': 'CAD',
      'GB': 'GBP',
      'IE': 'EUR',
      'FR': 'EUR',
      'DE': 'EUR',
      'ES': 'EUR',
      'IT': 'EUR',
      'NL': 'EUR',
      'PT': 'EUR',
      'IN': 'INR',
      'JP': 'JPY',
      'CN': 'CNY',
      'AU': 'AUD',
      'NZ': 'NZD',
      'SG': 'SGD',
      'AE': 'AED',
    };

    final countryCode = locale.countryCode?.toUpperCase();
    if (countryCode != null && countryToCurrency.containsKey(countryCode)) {
      return countryToCurrency[countryCode]!;
    }

    try {
      final format =
          NumberFormat.simpleCurrency(locale: locale.toLanguageTag());
      final code = format.currencyName;
      if (code != null && code.isNotEmpty) {
        return code.toUpperCase();
      }
    } catch (_) {
      // Fall through to USD.
    }
    return 'USD';
  }

  String _currencySymbol(String code) {
    try {
      final format = NumberFormat.simpleCurrency(name: code);
      if (format.currencySymbol.isNotEmpty) {
        return format.currencySymbol;
      }
    } catch (_) {
      // Fall through to code.
    }
    return code;
  }

  String _formatBudgetAmount(double amount, {bool includeCode = false}) {
    final symbol = _currencySymbol(_selectedCurrencyCode);
    final codeSuffix = includeCode ? ' $_selectedCurrencyCode' : '';
    final grouped = groupedNumberFormat(_selectedCurrencyCode).format(amount.round());
    return '$symbol$grouped$codeSuffix';
  }

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _selectedCurrencyCode = _defaultCurrencyForLocale(locale);
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      _allocationAmountControllers[categoryId] =
          TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    _budgetController.dispose();
    for (final controller in _allocationAmountControllers.values) {
      controller.dispose();
    }
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
                            const Spacer(),
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
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedCurrencyCode,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      icon: const Icon(Icons.arrow_drop_down),
                                      items:
                                          _supportedCurrencyCodes.map((code) {
                                        return DropdownMenuItem<String>(
                                          value: code,
                                          child: Text(code),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() =>
                                            _selectedCurrencyCode = value);
                                        _reformatBudgetForCurrency();
                                      },
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
                                      inputFormatters: [
                                        CurrencyInputFormatter(
                                          currencyCode: _selectedCurrencyCode,
                                        ),
                                      ],
                                      onChanged: (_) {
                                        setState(() {});
                                        _syncAllocationAmountControllers();
                                      },
                                      decoration: const InputDecoration(
                                        hintText: 'Enter your budget',
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
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _enteredBudget != null
                                        ? _formatBudgetAmount(_enteredBudget!,
                                            includeCode: true)
                                        : 'Not set',
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
                                final enteredBudget = _enteredBudget ?? 0;
                                final totalAllocated = _allocations.values
                                    .fold<double>(0, (sum, v) => sum + v);
                                final allocatedAmount =
                                    enteredBudget * totalAllocated;
                                final remaining =
                                    enteredBudget - allocatedAmount;
                                final isNegative = remaining < 0;
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 16),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: isNegative
                                        ? Colors.red.shade50
                                        : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isNegative
                                          ? Colors.red.shade300
                                          : Colors.green.shade300,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isNegative
                                                ? Icons.warning_amber_rounded
                                                : Icons.account_balance_wallet,
                                            color: isNegative
                                                ? Colors.red
                                                : Colors.green.shade700,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Remaining',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isNegative
                                                  ? Colors.red.shade700
                                                  : Colors.green.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${isNegative ? "-" : ""}${_formatBudgetAmount(remaining.abs())}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isNegative
                                              ? Colors.red
                                              : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            ..._budgetCategories.map(
                                (category) => _buildBudgetSlider(category)),
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
                                  final amount = (_enteredBudget ?? 0) *
                                      _allocations[category['id']]!;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(category['icon'] as IconData,
                                            size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            category['title'] as String,
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        Text(
                                          '${percentage.toStringAsFixed(0)}% / ${_formatBudgetAmount(amount)}',
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
                          final enteredBudget = _enteredBudget;
                          if (enteredBudget == null) {
                            Get.snackbar(
                              'Budget required',
                              'Please enter a valid budget amount.',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                            return;
                          }
                          final provider = Provider.of<UserPreferencesProvider>(
                              context,
                              listen: false);
                          provider.updateBudget(
                            enteredBudget,
                            currencyCode: _selectedCurrencyCode,
                          );
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
    final amount = (_enteredBudget ?? 0) * currentValue;

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
              Icon(category['icon'] as IconData,
                  size: 20, color: AppConfig.primaryColor),
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
                '${(currentValue * 100).toStringAsFixed(0)}% • ${_formatBudgetAmount(amount)}',
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allocationAmountControllers[categoryId],
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    CurrencyInputFormatter(currencyCode: _selectedCurrencyCode),
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
                _selectedCurrencyCode,
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
      _allocations[categoryId] = newValue;
    });
    _syncAllocationAmountControllers();
  }

  void _syncAllocationAmountControllers({String? skipCategoryId}) {
    final enteredBudget = _enteredBudget ?? 0;
    final formatter = groupedNumberFormat(_selectedCurrencyCode);
    for (final category in _budgetCategories) {
      final categoryId = category['id'] as String;
      if (categoryId == skipCategoryId) continue;

      final controller = _allocationAmountControllers[categoryId];
      if (controller == null) continue;

      final amount = enteredBudget * (_allocations[categoryId] ?? 0);
      final text = formatter.format(amount.round());
      if (controller.text != text) {
        controller.value = controller.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  void _updateAllocationFromAmount(String categoryId, String rawValue) {
    final enteredBudget = _enteredBudget ?? 0;
    final parsed = double.tryParse(rawValue.replaceAll(',', '').trim());
    if (parsed == null || enteredBudget <= 0) return;

    final clampedAmount = parsed.clamp(0, enteredBudget);
    final ratio = enteredBudget == 0 ? 0.0 : clampedAmount / enteredBudget;

    setState(() {
      _allocations[categoryId] = ratio;
    });
    _syncAllocationAmountControllers();
  }
}
