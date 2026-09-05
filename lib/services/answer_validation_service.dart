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
        if (NumericValidationService.isIncompleteDecimal(question.fieldType, raw,
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
}
