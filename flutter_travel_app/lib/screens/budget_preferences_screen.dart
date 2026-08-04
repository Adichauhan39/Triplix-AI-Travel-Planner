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
                            const Spacer(),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'What\'s your budget?',
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
                                      onChanged: (_) => setState(() {}),
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

                            // Total Budget Summary
                            Container(
                              width: double.infinity,
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
}
