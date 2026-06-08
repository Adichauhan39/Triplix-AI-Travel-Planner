import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_preferences_provider.dart';
import '../config/app_config.dart';
import '../services/dynamic_checkpoint_service.dart';
import '../models/user_preferences.dart';

class UserProgressCheckpoint extends StatefulWidget {
  const UserProgressCheckpoint({super.key});

  @override
  State<UserProgressCheckpoint> createState() => _UserProgressCheckpointState();
}

class _UserProgressCheckpointState extends State<UserProgressCheckpoint> {
  final DynamicCheckpointService _checkpointService =
      DynamicCheckpointService();
  Map<String, dynamic>? _insights;
  bool _isLoading = false;

  // --- SLIDER STATE ---
  bool _isSliderOpen = false;

  void _toggleSlider() {
    setState(() {
      _isSliderOpen = !_isSliderOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload insights when preferences change
    final provider = Provider.of<UserPreferencesProvider>(context);
    if (_insights == null || _shouldReloadInsights(provider.preferences)) {
      _loadInsights();
    }
  }

  bool _shouldReloadInsights(UserPreferences preferences) {
    // Reload if significant preferences have changed
    final hasNewData = preferences.hasDestination ||
        preferences.hasBudget ||
        preferences.hasActivities ||
        preferences.hasTransport ||
        preferences.hasAccommodation ||
        preferences.hasDestinationPreferences ||
        preferences.hasCompanion ||
        preferences.hasOccasion;

    final hasExistingInsights = _insights != null;
    final lastUpdate = _insights?['lastUpdated'] as DateTime?;
    final isStale = lastUpdate == null ||
        DateTime.now().difference(lastUpdate).inMinutes > 5;

    return hasNewData && (!hasExistingInsights || isStale);
  }

  Future<void> _loadInsights() async {
    final provider =
        Provider.of<UserPreferencesProvider>(context, listen: false);

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final insights =
          await _checkpointService.getCheckpointInsights(provider.preferences);
      if (mounted) {
        setState(() {
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading checkpoint insights: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserPreferencesProvider>(
      builder: (context, provider, child) {
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 100, right: 16, bottom: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width:
                  _isSliderOpen ? MediaQuery.of(context).size.width * 0.85 : 56,
              height:
                  _isSliderOpen ? MediaQuery.of(context).size.height * 0.5 : 56,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 32,
                maxHeight: MediaQuery.of(context).size.height - 150,
              ),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_isSliderOpen ? 24 : 28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Main AI Insights content (hidden when closed)
                  if (_isSliderOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header - responsive layout
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // If width is too small, stack vertically
                                if (constraints.maxWidth < 200) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.smart_toy,
                                              color: AppConfig.primaryColor,
                                              size: 22),
                                          SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'AI Travel Insights',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isLoading)
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 22),
                                            onPressed: _toggleSlider,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                } else {
                                  // Normal horizontal layout
                                  return Row(
                                    children: [
                                      const Icon(Icons.smart_toy,
                                          color: AppConfig.primaryColor,
                                          size: 22),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'AI Travel Insights',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_isLoading)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            size: 22),
                                        onPressed: _toggleSlider,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            if (_insights?['summary'] != null && !_isLoading)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      AppConfig.primaryColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _insights!['summary'],
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            const SizedBox(height: 12),
                            if (_insights != null && !_isLoading) ...[
                              _buildCheckpointProgress(_insights!),
                              const SizedBox(height: 16),
                              _buildAIInsights(_insights!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  // Floating action icon (always visible)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: GestureDetector(
                      onTap: _toggleSlider,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppConfig.primaryColor.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isSliderOpen
                              ? Icons.arrow_forward_ios_rounded
                              : Icons.smart_toy_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckpointProgress(Map<String, dynamic> insights) {
    final checkpointPlan = insights['checkpointPlan'] as Map<String, dynamic>?;
    if (checkpointPlan == null) return const SizedBox.shrink();

    final checkpoints = checkpointPlan['checkpoints'] as List;
    final completionPct = insights['completionPercentage'] as double? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress Bar
        Row(
          children: [
            const Text(
              '📋 Checkpoint Progress',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Text(
              '${completionPct.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppConfig.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: completionPct / 100,
            backgroundColor: Colors.grey[200],
            color: AppConfig.primaryColor,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 12),

        // Checkpoint List
        ...checkpoints.map((checkpoint) {
          final isCompleted = checkpoint['completed'] as bool;
          final importance = checkpoint['importance'] as String;
          final title = checkpoint['title'] as String;

          Color importanceColor = importance == 'critical'
              ? Colors.red
              : importance == 'high'
                  ? Colors.orange
                  : Colors.blue;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isCompleted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: isCompleted ? Colors.black87 : Colors.grey[600],
                      fontWeight:
                          isCompleted ? FontWeight.w500 : FontWeight.normal,
                      decoration: isCompleted
                          ? TextDecoration.none
                          : TextDecoration.none,
                    ),
                  ),
                ),
                if (!isCompleted)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: importanceColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: importanceColor.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      importance,
                      style: TextStyle(
                        fontSize: 9,
                        color: importanceColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAIInsights(Map<String, dynamic> insights) {
    final recommendations = insights['recommendations'] as List<dynamic>? ?? [];
    final challenges = insights['challenges'] as List<dynamic>? ?? [];
    final budgetTips = insights['budgetTips'] as List<dynamic>? ?? [];
    final alternatives = insights['alternatives'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '💡 AI Recommendations',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: recommendations
                .map((rec) => _buildKeywordChip(rec.toString(), Colors.green))
                .toList(),
          ),
        ],
        if (challenges.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '⚠️ Potential Challenges',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: challenges
                .map((challenge) =>
                    _buildKeywordChip(challenge.toString(), Colors.orange))
                .toList(),
          ),
        ],
        if (budgetTips.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '💰 Budget Tips',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: budgetTips
                .map((tip) => _buildKeywordChip(tip.toString(), Colors.blue))
                .toList(),
          ),
        ],
        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '🔄 Alternative Options',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: alternatives
                .map((alt) => _buildKeywordChip(alt.toString(), Colors.purple))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildKeywordChip(String keyword, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        keyword,
        style: TextStyle(
          fontSize: 11,
          color: color.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
