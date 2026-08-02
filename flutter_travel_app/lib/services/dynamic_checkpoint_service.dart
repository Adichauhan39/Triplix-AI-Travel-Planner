import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../models/user_preferences.dart';

/// Dynamic Checkpoint Service - Uses AI to analyze user preferences
/// and provide intelligent insights and recommendations with structured checkpoints
class DynamicCheckpointService {
  // Python FastAPI backend URL
  static const String _baseUrl = AppConfig.baseUrl;

  String _formatBudget(UserPreferences preferences) {
    if (preferences.budget == null) return 'Not specified';
    final code = preferences.budgetCurrencyCode.toUpperCase();
    try {
      final symbol = NumberFormat.simpleCurrency(name: code).currencySymbol;
      return '$symbol${preferences.budget!.toStringAsFixed(0)} $code';
    } catch (_) {
      return '${preferences.budget!.toStringAsFixed(0)} $code';
    }
  }

  /// Get AI-powered insights for user preferences with checkpoint tracking
  Future<Map<String, dynamic>> getCheckpointInsights(
      UserPreferences preferences) async {
    try {
      // First, generate checkpoint plan
      final checkpointPlan = _generateCheckpointPlan(preferences);

      // Check if Python backend is available
      final backendAvailable = await _isBackendAvailable();

      Map<String, dynamic> insights;
      if (backendAvailable) {
        insights = await _getPythonBackendInsights(preferences, checkpointPlan);
      } else {
        insights = _getFallbackInsights(preferences);
      }

      // Add checkpoint plan to insights
      insights['checkpointPlan'] = checkpointPlan;
      insights['completionPercentage'] =
          _calculateCompletionPercentage(checkpointPlan);

      return insights;
    } catch (e) {
      print('Error getting checkpoint insights: $e');
      final fallback = _getFallbackInsights(preferences);
      fallback['checkpointPlan'] = _generateCheckpointPlan(preferences);
      fallback['completionPercentage'] =
          _calculateCompletionPercentage(fallback['checkpointPlan']);
      return fallback;
    }
  }

  /// Generate structured checkpoint plan (like AI platforms do)
  Map<String, dynamic> _generateCheckpointPlan(UserPreferences preferences) {
    final List<Map<String, dynamic>> checkpoints = [
      {
        'id': 'destination',
        'title': 'Destination Selection',
        'description': 'Where you want to go',
        'completed': preferences.hasDestination,
        'importance': 'critical',
        'data': preferences.destination,
      },
      {
        'id': 'budget',
        'title': 'Budget Planning',
        'description': 'How much you want to spend',
        'completed': preferences.hasBudget,
        'importance': 'critical',
        'data': preferences.hasBudget ? _formatBudget(preferences) : null,
      },
      {
        'id': 'activities',
        'title': 'Activities & Experiences',
        'description': 'What you want to do',
        'completed': preferences.hasActivities,
        'importance': 'high',
        'data': preferences.selectedActivities,
      },
      {
        'id': 'transport',
        'title': 'Transportation',
        'description': 'How you want to travel',
        'completed': preferences.hasTransport,
        'importance': 'high',
        'data': preferences.selectedTransport,
      },
      {
        'id': 'accommodation',
        'title': 'Accommodation',
        'description': 'Where you want to stay',
        'completed': preferences.hasAccommodation,
        'importance': 'high',
        'data': preferences.selectedAccommodation,
      },
      {
        'id': 'destination_prefs',
        'title': 'Destination Preferences',
        'description': 'Climate, terrain, culture preferences',
        'completed': preferences.hasDestinationPreferences,
        'importance': 'medium',
        'data': {
          'climates': preferences.selectedClimates,
          'terrains': preferences.selectedTerrains,
          'cultures': preferences.selectedCultures,
        },
      },
      {
        'id': 'travel_context',
        'title': 'Travel Context',
        'description': 'Who you\'re traveling with and why',
        'completed': preferences.hasCompanion || preferences.hasOccasion,
        'importance': 'medium',
        'data': {
          'companion': preferences.companion,
          'occasion': preferences.occasion,
          'people': preferences.numberOfPeople,
        },
      },
      {
        'id': 'special_needs',
        'title': 'Special Requirements',
        'description': 'Accessibility, dietary, medical needs',
        'completed': preferences.selectedAccessibility.isNotEmpty ||
            preferences.selectedDietary.isNotEmpty ||
            preferences.selectedMedical.isNotEmpty,
        'importance': 'low',
        'data': {
          'accessibility': preferences.selectedAccessibility,
          'dietary': preferences.selectedDietary,
          'medical': preferences.selectedMedical,
        },
      },
    ];

    return {
      'checkpoints': checkpoints,
      'totalCheckpoints': checkpoints.length,
      'completedCheckpoints':
          checkpoints.where((c) => c['completed'] == true).length,
      'criticalCompleted': checkpoints
          .where((c) => c['importance'] == 'critical' && c['completed'] == true)
          .length,
      'criticalTotal':
          checkpoints.where((c) => c['importance'] == 'critical').length,
    };
  }

