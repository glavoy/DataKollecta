import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'skip_service.dart';

typedef AutomaticQuestionProcessor = Future<void> Function(Question question);

/// Resolves forward survey navigation while keeping skipped answers consistent.
class SurveyNavigationService {
  static const Set<String> protectedAutomaticFields = {
    'starttime',
    'startdate',
    'uniqueid',
    'swver',
    'survey_id',
    'lastmod',
    'stoptime',
  };

  /// The web designer's "End of Form" skip target. Not a real fieldname --
  /// `_findQuestionByFieldName` would never match it, which is exactly the
  /// bug this constant exists to fix: a skip targeting this literal string
  /// used to silently do nothing (index -1 always fails `> currentIndex`).
  static const String endOfFormSkipTarget = 'end';

  static bool _isEndOfForm(String target) =>
      target.trim().toLowerCase() == endOfFormSkipTarget;

  /// Advances from a displayed question, applying its postskip before traversing
  /// automatic questions and preskips.
  static Future<int> advanceFromQuestion({
    required List<Question> questions,
    required int currentIndex,
    required AnswerMap answers,
    required AutomaticQuestionProcessor processAutomaticQuestion,
    Iterable<String> primaryKeyFields = const [],
    bool isEditMode = false,
  }) async {
    var startIndex = currentIndex + 1;
    final postSkipTarget =
        SkipService.evaluateSkips(questions[currentIndex].postSkips, answers);

    if (postSkipTarget != null) {
      if (_isEndOfForm(postSkipTarget)) {
        return _advanceToEnd(
          questions: questions,
          answers: answers,
          startIndex: currentIndex + 1,
          processAutomaticQuestion: processAutomaticQuestion,
          primaryKeyFields: primaryKeyFields,
          isEditMode: isEditMode,
        );
      }

      final targetIndex = _findQuestionByFieldName(questions, postSkipTarget);
      if (targetIndex > currentIndex) {
        clearAnswersInRange(
          questions: questions,
          answers: answers,
          startIndex: currentIndex + 1,
          endIndex: targetIndex,
          primaryKeyFields: primaryKeyFields,
        );
        startIndex = targetIndex;
      }
    }

    return findNextDisplayedQuestion(
      questions: questions,
      startIndex: startIndex,
      answers: answers,
      processAutomaticQuestion: processAutomaticQuestion,
      primaryKeyFields: primaryKeyFields,
      isEditMode: isEditMode,
    );
  }

  /// Finds the next displayed question. Preskips are evaluated before any
  /// automatic or hidden-primary-key processing.
  static Future<int> findNextDisplayedQuestion({
    required List<Question> questions,
    required int startIndex,
    required AnswerMap answers,
    required AutomaticQuestionProcessor processAutomaticQuestion,
    Iterable<String> primaryKeyFields = const [],
    bool isEditMode = false,
  }) async {
    var index = startIndex;
    final primaryKeys =
        primaryKeyFields.map((field) => field.toLowerCase()).toSet();

    while (index < questions.length) {
      final question = questions[index];
      final preSkipTarget =
          SkipService.evaluateSkips(question.preSkips, answers);

      if (preSkipTarget != null) {
        if (_isEndOfForm(preSkipTarget)) {
          return _advanceToEnd(
            questions: questions,
            answers: answers,
            startIndex: index,
            processAutomaticQuestion: processAutomaticQuestion,
            primaryKeyFields: primaryKeys,
            isEditMode: isEditMode,
          );
        }

        final targetIndex = _findQuestionByFieldName(questions, preSkipTarget);
        if (targetIndex > index) {
          clearAnswersInRange(
            questions: questions,
            answers: answers,
            startIndex: index,
            endIndex: targetIndex,
            primaryKeyFields: primaryKeys,
          );
          index = targetIndex;
          continue;
        }
      }

      final isHiddenPrimaryKey =
          isEditMode && primaryKeys.contains(question.fieldName.toLowerCase());
      if (question.type == QuestionType.automatic || isHiddenPrimaryKey) {
        await processAutomaticQuestion(question);
        index++;
        continue;
      }

      return index;
    }

    return questions.isEmpty ? 0 : questions.length - 1;
  }

