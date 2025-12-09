import '../models/question.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';
import 'db_service.dart';
import 'package:flutter/foundation.dart';

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
    AnswerMap answers, Question q, bool isEditMode, String? surveyId);

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
    'survey_id': _computeSurveyId,

    // Add more automatic variables here ...
  };

  /// Public entry point: returns existing answer if present,
  /// otherwise computes once and stores it in `answers`.
  /// In edit mode, preserves certain fields like uniqueid, starttime, stoptime
  static Future<String> compute(AnswerMap answers, Question q,
      {bool isEditMode = false, String? surveyId}) async {
    final key = q.fieldName;
    final existing = answers[key];

    // Debug logging for preservation logic
    if (key == 'starttime' ||
        key == 'stoptime' ||
        key == 'uniqueid' ||
        key == 'intnum' ||
        key == 'vcode' ||
        key == 'lastmod') {
      debugPrint(
          '[AutoFields] computing $key. isEditMode=$isEditMode, existing=$existing (${existing.runtimeType})');
    }

    // In edit mode, preserve existing values for certain fields
    // Fix: check for null or empty string, but allow DateTime objects (which are not strings)
    bool hasValue = existing != null;
    if (existing is String) hasValue = existing.isNotEmpty;

    if (isEditMode && hasValue) {
      // Always preserve these fields in edit mode
      if (key == 'uniqueid' || key == 'starttime' || key == 'stoptime') {
        if (existing is DateTime) return existing.toIso8601String();
        return existing.toString();
      }
      // Fields that should update in edit mode: lastmod, swver, survey_id
      if (key != 'lastmod' && key != 'swver' && key != 'survey_id') {
        return existing;
      }
    }

    // For new records, return existing if present
    if (!isEditMode && existing is String && existing.isNotEmpty) {
      return existing;
    }

    // Check for XML configuration
    if (q.calculation != null) {
      // Check preserve flag
      if (isEditMode &&
          q.calculation!.preserve &&
          existing is String &&
          existing.isNotEmpty) {
        return existing;
      }

      final val = await _executeCalculation(q.calculation!, answers, surveyId);
      answers[key] = val;
      return val;
    }

    final fn = _registry[key];
    if (fn == null) {
      // Fallback if no handler defined for this field
      final val = _defaultValueFor(q);
      answers[key] = val;
      return val;
    }

    final value = fn(answers, q, isEditMode, surveyId);
    answers[key] = value;
    return value;
  }

  static String? _sanitizeField(String? field) {
    if (field == null) return null;
    // Strip [[ and ]] if present
    if (field.startsWith('[[') && field.endsWith(']]')) {
      return field.substring(2, field.length - 2);
    }
    return field;
  }

  static Future<String> _executeCalculation(
      CalculationConfig config, AnswerMap answers, String? surveyId) async {
    try {
      switch (config.type) {
        case 'constant':
          if (config.value == 'NOW_YEAR') return DateTime.now().year.toString();
          if (config.value == 'NOW') return DateTime.now().toIso8601String();
          return config.value ?? '';

        case 'lookup':
          final field = _sanitizeField(config.field);
          if (field != null) {
            return answers[field]?.toString() ?? '';
          }
          return '';

        case 'query':
          if (surveyId == null || config.sql == null) return '';
          try {
            final db = await DbService.getDatabaseForQueries(surveyId);

            // Prepare parameters
            final List<dynamic> args = [];
            String sql = config.sql!;
            final params = config.sqlParams ?? {};

            final paramRegex = RegExp(r'@\w+');
            final matches = paramRegex.allMatches(sql).toList();

            for (final match in matches) {
              final paramName = match.group(0)!;
              final rawFieldName = params[paramName];
              final fieldName = _sanitizeField(rawFieldName);

              final val = fieldName != null
                  ? (answers[fieldName]?.toString() ?? '')
                  : '';
              args.add(val);
            }

            // Replace all @param with ?
            sql = sql.replaceAll(paramRegex, '?');

            final results = await db.rawQuery(sql, args);
            if (results.isNotEmpty && results.first.values.isNotEmpty) {
              return results.first.values.first?.toString() ?? '';
            }
            return '';
          } catch (e) {
            print('Error executing auto field query: $e');
            return '';
          }

        case 'concat':
          if (config.parts == null) return '';
          final buffer = StringBuffer();
          for (int i = 0; i < config.parts!.length; i++) {
            if (i > 0 && config.separator != null) {
              buffer.write(config.separator);
            }
            buffer.write(
                await _executeCalculation(config.parts![i], answers, surveyId));
          }
          return buffer.toString();

        case 'math':
          if (config.parts == null || config.parts!.isEmpty) return '';
          double result = 0;

          // Evaluate first part
          final firstVal = double.tryParse(await _executeCalculation(
                  config.parts![0], answers, surveyId)) ??
              0;
          result = firstVal;

          // Apply subsequent parts
          for (int i = 1; i < config.parts!.length; i++) {
            final val = double.tryParse(await _executeCalculation(
                    config.parts![i], answers, surveyId)) ??
                0;
            switch (config.operator) {
              case '+':
                result += val;
                break;
              case '-':
                result -= val;
                break;
              case '*':
                result *= val;
                break;
              case '/':
                if (val != 0) result /= val;
                break;
            }
          }
          // Return as integer if it's a whole number, else double
          if (result == result.roundToDouble()) {
            return result.toInt().toString();
          }
          return result.toString();

        case 'case':
          if (config.cases != null) {
            for (final c in config.cases!) {
              final field = _sanitizeField(c.field);
              final val = answers[field]?.toString() ?? '';
              bool match = false;

              switch (c.operator) {
                case '=':
                  match = val == c.value;
                  break;
                case '!=':
                  match = val != c.value;
                  break;
                case '>':
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) match = v1 > v2;
                  break;
                case '<':
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) match = v1 < v2;
                  break;
                case '>=':
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) match = v1 >= v2;
                  break;
                case '<=':
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) match = v1 <= v2;
                  break;
              }

              if (match) {
                return await _executeCalculation(c.result, answers, surveyId);
              }
            }
          }
          if (config.defaultValue != null) {
            return await _executeCalculation(
                config.defaultValue!, answers, surveyId);
          }
          return '';

        default:
          return '';
      }
    } catch (e) {
      print('Error executing calculation: $e');
      return '';
    }
  }

  static String _computeStartTime(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // In edit mode, preserve existing starttime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeStopTime(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // Same idea as starttime: when this automatic question is *shown*,
    // we stamp the stop time. You *do not* need to set it in _showDone().
    // In edit mode, preserve existing stoptime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeLastModified(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // Last modified timestamp - updates whenever any answer changes
    // This ALWAYS updates, even in edit mode
    return DateTime.now().toIso8601String();
  }

  static String _computeSoftwareVersion(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    return AppConfig.softwareVersion;
  }

  static String _computeSurveyId(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    return surveyId ?? 'unknown';
  }

  static String _computeUniqueId(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
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
