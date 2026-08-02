import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/user_preferences_provider.dart';
import '../widgets/user_progress_checkpoint.dart';

class TransportPreferencesScreen extends StatefulWidget {
  const TransportPreferencesScreen({super.key});

  @override
  State<TransportPreferencesScreen> createState() =>
      _TransportPreferencesScreenState();
}

class _TransportPreferencesScreenState
    extends State<TransportPreferencesScreen> {
  final TextEditingController _transportController = TextEditingController();

  @override
  void dispose() {
    _transportController.dispose();
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
                            const Spacer(),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'How do you like to travel?',
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
                            const SizedBox(height: 8),
                            Icon(Icons.smart_toy_outlined,
                                size: 48,
                                color: AppConfig.primaryColor
                                    .withValues(alpha: 0.7)),
                            const SizedBox(height: 16),
                            const Text(
                              'Tell our AI your transport preferences',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Describe how you prefer to travel and our AI will find the best options for you.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.grey[300]!, width: 1),
                              ),
                              child: TextField(
                                controller: _transportController,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                  hintText:
                                      'e.g., I prefer trains over buses because I get motion sick. '
                                      'I like scenic routes even if they take longer. '
                                      'For local travel I prefer auto or cab. '
                                      'Budget-friendly options are fine for short distances...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Quick suggestion chips
                            const Text(
                              'Quick picks (tap to add):',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                'Prefer flights',
                                'Train lover',
                                'Budget bus',
                                'Self-drive',
                                'Cab/Auto',
                                'Scenic routes',
                                'No motion sickness',
                                'Overnight travel OK',
                              ].map((label) {
                                return ActionChip(
                                  label: Text(label,
                                      style: const TextStyle(fontSize: 12)),
                                  backgroundColor: Colors.grey[100],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  onPressed: () {
                                    final current =
                                        _transportController.text.trim();
                                    if (current.isEmpty) {
                                      _transportController.text = label;
                                    } else {
                                      _transportController.text =
                                          '$current, $label';
                                    }
                                  },
                                );
                              }).toList(),
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
                          final provider = Provider.of<UserPreferencesProvider>(
                              context,
                              listen: false);
                          // Save the text as transport preferences
                          final text = _transportController.text.trim();
                          if (text.isNotEmpty) {
                            provider.updateTransport(text
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList());
                          }
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
          const UserProgressCheckpoint(),
        ],
      ),
    );
  }
}
