// lib/services/auto_fields.dart
import 'dart:math';
import '../models/question.dart';

const swVer = "0.0.3";

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

typedef AutoFieldFn = String Function(AnswerMap answers, Question q);

class AutoFields {
  /// Per-survey registry of automatic fields: fieldName -> function
  /// Edit this map for your survey’s automatic variables.
  static final Map<String, AutoFieldFn> _registry = {
    // EXAMPLES — replace/extend as needed:
    'starttime': _computeStartTime,
    'swver': _computeSoftwareVersion,
    'subjid': _computeSubjId,
    // Add more:
    // 'subjid': (answers, q) => _generateSubjectId(answers, q),
  };

  /// Public entry point: returns existing answer if present,
  /// otherwise computes once and stores it in `answers`.
  static String compute(AnswerMap answers, Question q) {
    final key = q.fieldName;
    final existing = answers[key];
    if (existing is String && existing.isNotEmpty) return existing;

    final fn = _registry[key];
    if (fn == null) {
      // Fallback if no handler defined for this field
      final val = _defaultValueFor(q);
      answers[key] = val;
      return val;
    }

    final value = fn(answers, q);
    answers[key] = value;
    return value;
  }

  // ---------- Example handlers (customize per survey) ----------

  static String _computeStartTime(AnswerMap answers, Question q) {
    // ISO local time; pick a format your backend expects
    return DateTime.now().toIso8601String();
  }

  static String _computeSoftwareVersion(AnswerMap answers, Question q) {
    return swVer;
  }

  static String _computeSubjId(AnswerMap answers, Question q) {
    final r = Random();
    return 'SP${r.nextInt(999999).toString().padLeft(6, '0')}';
  }

  // ---------- Default/fallbacks ----------

  static String _defaultValueFor(Question q) {
    switch (q.fieldType.toLowerCase()) {
      case 'datetime':
        return DateTime.now().toIso8601String();
      case 'integer':
        return '0';
      default:
        return 'auto';
    }
  }
}
