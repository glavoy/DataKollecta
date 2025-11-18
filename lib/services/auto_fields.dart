// import 'dart:math';
import '../models/question.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';
import 'id_generator.dart';
import 'package:flutter/material.dart';

/// This is the ONLY file a programmer edits for automatic variables.
/// Add/edit entries in [_registry] to support new automatic fields.
///
/// Signature:
///   String function(AnswerMap answers, Question q)
/// - `answers` contains what the user has already answered (useful for deps)
/// - `q` is the current question (has fieldName, fieldType, etc.)
///
/// Rules:
/// - Return a STRING. Convert to string if needed.
/// - Keep pure/side-effect-free if possible; if you must do async (e.g. GPS),
///   you can later make this Future and await. For now we keep it sync.

typedef AutoFieldFn = String Function(AnswerMap answers, Question q, bool isEditMode);

class AutoFields {
  /// Context for ID generation - set by SurveyScreen
  static String? _tableName;
  static String? _idConfig;
  static String? _linkingField;

  /// Set the context for ID generation
  static void setIdGenerationContext({
    String? tableName,
    String? idConfig,
    String? linkingField,
  }) {
    _tableName = tableName;
    _idConfig = idConfig;
    _linkingField = linkingField;
  }

  /// Clear the context after survey completion
  static void clearIdGenerationContext() {
    _tableName = null;
    _idConfig = null;
    _linkingField = null;
  }

  /// Asynchronously generates an ID if needed
  /// Call this when all required fields for ID generation are available
  static Future<String?> generateIdIfNeeded({
    required AnswerMap answers,
    required String fieldName,
  }) async {
    // Check if ID is already set
    final existing = answers[fieldName];
    if (existing != null && existing.toString().isNotEmpty && existing != '_PENDING_ID_GENERATION_') {
      return null; // ID already set
    }

    // Check if we have the necessary configuration
    if (_idConfig == null || _tableName == null) {
      return null; // No configuration
    }

    // Validate that all required fields are present
    if (!IdGenerator.validateIdFields(
      idConfigJson: _idConfig!,
      answers: answers,
    )) {
      return null; // Not all required fields available
    }

    // Generate the ID
    try {
      final generatedId = await IdGenerator.generateId(
        tableName: _tableName!,
        idConfigJson: _idConfig!,
        answers: answers,
      );

      // Update the answers map
      answers[fieldName] = generatedId;
      return generatedId;
    } catch (e) {
      debugPrint('Error generating ID: $e');
      return null;
    }
  }

  /// Per-survey registry of automatic fields: fieldName -> function
  /// Edit this map for your survey's automatic variables.
  static final Map<String, AutoFieldFn> _registry = {
    'uniqueid': _computeUniqueId,
    'starttime': _computeStartTime,
    'stoptime': _computeStopTime,
    'lastmod': _computeLastModified,
    'swver': _computeSoftwareVersion,
    'subjid': _computeSubjId,  // Now enabled for dynamic ID generation
    'hhid': _computeSubjId,    // Use same function for household IDs
    // Add more automatic variables here ...
  };

  /// Public entry point: returns existing answer if present,
  /// otherwise computes once and stores it in `answers`.
  /// In edit mode, preserves certain fields like uniqueid, starttime, stoptime
  static String compute(AnswerMap answers, Question q, {bool isEditMode = false}) {
    final key = q.fieldName;
    final existing = answers[key];

    // In edit mode, preserve existing values for certain fields
    if (isEditMode && existing is String && existing.isNotEmpty) {
      // Always preserve these fields in edit mode
      if (key == 'uniqueid' || key == 'starttime' || key == 'stoptime') {
        return existing;
      }
      // For lastmod, we want to update it even in edit mode
      if (key != 'lastmod') {
        return existing;
      }
    }

    // For new records, return existing if present
    if (!isEditMode && existing is String && existing.isNotEmpty) {
      return existing;
    }

    final fn = _registry[key];
    if (fn == null) {
      // Fallback if no handler defined for this field
      final val = _defaultValueFor(q);
      answers[key] = val;
      return val;
    }

    final value = fn(answers, q, isEditMode);
    answers[key] = value;
    return value;
  }

  static String _computeStartTime(AnswerMap answers, Question q, bool isEditMode) {
    // In edit mode, preserve existing starttime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeStopTime(AnswerMap answers, Question q, bool isEditMode) {
    // Same idea as starttime: when this automatic question is *shown*,
    // we stamp the stop time. You *do not* need to set it in _showDone().
    // In edit mode, preserve existing stoptime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeLastModified(AnswerMap answers, Question q, bool isEditMode) {
    // Last modified timestamp - updates whenever any answer changes
    // This ALWAYS updates, even in edit mode
    return DateTime.now().toIso8601String();
  }

  static String _computeSoftwareVersion(AnswerMap answers, Question q, bool isEditMode) {
    return AppConfig.softwareVersion;
  }

  static String _computeUniqueId(AnswerMap answers, Question q, bool isEditMode) {
    // Generate once per record.
    // In edit mode, preserve existing uniqueid (handled in compute method)
    const uuid = Uuid();
    return uuid.v4();
  }

  /// Update record-level last modified timestamp.
  /// Call this whenever *any* answer changes.
  static void touchLastMod(AnswerMap answers) => _touchLastMod(answers);

  static void _touchLastMod(AnswerMap answers) {
    answers['lastmod'] = DateTime.now().toIso8601String();
  }

  /// Computes subject ID or household ID based on configuration
  /// This function generates IDs dynamically based on:
  /// 1. If prepopulated (from parent selector) - return existing value
  /// 2. If base form with idConfig - generate new ID using IdGenerator
  /// 3. Otherwise return placeholder
  static String _computeSubjId(AnswerMap answers, Question q, bool isEditMode) {
    final fieldName = q.fieldName;

    // In edit mode, preserve existing ID
    if (isEditMode) {
      final existing = answers[fieldName];
      if (existing != null && existing.toString().isNotEmpty) {
        return existing.toString();
      }
    }

    // If already populated (e.g., from parent ID selector), use that value
    final existing = answers[fieldName];
    if (existing != null && existing.toString().isNotEmpty) {
      return existing.toString();
    }

    // If we have idConfig, this is a base form - generate new ID
    if (_idConfig != null && _tableName != null) {
      debugPrint('Generating ID for field: $fieldName, table: $_tableName');

      // Check if all required fields are present
      if (IdGenerator.validateIdFields(
        idConfigJson: _idConfig!,
        answers: answers,
      )) {
        // Generate ID asynchronously - we'll need to handle this differently
        // For now, return a placeholder and let the survey screen handle async generation
        return '_PENDING_ID_GENERATION_';
      } else {
        // Not all required fields available yet
        debugPrint('Required fields for ID generation not yet available');
        return '';
      }
    }

    // No configuration available - shouldn't happen in production
    debugPrint('Warning: No ID config available for $fieldName');
    return '';
  }

  // ---------- Default/fallbacks ----------

  static String _defaultValueFor(Question q) {
    switch (q.fieldType.toLowerCase()) {
      case 'datetime':
        return DateTime.now().toIso8601String();
      case 'date':
        return DateTime.now().toIso8601String().split('T')[0];
      default:
        return '-9';
    }
  }
}

