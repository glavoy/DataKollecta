import '../models/question.dart';
import 'package:uuid/uuid.dart';
import 'db_service.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  /// Cached software version from pubspec.yaml
  static String? _cachedVersion;

  /// Public getter for the registry
  static Map<String, AutoFieldFn> getRegistry() => _registry;

  /// System fields that are automatically added to every CRF table.
  /// These don't need to be defined in XML files.
  /// Order: starttime, startdate first; then uuid, swver, survey_id, lastmod, stoptime, synced_at at end
  static const List<String> systemFieldsStart = ['starttime', 'startdate'];
  static const List<String> systemFieldsEnd = [
    'uuid',
    'swver',
    'survey_id',
    'lastmod',
    'stoptime',
    'synced_at'
  ];

  /// Per-survey registry of automatic fields: fieldName -> function
  /// Edit this map for your survey's automatic variables.
  static final Map<String, AutoFieldFn> _registry = {
    'uuid': _computeUuid,
    'starttime': _computeStartTime,
    'startdate': _computeStartDate,
    'stoptime': _computeStopTime,
    'lastmod': _computeLastModified,
    'swver': _computeSoftwareVersion,
    'survey_id': _computeSurveyId,

    // Add more automatic variables here ...
  };

  /// Public entry point: returns existing answer if present,
  /// otherwise computes once and stores it in `answers`.
  /// In edit mode, preserves certain fields like uuid, starttime, stoptime
  static Future<String?> compute(AnswerMap answers, Question q,
      {bool isEditMode = false, String? surveyId}) async {
    // Load version from pubspec.yaml once and cache it
    if (_cachedVersion == null) {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        _cachedVersion = 'DataKollecta ${packageInfo.version}';
      } catch (e) {
        debugPrint('[AutoFields] Error loading version from pubspec.yaml: $e');
        _cachedVersion = 'DataKollecta unknown';
      }
    }

    final key = q.fieldName;
    final existing = answers[key];

    // Debug logging for preservation logic
    if (key == 'starttime' ||
        key == 'startdate' ||
        key == 'stoptime' ||
        key == 'uuid' ||
        key == 'intnum' ||
        key == 'vcode' ||
        key == 'lastmod') {
      debugPrint(
          '[AutoFields] computing $key. isEditMode=$isEditMode, existing=$existing (${existing.runtimeType})');
    }

    // In edit mode, preserve existing values ONLY for special system fields
    // that should never change (uuid, starttime, stoptime)
    // All other fields (including calculations) should be recalculated
    bool hasValue = existing != null;
    if (existing is String) hasValue = existing.isNotEmpty;

    if (isEditMode && hasValue) {
      // Preserve these special system fields in edit mode
      if (key == 'uuid' ||
          key == 'starttime' ||
          key == 'startdate' ||
          key == 'stoptime') {
        if (existing is DateTime) return existing.toIso8601String();
        return existing.toString();
      }
      // All other fields fall through to be recalculated below
      // (including lastmod, swver, survey_id, and any calculation-based fields)
    }

    // Check for XML configuration first (before checking existing value)
    // This ensures calculation-based fields are always recalculated
    // when their dependencies might have changed
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

    // For new records with registry-based fields, return existing if present
    // (but not for calculation-based fields, which are handled above)
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
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) {
                    match = v1 == v2;
                  } else {
                    match = val == c.value;
                  }
                  break;
                case '!=':
                  final v1 = double.tryParse(val);
                  final v2 = double.tryParse(c.value);
                  if (v1 != null && v2 != null) {
                    match = v1 != v2;
                  } else {
                    match = val != c.value;
                  }
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

        case 'age_from_date':
          return _calculateAgeFromDate(config, answers);

        case 'age_at_date':
          return _calculateAgeAtDate(config, answers);

        case 'date_offset':
          final field = _sanitizeField(config.field);
          if (field == null) return '';
          final baseVal = answers[field]?.toString() ?? '';
          if (baseVal.isEmpty) return '';

          final baseDate = DateTime.tryParse(baseVal);
          if (baseDate == null) return '';

          final offsetStr = config.value ?? '';
          final resultDate = _applyDateOffset(baseDate, offsetStr);
          return resultDate.toIso8601String().split('T')[0];

        case 'date_diff':
          final startFieldName = _sanitizeField(config.field);
          final endFieldName = _sanitizeField(config.value);

          DateTime? startDate;
          DateTime? endDate;

          // Parse start date
          if (startFieldName == 'today') {
            final now = DateTime.now();
            startDate = DateTime(now.year, now.month, now.day);
          } else if (startFieldName != null) {
            final val = answers[startFieldName]?.toString() ?? '';
            if (val.isNotEmpty) startDate = DateTime.tryParse(val);
          }

          // Parse end date
          if (endFieldName == 'today') {
            final now = DateTime.now();
            endDate = DateTime(now.year, now.month, now.day);
          } else if (endFieldName != null) {
            final val = answers[endFieldName]?.toString() ?? '';
            if (val.isNotEmpty) endDate = DateTime.tryParse(val);
          }

          if (startDate == null || endDate == null) return '';

          return _calculateDateDiff(startDate, endDate, config.unit ?? 'd')
              .toString();

        default:
          return '';
      }
    } catch (e) {
      print('Error executing calculation: $e');
      return '';
    }
  }

  /// Calculate age from a date field to today
  /// Returns age in specified unit (years, months, or days)
  static String _calculateAgeFromDate(
      CalculationConfig config, AnswerMap answers) {
    try {
      final dateField = _sanitizeField(config.field);
      if (dateField == null) return '';

      final dateValue = answers[dateField];
      if (dateValue == null) return '';

      DateTime birthDate;
      if (dateValue is DateTime) {
        birthDate = dateValue;
      } else if (dateValue is String) {
        try {
          birthDate = DateTime.parse(dateValue);
        } catch (e) {
          debugPrint('[AutoFields] Error parsing date from $dateField: $e');
          return '';
        }
      } else {
        return '';
      }

      final now = DateTime.now();
      final unit = config.value?.toLowerCase() ?? 'years';

      return _calculateAgeDifference(birthDate, now, unit);
    } catch (e) {
      debugPrint('[AutoFields] Error in age_from_date calculation: $e');
      return '';
    }
  }

  /// Calculate age from a date field to a specific target date
  /// Returns age in specified unit (years, months, or days)
  static String _calculateAgeAtDate(
      CalculationConfig config, AnswerMap answers) {
    try {
      final dateField = _sanitizeField(config.field);
      if (dateField == null) return '';

      final dateValue = answers[dateField];
      if (dateValue == null) return '';

      DateTime birthDate;
      if (dateValue is DateTime) {
        birthDate = dateValue;
      } else if (dateValue is String) {
        try {
          birthDate = DateTime.parse(dateValue);
        } catch (e) {
          debugPrint('[AutoFields] Error parsing date from $dateField: $e');
          return '';
        }
      } else {
        return '';
      }

      // Parse target date from separator attribute
      if (config.separator == null || config.separator!.isEmpty) {
        debugPrint(
            '[AutoFields] age_at_date requires separator attribute with target date');
        return '';
      }

      DateTime targetDate;
      try {
        targetDate = DateTime.parse(config.separator!);
      } catch (e) {
        debugPrint('[AutoFields] Error parsing target date: $e');
        return '';
      }

      final unit = config.value?.toLowerCase() ?? 'years';

      return _calculateAgeDifference(birthDate, targetDate, unit);
    } catch (e) {
      debugPrint('[AutoFields] Error in age_at_date calculation: $e');
      return '';
    }
  }

  /// Helper to calculate age difference between two dates
  static String _calculateAgeDifference(
      DateTime fromDate, DateTime toDate, String unit) {
    switch (unit) {
      case 'years':
        int years = toDate.year - fromDate.year;
        // Adjust if birthday hasn't occurred yet this year
        if (toDate.month < fromDate.month ||
            (toDate.month == fromDate.month && toDate.day < fromDate.day)) {
          years--;
        }
        return years.toString();

      case 'months':
        int months = (toDate.year - fromDate.year) * 12 +
            (toDate.month - fromDate.month);
        // Adjust if day hasn't occurred yet this month
        if (toDate.day < fromDate.day) {
          months--;
        }
        return months.toString();

      case 'days':
        final difference = toDate.difference(fromDate);
        return difference.inDays.toString();

      default:
        debugPrint('[AutoFields] Unknown age unit: $unit. Using years.');
        int years = toDate.year - fromDate.year;
        if (toDate.month < fromDate.month ||
            (toDate.month == fromDate.month && toDate.day < fromDate.day)) {
          years--;
        }
        return years.toString();
    }
  }

  static String _computeStartTime(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // In edit mode, preserve existing starttime (handled in compute method)
    return DateTime.now().toIso8601String();
  }

  static String _computeStartDate(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // In edit mode, preserve existing startdate (handled in compute method)
    return DateTime.now().toIso8601String().split('T')[0];
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
    // Return cached version if available, otherwise return a placeholder
    // The cache is populated by the compute() method
    return _cachedVersion ?? 'unknown';
  }

  static String _computeSurveyId(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    return surveyId ?? 'unknown';
  }

  static String _computeUuid(
      AnswerMap answers, Question q, bool isEditMode, String? surveyId) {
    // Generate once per record.
    // In edit mode, preserve existing uuid (handled in compute method)
    const uuidGen = Uuid();
    return uuidGen.v4();
  }

  /// Update record-level last modified timestamp.
  /// Call this whenever *any* answer changes.
  static void touchLastMod(AnswerMap answers) => _touchLastMod(answers);

  static void _touchLastMod(AnswerMap answers) {
    answers['lastmod'] = DateTime.now().toIso8601String();
  }

  static int _calculateDateDiff(
      DateTime fromDate, DateTime toDate, String unit) {
    if (unit == 'd') {
      return toDate.difference(fromDate).inDays;
    }
    if (unit == 'w') {
      return toDate.difference(fromDate).inDays ~/ 7;
    }

    int years = toDate.year - fromDate.year;
    int months = toDate.month - fromDate.month;

    // Adjust for birthday/day-of-month
    if (toDate.day < fromDate.day) {
      months--;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    if (unit == 'y') return years;
    if (unit == 'm') return years * 12 + months;

    return toDate.difference(fromDate).inDays;
  }

  static DateTime _applyDateOffset(DateTime baseDate, String offsetStr) {
    if (offsetStr.isEmpty) return baseDate;

    // Normalize to date (midnight)
    final base = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final relativePattern = RegExp(r'^([+-]?\d+)([ymwd])$');
    final match = relativePattern.firstMatch(offsetStr);

    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      final unit = match.group(2)!;

      if (value != null) {
        switch (unit) {
          case 'y': // years
            return DateTime(base.year + value, base.month, base.day);
          case 'm': // months
            int newMonth = base.month + value;
            int newYear = base.year;
            while (newMonth > 12) {
              newMonth -= 12;
              newYear++;
            }
            while (newMonth < 1) {
              newMonth += 12;
              newYear--;
            }
            return DateTime(newYear, newMonth, base.day);
          case 'w': // weeks
            return base.add(Duration(days: value * 7));
          case 'd': // days
            return base.add(Duration(days: value));
        }
      }
    }
    return base;
  }

  // ---------- Default/fallbacks ----------
  static String? _defaultValueFor(Question q) {
    // 1. Check for specific field names first
    if (q.fieldName == 'synced_at') {
      return null;
    }

    // 2. Fall back to type-based defaults
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
