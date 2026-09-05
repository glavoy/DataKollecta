import '../models/question.dart';
import 'answer_equality.dart';
import 'app_strings.dart';
import 'logic_service.dart';
import 'numeric_validation_service.dart';
import 'survey_loader.dart';

/// The outcome of validating the answer now in the map.
class AnswerValidation {
  /// The message to show, or null for "no error".
  final String? message;

  /// Whether validation stopped before finishing.
  ///
  /// **This is not cosmetic, and dropping it changes behaviour.** In the
  /// original code these checks lived inside a `setState` closure and signalled
  /// "incomplete input" with a bare `return`, which exited the closure and so
  /// skipped the real-time duplicate check that followed it. A field that is
  /// half-typed, or a decimal that is mid-keystroke, therefore never reached
  /// that check. Collapsing this into "message == null" would newly run the
  /// duplicate check in three cases where it has never run.
  final bool stopsFurtherChecks;

  const AnswerValidation(this.message, {this.stopsFurtherChecks = false});
}

/// Validates the current question's answer: logic checks, then the text-only
/// length, decimal and numeric-range rules.
///
/// Pulled out of `SurveyScreen._onAnswerChanged` so it can be tested. Pure --
/// it reads the answer map and the question and returns a decision, touching
/// no state, no context and no database. The `setState`, the dialog and the
/// duplicate check stay with the screen.
class AnswerValidationService {
  /// Whether a change is only padding, and so not a real edit.
  ///
  /// `"04"` and `"4"` are the same answer. Treating them as a change would
  /// cascade-clear every dependent field each time a fixed-length field is
  /// re-padded, silently discarding answers the interviewer already gave.
  ///
  /// Kept as a name the screen reads well at its call site; the rule itself
  /// now lives in [AnswerEquality], which is the single definition the four
  /// former copies were unified onto. It is slightly wider than what this used
  /// to do -- a date re-rendered into another format is also a representation
  /// change, and cascade-clearing on one was never intended either.
  static bool isPaddingOnlyChange(dynamic oldValue, dynamic newValue) =>
      AnswerEquality.isRepresentationOnlyChange(oldValue, newValue);

  /// The error to display for [question], given the answers now in [answers].
  static AnswerValidation evaluate(
    Question question,
    AnswerMap answers,
    AppStrings s,
  ) {
    String? logicError = LogicService.evaluateLogicChecks(question, answers);

    // Perform numeric check validation
    if (question.type == QuestionType.text) {
      final raw = answers[question.fieldName]?.toString() ?? '';

      // Strict length check (if configured with <maxCharacters>=N)
      if (question.fixedLength && question.maxCharacters != null) {
        if (raw.length != question.maxCharacters) {
          // Incomplete input: keep Next disabled, but HIDE error message
          return const AnswerValidation(null, stopsFurtherChecks: true);
        }
      }

      // Special responses (don't know / refuse) bypass the numeric range check
      final isSpecialResponse = raw.isNotEmpty &&
          ((question.dontKnow != null && raw == question.dontKnow) ||
              (question.refuse != null && raw == question.refuse));

      if (logicError == null && raw.isNotEmpty && !isSpecialResponse) {
        // "12." is a number the interviewer has not finished typing. Flag it
        // on any decimal field, not just one that also declares a range.
        if (NumericValidationService.isIncompleteDecimal(
            question.fieldType, raw,
            hasRangeCheck: question.numericCheck != null)) {
          return AnswerValidation(s.incompleteDecimalValue,
              stopsFurtherChecks: true);
        }

        final parsed = num.tryParse(raw);
        if (question.numericCheck != null && parsed != null) {
          final nc = question.numericCheck!;
          if (!NumericValidationService.isWithinRange(nc, parsed)) {
            // The generator writes this sentence in English whatever the
            // build, so the app supplies the wording. A message the author
            // wrote is already in the dictionary's language: use it as-is.
            final ownWording =
                s.numberMustBeBetween(nc.minValue ?? '', nc.maxValue ?? '');
            logicError = SurveyLoader.isGeneratedNumericRangeMessage(nc.message)
                ? ownWording
                : (nc.message ?? ownWording);
          }
        }
      }
    }

    return AnswerValidation(logicError);
  }

