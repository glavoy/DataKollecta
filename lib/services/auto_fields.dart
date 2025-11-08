// import 'dart:math';
import '../models/question.dart';
import 'package:uuid/uuid.dart';

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
    'uniqueid': _computeUniqueId,
    'starttime': _computeStartTime,
    'stoptime': _computeStopTime,
    // 'lastmod': _computeLastModified,
    'swver': _computeSoftwareVersion,
    // 'subjid': _computeSubjId,
    // Add more automatic variables here ...

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

  static String _computeStartTime(AnswerMap answers, Question q) {
    return DateTime.now().toIso8601String();
  }

  static String _computeStopTime(AnswerMap answers, Question q) {
    // Same idea as starttime: when this automatic question is *shown*,
    // we stamp the stop time. You *do not* need to set it in _showDone().
    return DateTime.now().toIso8601String();
  }

  static String _computeSoftwareVersion(AnswerMap answers, Question q) {
    return '1.0.0'; // replace later if you fetch from platform
  }

  static String _computeUniqueId(AnswerMap answers, Question q) {
    // Generate once per record.
    const uuid = Uuid();
    return uuid.v4();
  }

  /// Update record-level last modified timestamp.
  /// Call this whenever *any* answer changes.
  static void touchLastMod(AnswerMap answers) => _touchLastMod(answers);

  static void _touchLastMod(AnswerMap answers) {
    answers['lastmod'] = DateTime.now().toIso8601String();
  }

  // static String _computeSubjId(AnswerMap answers, Question q) {
  //   final r = Random();
  //   return 'SP${r.nextInt(999999).toString().padLeft(6, '0')}';
  // }

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