  /// Walks every remaining question to the very end of the survey.
  ///
  /// Unlike an ordinary skip -- which jumps straight to a target index and
  /// clears the whole range in one shot -- "end of form" cannot use that
  /// shortcut: the range being skipped over always contains the trailing
  /// system fields (uniqueid, swver, survey_id, lastmod, stoptime), which
  /// must be *computed*, not cleared -- every record needs them regardless
  /// of how the interview ended. So this walks question by question instead.
  ///
  /// A *custom* `calc:` field in that range is nulled, not computed --
  /// matching `clearAnswersInRange`'s rule for an ordinary skip (see its own
  /// doc comment). Computing it here would mean evaluating a calculation
  /// whose declared inputs the interview may never have reached, silently
  /// producing a value from missing data (e.g. a `math` calculation treats
  /// an unanswered operand as 0, not blank -- see `_answerText` in
  /// auto_fields.dart). A survey author who wants a calculation to always
  /// have a value must place it before any skip that could bypass it; this
  /// service does not try to guess which calculations are "safe" to run
  /// with incomplete inputs.
  ///
  /// Every other question has just its own answer cleared (via the same
  /// protections `clearAnswersInRange` already applies -- primary keys,
  /// protected system fields, and information screens are left alone)
  /// without ever being displayed.
  static Future<int> _advanceToEnd({
    required List<Question> questions,
    required AnswerMap answers,
    required int startIndex,
    required AutomaticQuestionProcessor processAutomaticQuestion,
    Iterable<String> primaryKeyFields = const [],
    bool isEditMode = false,
  }) async {
    final primaryKeys =
        primaryKeyFields.map((field) => field.toLowerCase()).toSet();
    var index = startIndex < 0 ? 0 : startIndex;

    while (index < questions.length) {
      final question = questions[index];
      final isHiddenPrimaryKey =
          isEditMode && primaryKeys.contains(question.fieldName.toLowerCase());

      if (isHiddenPrimaryKey) {
        await processAutomaticQuestion(question);
      } else if (question.type == QuestionType.automatic) {
        final isCustomCalculation = question.calculation != null &&
            !protectedAutomaticFields.contains(question.fieldName.toLowerCase());
        if (isCustomCalculation) {
          answers[question.fieldName] = null;
        } else {
          await processAutomaticQuestion(question);
        }
      } else {
        clearAnswersInRange(
          questions: questions,
          answers: answers,
          startIndex: index,
          endIndex: index + 1,
          primaryKeyFields: primaryKeys,
        );
      }
      index++;
    }

    return questions.isEmpty ? 0 : questions.length - 1;
  }

  /// Clears [startIndex] (inclusive) through [endIndex] (exclusive).
  ///
  /// Calculated automatic fields are route-derived and must be invalidated.
  /// Protected system fields and primary keys are never cleared by navigation.
  static void clearAnswersInRange({
    required List<Question> questions,
    required AnswerMap answers,
    required int startIndex,
    required int endIndex,
    Iterable<String> primaryKeyFields = const [],
  }) {
    final primaryKeys =
        primaryKeyFields.map((field) => field.toLowerCase()).toSet();
    final clearedFields = <String>[];
    final boundedStart = startIndex < 0 ? 0 : startIndex;

    for (var index = boundedStart;
        index < endIndex && index < questions.length;
        index++) {
      final question = questions[index];
      final fieldName = question.fieldName;
      final normalizedFieldName = fieldName.toLowerCase();

      if (primaryKeys.contains(normalizedFieldName) ||
          protectedAutomaticFields.contains(normalizedFieldName) ||
          question.type == QuestionType.information) {
        continue;
      }

      if (question.type == QuestionType.automatic &&
          question.calculation == null) {
        continue;
      }

      if (answers[fieldName] != null) {
        clearedFields.add(fieldName);
      }
      answers[fieldName] = null;
    }

    if (clearedFields.isNotEmpty) {
      debugPrint(
        'Cleared ${clearedFields.length} skipped answers: '
        '${clearedFields.join(", ")}',
      );
    }
  }

  static int _findQuestionByFieldName(
    List<Question> questions,
    String fieldName,
  ) {
    return questions.indexWhere((question) => question.fieldName == fieldName);
  }
}