  /// Whether [question] counts as answered, for the Next button.
  ///
  /// Moved verbatim out of `SurveyScreen._isAnswered` so the survey-testing
  /// harness gates on the same rule the app gates on rather than a copy of it.
  /// The screen still owns the button; this owns the decision.
  static bool isAnswered(Question question, AnswerMap answers) {
    // A question the dictionary marked <optional> may be left blank -- the
    // Next button stays enabled with no answer. Replaces the old hardcoded
    // 'comments' fieldname special-case, which applied regardless of what
    // the XML actually declared and gave every survey exactly one skippable
    // field, always named 'comments'.
    if (question.optional) {
      return true;
    }

    final val = answers[question.fieldName];

    switch (question.type) {
      case QuestionType.text:
        return (val is String) && val.trim().isNotEmpty;
      case QuestionType.radio:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.checkbox:
        return (val is List) && val.isNotEmpty;
      case QuestionType.combobox:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.date:
        // For date questions, must have a date selected or special response
        if (val == null) return false;
        final valStr = val.toString();
        if (valStr.isEmpty) return false;
        // Special responses (don't know, refuse) are valid
        if (question.dontKnow != null && valStr == question.dontKnow) {
          return true;
        }
        if (question.refuse != null && valStr == question.refuse) return true;
        // Otherwise, must be a valid DateTime
        return val is DateTime ||
            (val is String && DateTime.tryParse(valStr) != null);
      case QuestionType.datetime:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.information:
      case QuestionType.automatic:
        return true; // not applicable
    }
  }

  /// Whether [question]'s answer passes its length, decimal and range rules.
  ///
  /// Moved verbatim out of `SurveyScreen._isValid`. Deliberately silent: this
  /// is the half of the gate that disables the button without saying why --
  /// [evaluate] is what produces the message. Only `QuestionType.text` has
  /// anything to check.
  static bool isValid(Question question, AnswerMap answers) {
    if (question.type == QuestionType.text) {
      final raw = answers[question.fieldName]?.toString() ?? '';

      // Special responses (don't know / refuse) bypass format/length/numeric checks
      if (raw.isNotEmpty &&
          ((question.dontKnow != null && raw == question.dontKnow) ||
              (question.refuse != null && raw == question.refuse))) {
        return true;
      }

      // Strict length check
      if (question.fixedLength && question.maxCharacters != null) {
        if (raw.length != question.maxCharacters) return false;
      }

      // A half-typed decimal blocks Next whether or not a range is declared.
      if (NumericValidationService.isIncompleteDecimal(question.fieldType, raw,
          hasRangeCheck: question.numericCheck != null)) {
        return false;
      }

      if (question.numericCheck != null) {
        if (raw.isEmpty) return false;

        final parsed = num.tryParse(raw);
        if (parsed == null) return false;

        if (!NumericValidationService.isWithinRange(
            question.numericCheck!, parsed)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Whether navigation may leave [question] -- the whole Next-button gate.
  ///
  /// Composes the three halves the way `SurveyScreen.build` does: an
  /// `information` screen always passes, anything else must be answered and
  /// valid, and no logic check may be failing. An interviewer facing `false`
  /// here cannot move on and cannot finish; there is no way past it but to
  /// change the answer.
  ///
  /// The screen holds its failing message in `_logicError` across rebuilds,
  /// so it re-reads state rather than recomputing; this recomputes, which is
  /// the same decision from the same inputs.
  static bool canProceed(Question question, AnswerMap answers, AppStrings s) {
    if (question.type == QuestionType.information) return true;
    if (!isAnswered(question, answers)) return false;
    if (!isValid(question, answers)) return false;
    return evaluate(question, answers, s).message == null;
  }
}