  /// Calculate completion percentage
  double _calculateCompletionPercentage(Map<String, dynamic> plan) {
    final total = plan['totalCheckpoints'] as int;
    final completed = plan['completedCheckpoints'] as int;
    return total > 0 ? (completed / total * 100) : 0;
  }

  /// Check if Python backend is running
  Future<bool> _isBackendAvailable() async {
    try {
      final response = await http
          .get(Uri.parse(_baseUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      print('Python backend not available: $e');
      return false;
    }
  }

  /// Get insights from Python ADK backend with checkpoint context
  Future<Map<String, dynamic>> _getPythonBackendInsights(
      UserPreferences preferences, Map<String, dynamic> checkpointPlan) async {
    final prompt = _buildPreferenceAnalysisPrompt(preferences, checkpointPlan);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/agent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': prompt,
          'context': preferences.toJson(),
          'checkpoint_plan': checkpointPlan,
          'agent_type': 'checkpoint_analyzer'
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseBackendResponse(data);
      }
    } catch (e) {
      print('Python backend error: $e');
    }

    return _getFallbackInsights(preferences);
  }

  /// Parse response from Python backend
  Map<String, dynamic> _parseBackendResponse(Map<String, dynamic> data) {
    return {
      'summary':
          data['summary'] ?? 'Your travel preferences are being analyzed...',
      'recommendations': data['recommendations'] ?? [],
      'challenges': data['challenges'] ?? [],
      'budgetTips': data['budget_tips'] ?? [],
      'alternatives': data['alternatives'] ?? [],
      'confidence': data['confidence'] ?? 0.8,
      'lastUpdated': DateTime.now(),
    };
  }

  /// Build analysis prompt for user preferences with checkpoint context
  String _buildPreferenceAnalysisPrompt(
      UserPreferences preferences, Map<String, dynamic> checkpointPlan) {
    final completionPct = checkpointPlan['completedCheckpoints'] /
        checkpointPlan['totalCheckpoints'] *
        100;
    final checkpoints = checkpointPlan['checkpoints'] as List;
    final completedCheckpoints =
        checkpoints.where((c) => c['completed'] == true).toList();
    final pendingCheckpoints =
        checkpoints.where((c) => c['completed'] == false).toList();

    return '''
You are an AI travel planning assistant. Analyze the user's travel preferences using a structured checkpoint approach.

CHECKPOINT PROGRESS: ${completionPct.toStringAsFixed(0)}% Complete (${checkpointPlan['completedCheckpoints']}/${checkpointPlan['totalCheckpoints']} checkpoints)

COMPLETED CHECKPOINTS:
${completedCheckpoints.map((c) => '✓ ${c['title']}: ${_formatCheckpointData(c['data'])}').join('\n')}

PENDING CHECKPOINTS:
${pendingCheckpoints.map((c) => '○ ${c['title']} [${c['importance']}]: ${c['description']}').join('\n')}

CURRENT TRAVEL PREFERENCES:
DESTINATION: ${preferences.destination ?? 'Not specified'}
BUDGET: ${_formatBudget(preferences)}

ACTIVITIES: ${preferences.selectedActivities.isNotEmpty ? preferences.selectedActivities.join(', ') : 'None selected'}
TRANSPORT: ${preferences.selectedTransport.isNotEmpty ? preferences.selectedTransport.join(', ') : 'None selected'}
ACCOMMODATION: ${preferences.selectedAccommodation.isNotEmpty ? preferences.selectedAccommodation.join(', ') : 'None selected'}

DESTINATION PREFERENCES:
- Climates: ${preferences.selectedClimates.isNotEmpty ? preferences.selectedClimates.join(', ') : 'None'}
- Terrains: ${preferences.selectedTerrains.isNotEmpty ? preferences.selectedTerrains.join(', ') : 'None'}
- Cultures: ${preferences.selectedCultures.isNotEmpty ? preferences.selectedCultures.join(', ') : 'None'}

TRAVEL CONTEXT:
- Companion: ${preferences.companion ?? 'Not specified'}
- Occasion: ${preferences.occasion ?? 'Not specified'}
- Experience: ${preferences.experience ?? 'Not specified'}
- People: ${preferences.numberOfPeople ?? 'Not specified'}

SPECIAL REQUIREMENTS:
- Accessibility: ${preferences.selectedAccessibility.isNotEmpty ? preferences.selectedAccessibility.join(', ') : 'None'}
- Dietary: ${preferences.selectedDietary.isNotEmpty ? preferences.selectedDietary.join(', ') : 'None'}
- Medical: ${preferences.selectedMedical.isNotEmpty ? preferences.selectedMedical.join(', ') : 'None'}
- Languages: ${preferences.selectedLanguages.isNotEmpty ? preferences.selectedLanguages.join(', ') : 'None'}

Based on the checkpoint analysis, provide:
1. A personalized summary highlighting what's complete and what's needed
2. Smart recommendations based on COMPLETED checkpoints
3. Specific guidance on PENDING critical checkpoints
4. Budget optimization suggestions if budget is set
5. Alternative options considering their current preferences

Keep responses actionable and checkpoint-focused. Prioritize critical checkpoints.
''';
  }

