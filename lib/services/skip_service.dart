// lib/services/skip_service.dart
import '../models/question.dart';
import 'field_comparator.dart';

/// Service for evaluating skip conditions
class SkipService {
  /// Evaluate a skip condition and return the target field name if skip should occur
  /// Returns null if the skip condition is not met
  static String? evaluateSkip(
    SkipCondition skip,
    AnswerMap answers,
  ) {
    // A skip whose tested field is unanswered fails open: it never fires,
    // so the question it guards is asked of everyone.
    final actualValueStr = FieldComparator.resolveText(answers[skip.fieldName]);
    if (actualValueStr == null) return null;

    // Get the comparison value
    final String compareValue;
    if (skip.responseType == 'dynamic') {
      // Dynamic: get value from another field
      compareValue = FieldComparator.resolveTextOrEmpty(answers[skip.response]);
    } else {
      // Fixed: use the literal value
      compareValue = skip.response;
    }

    final conditionMet =
        FieldComparator.compare(actualValueStr, skip.condition, compareValue);

    // If condition is met, return the skip target
    return conditionMet ? skip.skipToFieldName : null;
  }

  /// Evaluate all skip conditions for a question and return the first matching skip target
  /// Returns null if no skip conditions are met
  static String? evaluateSkips(
    List<SkipCondition> skips,
    AnswerMap answers,
  ) {
    for (final skip in skips) {
      final target = evaluateSkip(skip, answers);
      if (target != null) return target;
    }
    return null;
  }
}
