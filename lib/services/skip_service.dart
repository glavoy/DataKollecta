// lib/services/skip_service.dart
import '../models/question.dart';
import 'field_comparator.dart';

/// Told about each skip rule as it is evaluated, and whether it fired.
///
/// Exists for the survey-testing harness, which needs to distinguish a rule
/// that was tried and did not fire from one that was never reached at all --
/// a green run whose branches were never taken proves nothing about them. The
/// alternative was for the harness to evaluate rules itself, which would be a
/// second comparator alongside the one documented here to fail open on an
/// unanswered field.
typedef SkipObserver = void Function(SkipCondition skip, bool fired);

/// Service for evaluating skip conditions
class SkipService {
  /// Evaluate a skip condition and return the target field name if skip should occur
  /// Returns null if the skip condition is not met
  static String? evaluateSkip(
    SkipCondition skip,
    AnswerMap answers, {
    SkipObserver? onEvaluated,
  }) {
    // A skip whose tested field is unanswered fails open: it never fires,
    // so the question it guards is asked of everyone.
    final actualValueStr = FieldComparator.resolveText(answers[skip.fieldName]);
    if (actualValueStr == null) {
      onEvaluated?.call(skip, false);
      return null;
    }

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
    onEvaluated?.call(skip, conditionMet);

    // If condition is met, return the skip target
    return conditionMet ? skip.skipToFieldName : null;
  }

  /// Evaluate all skip conditions for a question and return the first matching skip target
  /// Returns null if no skip conditions are met
  ///
  /// First match wins, and the rules after it are **not** evaluated -- so an
  /// [onEvaluated] observer hears nothing about them. That silence is the
  /// signal a shadowed rule produces, and it is deliberate.
  static String? evaluateSkips(
    List<SkipCondition> skips,
    AnswerMap answers, {
    SkipObserver? onEvaluated,
  }) {
    for (final skip in skips) {
      final target = evaluateSkip(skip, answers, onEvaluated: onEvaluated);
      if (target != null) return target;
    }
    return null;
  }
}