  /// Format checkpoint data for display
  String _formatCheckpointData(dynamic data) {
    if (data == null) return 'Not set';
    if (data is String) return data;
    if (data is List) return data.isNotEmpty ? data.join(', ') : 'None';
    if (data is Map) {
      final entries = (data as Map<String, dynamic>)
          .entries
          .where((e) => e.value != null && e.value.toString().isNotEmpty)
          .map((e) => '${e.key}: ${e.value}');
      return entries.isNotEmpty ? entries.join(', ') : 'None';
    }
    return data.toString();
  }

  /// Fallback insights when AI is unavailable - checkpoint-based
  Map<String, dynamic> _getFallbackInsights(UserPreferences preferences) {
    // Generate checkpoint-aware summary
    List<String> completedAreas = [];
    List<String> pendingAreas = [];

    if (preferences.hasDestination) {
      completedAreas.add('destination (${preferences.destination})');
    } else {
      pendingAreas.add('destination selection');
    }

    if (preferences.hasBudget) {
      completedAreas.add('budget (${_formatBudget(preferences)})');
    } else {
      pendingAreas.add('budget planning');
    }

    if (preferences.hasActivities) {
      completedAreas.add('activities');
    } else {
      pendingAreas.add('activity preferences');
    }

    String summary;
    if (completedAreas.isEmpty) {
      summary =
          '📋 Let\'s start planning your trip! Complete the checkpoints to get personalized recommendations.';
    } else if (pendingAreas.isEmpty) {
      summary =
          '✨ Your travel profile is complete! Ready to find the perfect ${preferences.destination} experience.';
    } else {
      summary =
          '📊 Progress: ${completedAreas.join(', ')} set. Still need: ${pendingAreas.join(', ')}.';
    }

    // Checkpoint-based recommendations
    List<String> recommendations = [];

    if (!preferences.hasBudget) {
      recommendations.add(
          '💰 Set your budget first - it\'s critical for tailored recommendations');
    }
    if (!preferences.hasDestination) {
      recommendations.add(
          '📍 Choose your destination - this unlocks location-specific suggestions');
    }
    if (preferences.hasBudget && preferences.hasDestination) {
      final budgetLevel = preferences.budget! < 10000
          ? 'budget'
          : preferences.budget! < 50000
              ? 'moderate'
              : 'luxury';
      recommendations.add(
          '🎯 Your $budgetLevel budget works great for ${preferences.destination}');
    }
    if (preferences.selectedActivities.isNotEmpty) {
      recommendations.add(
          '🎨 ${preferences.selectedActivities.first} activities will enhance your experience');
    } else {
      recommendations.add('🎭 Add activities to discover unique experiences');
    }
    if (preferences.selectedTransport.isEmpty) {
      recommendations
          .add('🚗 Select transport preferences for better route planning');
    }

    // Checkpoint-based challenges
    List<String> challenges = [];
    if (pendingAreas.isNotEmpty) {
      challenges.add(
          '⚠️ ${pendingAreas.length} critical checkpoint${pendingAreas.length > 1 ? 's' : ''} pending');
    }
    if (preferences.hasBudget && preferences.budget! < 5000) {
      challenges.add('💡 Low budget may limit accommodation options');
    }

    return {
      'summary': summary,
      'recommendations': recommendations.take(5).toList(),
      'challenges': challenges,
      'budgetTips': preferences.hasBudget
          ? [
              'Track expenses daily',
              'Book in advance for better rates',
              'Consider off-peak travel'
            ]
          : ['Set a budget to unlock financial insights'],
      'alternatives': preferences.hasDestination
          ? [
              'Explore nearby ${preferences.destination}',
              'Consider different seasons'
            ]
          : ['Browse popular destinations first'],
      'confidence': 0.3,
      'lastUpdated': DateTime.now(),
    };
  }

  /// Get travel compatibility score
  Future<double> getCompatibilityScore(UserPreferences preferences) async {
    try {
      final insights = await getCheckpointInsights(preferences);
      return insights['confidence'] ?? 0.5;
    } catch (e) {
      return 0.5;
    }
  }

  /// Get personalized destination suggestions
  Future<List<String>> getDestinationSuggestions(
      UserPreferences preferences) async {
    try {
      final insights = await getCheckpointInsights(preferences);
      final alternatives = insights['alternatives'] as List<dynamic>? ?? [];
      return alternatives.map((alt) => alt.toString()).toList();
    } catch (e) {
      return [];
    }
  }
}
