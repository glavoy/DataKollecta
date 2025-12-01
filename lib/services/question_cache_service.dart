import 'dart:io';
import '../models/question.dart';
import 'survey_loader.dart';

/// Service to cache question definitions from all XML files for a survey
/// This enables fast lookup of option labels for display purposes
class QuestionCacheService {
  static final QuestionCacheService _instance = QuestionCacheService._internal();
  factory QuestionCacheService() => _instance;
  QuestionCacheService._internal();

  // Cache: fieldName -> Question
  final Map<String, Question> _questionCache = {};
  String? _cachedSurveyId;

  /// Load all questions from all XML files in the survey
  Future<void> loadQuestionsForSurvey({
    required String surveyId,
    required String surveyDirectory,
    required List<String> xmlFiles,
  }) async {
    // Only reload if it's a different survey
    if (_cachedSurveyId == surveyId && _questionCache.isNotEmpty) {
      return;
    }

    _questionCache.clear();
    _cachedSurveyId = surveyId;

    // Load all XML files
    for (final xmlFile in xmlFiles) {
      try {
        final filePath = '$surveyDirectory/$xmlFile';
        final file = File(filePath);

        if (!await file.exists()) {
          continue; // Skip missing files
        }

        final questions = await SurveyLoader.loadFromFile(file);

        // Add each question to the cache
        for (final question in questions) {
          _questionCache[question.fieldName] = question;
        }
      } catch (e) {
        // Log error but continue loading other files
        print('Error loading XML file $xmlFile: $e');
      }
    }
  }

  /// Get the display label for a field value
  /// Supports [[fieldname]] syntax to lookup option labels
  /// Returns the original value if no label is found
  String getDisplayValue(String displayFieldPattern, Map<String, dynamic> record) {
    // Check if pattern uses [[fieldname]] syntax
    final match = RegExp(r'^\[\[(.+?)\]\]$').firstMatch(displayFieldPattern);

    if (match != null) {
      // Extract field name from [[fieldname]]
      final fieldName = match.group(1)!;
      final question = _questionCache[fieldName];

      if (question != null) {
        // Get the stored value from the record
        final storedValue = record[fieldName]?.toString();

        if (storedValue != null && storedValue.isNotEmpty) {
          // Only process static responses for now
          if (question.responseConfig?.source == ResponseSource.static_ ||
              question.responseConfig == null) {
            // Find the matching option
            final option = question.options.firstWhere(
              (opt) => opt.value == storedValue,
              orElse: () => QuestionOption(value: storedValue, label: storedValue),
            );
            return option.label;
          }
        }

        // Return the stored value if no label found
        return storedValue ?? '';
      }

      // Field not in cache, return the stored value
      final storedValue = record[fieldName]?.toString();
      return storedValue ?? '';
    } else {
      // Not using [[...]] syntax, just return the field value directly
      final value = record[displayFieldPattern]?.toString();
      return value ?? '';
    }
  }

  /// Clear the cache (useful when switching surveys)
  void clearCache() {
    _questionCache.clear();
    _cachedSurveyId = null;
  }

  /// Get a question from the cache by field name
  Question? getQuestion(String fieldName) {
    return _questionCache[fieldName];
  }

  /// Check if questions are loaded for a survey
  bool isLoadedForSurvey(String surveyId) {
    return _cachedSurveyId == surveyId && _questionCache.isNotEmpty;
  }
}
