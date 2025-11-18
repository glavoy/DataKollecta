import '../models/question.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';
// import 'id_generator.dart';
// import 'package:flutter/material.dart';

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

typedef AutoFieldFn = String Function(
    AnswerMap answers, Question q, bool isEditMode);

class AutoFields {
  /// Public getter for the registry
  static Map<String, AutoFieldFn> getRegistry() => _registry;

  /// Per-survey registry of automatic fields: fieldName -> function
  /// Edit this map for your survey's automatic variables.
  static final Map<String, AutoFieldFn> _registry = {
    'uniqueid': _computeUniqueId,
    'starttime': _computeStartTime,
    'stoptime': _computeStopTime,
    'lastmod': _computeLastModified,
    'swver': _computeSoftwareVersion,
    // 'subjid': _computeSubjId,  // This is now handled in SurveyScreen._showDone
    // 'hhid': _computeSubjId,    // This is now handled in SurveyScreen._showDone
    // Add more automatic variables here ...
  };

  /// Public entry point: returns existing answer if present,
  /// otherwise computes once and stores it in `answers`.
  /// In edit mode, preserves certain fields like uniqueid, starttime, stoptime
  static String compute(AnswerMap answers, Question q,
      {bool isEditMode = false}) {
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

  static String _computeStartTime(
      AnswerMap answers, Question q, bool isEditMode) {
    // In edit mode, preserve existing starttime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeStopTime(
      AnswerMap answers, Question q, bool isEditMode) {
    // Same idea as starttime: when this automatic question is *shown*,
    // we stamp the stop time. You *do not* need to set it in _showDone().
    // In edit mode, preserve existing stoptime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeLastModified(
      AnswerMap answers, Question q, bool isEditMode) {
    // Last modified timestamp - updates whenever any answer changes
    // This ALWAYS updates, even in edit mode
    return DateTime.now().toIso8601String();
  }

  static String _computeSoftwareVersion(
      AnswerMap answers, Question q, bool isEditMode) {
    return AppConfig.softwareVersion;
  }

  static String _computeUniqueId(
      AnswerMap answers, Question q, bool isEditMode) {
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
