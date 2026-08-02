import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../providers/user_preferences_provider.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _analysisResult;
  final ScrollController _scrollController = ScrollController();

  // Form controllers
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  DateTime? _travelDate;

  @override
  void initState() {
    super.initState();
    // Show form dialog when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTravelInfoDialog();
    });
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _cityController.dispose();
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showTravelInfoDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Triplix AI Assistant',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please provide your travel details:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _fromController,
                      decoration: InputDecoration(
                        labelText: 'From (City)',
                        hintText: 'Enter departure city',
                        prefixIcon: const Icon(Icons.flight_takeoff),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _toController,
                      decoration: InputDecoration(
                        labelText: 'To (City)',
                        hintText: 'Enter destination city',
                        prefixIcon: const Icon(Icons.flight_land),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'Accommodation City',
                        hintText: 'Where do you need accommodation?',
                        prefixIcon: const Icon(Icons.hotel),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setDialogState(() {
                            _travelDate = date;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Travel Date',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _travelDate == null
                              ? 'Select travel date'
                              : '${_travelDate!.day}/${_travelDate!.month}/${_travelDate!.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _queryController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Additional Query (Optional)',
                        hintText: 'Any specific requirements or questions?',
                        prefixIcon: const Icon(Icons.chat),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.trim().toLowerCase() == 'hi') {
                          Navigator.of(context).pop();
                          Future.delayed(const Duration(milliseconds: 300), () {
                            _showTravelInfoDialog();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Get.back();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_fromController.text.isEmpty ||
                        _toController.text.isEmpty ||
                        _cityController.text.isEmpty ||
                        _travelDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill in all required fields'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop();
                    _analyzePreferences();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                  ),
                  child: const Text('Analyze'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _analyzePreferences() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefsProvider =
          Provider.of<UserPreferencesProvider>(context, listen: false);

      // Gather all user preferences
      final preferencesData = {
        'destination': {
          'location_types': prefsProvider.preferences.selectedTerrains,
          'climate': prefsProvider.preferences.selectedClimates.isNotEmpty
              ? prefsProvider.preferences.selectedClimates.first
              : '',
          'experience_level': prefsProvider.preferences.experience ?? '',
        },
        'budget': {
          'tier': 'mid_range', // Default since not available in current model
          'amount': prefsProvider.preferences.budget ?? 0,
          'is_per_person': false, // Default since not available
          'num_people': prefsProvider.preferences.numberOfPeople ?? 1,
        },
        'activities': {
          'selected': prefsProvider.preferences.selectedActivities,
          'intensity': 'moderate', // Default since not available
        },
        'transport': {
          'modes': prefsProvider.preferences.selectedTransport,
          'class': 'economy', // Default since not available
        },
        'allocation': {
          'accommodation':
              40, // Default values since not available in current model
          'transport': 30,
          'food': 15,
          'activities': 10,
          'shopping': 5,
        },
        'context': {
          'dietary_requirements': prefsProvider.preferences.selectedDietary,
          'accessibility_needs':
              prefsProvider.preferences.selectedAccessibility,
          'travel_companions': prefsProvider.preferences.companion ?? '',
          'special_requests': prefsProvider.preferences.occasion ?? '',
        },
      };

      // Call AI backend for comprehensive analysis
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/analyze-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(preferencesData),
      );

      if (response.statusCode == 200) {
        setState(() {
          _analysisResult = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to analyze preferences');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error analyzing preferences: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppConfig.primaryColor,
              AppConfig.secondaryColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(AppConfig.paddingMedium),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Get.back(),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.psychology_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'AI Travel Assistant',
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
                  child: _isLoading
                      ? _buildLoadingState()
                      : _analysisResult != null
                          ? _buildAnalysisResults()
                          : _buildEmptyState(),
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(AppConfig.paddingMedium),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _analyzePreferences,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Analysis'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.white,
                          foregroundColor: AppConfig.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Get.toNamed('/home'),
                        icon: const Icon(Icons.home),
                        label: const Text('Start Booking'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppConfig.primaryColor),
          SizedBox(height: 24),
          Text(
            'Analyzing your preferences...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppConfig.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Our AI agents are working together',
            style: TextStyle(
              fontSize: 14,
              color: AppConfig.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 80,
            color: AppConfig.textTertiary,
          ),
          SizedBox(height: 24),
          Text(
            'No preferences to analyze',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppConfig.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Complete the preference screens first',
            style: TextStyle(
              fontSize: 14,
              color: AppConfig.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    return SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(AppConfig.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Comprehensive Analysis', Icons.analytics),
            const SizedBox(height: 16),

            // Overall Summary
            if (_analysisResult!['overall_summary'] != null)
              _buildSummaryCard(_analysisResult!['overall_summary']),

            const SizedBox(height: 24),

            // Destination Insights
            _buildSectionTitle('Destination Insights', Icons.location_on),
            const SizedBox(height: 12),
            if (_analysisResult!['destination_analysis'] != null)
              _buildInsightCard(_analysisResult!['destination_analysis']),

            const SizedBox(height: 24),

            // Budget Insights
            _buildSectionTitle('Budget Analysis', Icons.account_balance_wallet),
            const SizedBox(height: 12),
            if (_analysisResult!['budget_analysis'] != null)
              _buildInsightCard(_analysisResult!['budget_analysis']),

            const SizedBox(height: 24),

            // Activity Insights
            _buildSectionTitle(
                'Activity Recommendations', Icons.local_activity),
            const SizedBox(height: 12),
            if (_analysisResult!['activities_analysis'] != null)
              _buildInsightCard(_analysisResult!['activities_analysis']),

            const SizedBox(height: 24),

            // Transport Insights
            _buildSectionTitle('Transport Recommendations', Icons.directions),
            const SizedBox(height: 12),
            if (_analysisResult!['transport_analysis'] != null)
              _buildInsightCard(_analysisResult!['transport_analysis']),

            const SizedBox(height: 24),

            // Allocation Insights
            _buildSectionTitle('Budget Allocation', Icons.pie_chart),
            const SizedBox(height: 12),
            if (_analysisResult!['allocation_analysis'] != null)
              _buildInsightCard(_analysisResult!['allocation_analysis']),

            const SizedBox(height: 24),

            // Special Requirements
            _buildSectionTitle('Special Considerations', Icons.info_outline),
            const SizedBox(height: 12),
            if (_analysisResult!['context_analysis'] != null)
              _buildInsightCard(_analysisResult!['context_analysis']),

            const SizedBox(height: 24),

            // Action Items
            _buildSectionTitle('Next Steps', Icons.checklist),
            const SizedBox(height: 12),
            if (_analysisResult!['action_items'] != null)
              _buildActionItems(_analysisResult!['action_items']),

            const SizedBox(height: 24),
          ],
        ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppConfig.primaryColor, size: 24),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppConfig.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConfig.primaryColor.withValues(alpha: 0.1),
            AppConfig.secondaryColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary['title'] ?? 'Summary',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConfig.primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            summary['content'] ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: AppConfig.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(Map<String, dynamic> insight) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConfig.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (insight['recommendations'] != null) ...[
            const Text(
              'Recommendations:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppConfig.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...((insight['recommendations'] as List).map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: AppConfig.successColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rec.toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppConfig.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))),
          ],
          if (insight['warnings'] != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Considerations:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppConfig.warningColor,
              ),
            ),
            const SizedBox(height: 8),
            ...((insight['warnings'] as List).map((warn) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 16, color: AppConfig.warningColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warn.toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppConfig.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))),
          ],
        ],
      ),
    );
  }

  Widget _buildActionItems(List<dynamic> items) {
    return Column(
      children: items.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppConfig.primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppConfig.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child:
                      Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConfig.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
