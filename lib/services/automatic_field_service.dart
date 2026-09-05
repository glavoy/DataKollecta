import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'auto_fields.dart';
import 'id_generator.dart';
import 'survey_navigation_service.dart';

/// The outcome of computing one automatic question.
class AutomaticFieldResult {
  const AutomaticFieldResult({
    required this.fieldName,
    required this.value,
    required this.wasPreserved,
    required this.generationFailed,
  });

  final String fieldName;

  /// What now sits in the answer map for [fieldName].
  final String value;

  /// True when an existing ID was kept rather than regenerated, which happens
  /// only in edit mode and only while its component answers are unchanged.
  final bool wasPreserved;

  /// True when ID generation threw and [value] is the `-9` fallback.
  final bool generationFailed;
}

/// Computes the value of an `automatic` question when navigation reaches it.
///
/// Pulled out of `SurveyScreen._processAutomaticQuestion`, which was 117 lines
/// of which only the last six needed a widget -- a `setState` and a dialog
/// telling the interviewer their primary key already exists. Everything above
/// that is a function of the answer map, the crfs configuration and the
/// database, and is now callable without a widget tree.
///
/// **When this runs decides what a record stores**, which is why it is still
/// invoked as `SurveyNavigationService`'s injected
/// [AutomaticQuestionProcessor] rather than called directly from anywhere.
/// `starttime` records the moment navigation crossed it; move the call and the
/// record changes with no test failing. Moving the *body* is safe precisely
/// because the call site did not move.
///
/// The duplicate-key check stays in the screen. It is the one part whose whole
/// purpose is to interrupt someone.
class AutomaticFieldService {
  const AutomaticFieldService._();

  /// The value written when ID generation fails.
  ///
  /// A real value rather than null so the record still saves, and one no
  /// legitimate ID can be, so `WHERE subjid = '-9'` finds every affected row.
  static const String idGenerationFallback = '-9';

  /// Computes [question] and writes the result into [answers].
  ///
  /// Mutates the map it is given and never copies it: `SurveyScreen`'s answers
  /// are one map shared by reference with the question views, the logic
  /// service and the navigation service, and a service quietly working on its
  /// own copy would drop whatever those wrote next.
  static Future<AutomaticFieldResult> compute({
    required Question question,
    required AnswerMap answers,
    required String? surveyId,
    required String tableName,
    String? idConfig,
    String? linkingField,
    String? incrementField,
    required bool isEditMode,
  }) async {
    final isIdField = SurveyNavigationService.isGeneratedIdField(
      question,
      hasRegistryEntry:
          AutoFields.getRegistry().containsKey(question.fieldName),
      linkingField: linkingField,
      incrementField: incrementField,
    );

    if (!isIdField || idConfig == null || idConfig.isEmpty) {
      final value = await AutoFields.compute(
        answers,
        question,
        isEditMode: isEditMode,
        surveyId: surveyId,
      );
      answers[question.fieldName] = value;
      return AutomaticFieldResult(
        fieldName: question.fieldName,
        value: value,
        wasPreserved: false,
        generationFailed: false,
      );
    }

    try {
      if (surveyId != null &&
          IdGenerator.validateIdFields(
            idConfigJson: idConfig,
            answers: answers,
          )) {
        final existingId = answers[question.fieldName]?.toString();

        // Only in edit mode. A new record regenerates on every crossing, which
        // is how going back and forward past an ID question advances it -- see
        // the note on this in ToDo.md; changing it is a behaviour decision, not
        // part of moving this code.
        if (isEditMode &&
            existingId != null &&
            existingId.isNotEmpty &&
            existingId != idGenerationFallback) {
          final hasChanged = IdGenerator.hasBaseIdChanged(
            existingId: existingId,
            idConfigJson: idConfig,
            answers: answers,
          );
          if (!hasChanged) {
            return AutomaticFieldResult(
              fieldName: question.fieldName,
              value: existingId,
              wasPreserved: true,
              generationFailed: false,
            );
          }
        }

        final generatedId = await IdGenerator.generateId(
          surveyId: surveyId,
          tableName: tableName,
          fieldName: question.fieldName,
          idConfigJson: idConfig,
          answers: answers,
        );
        answers[question.fieldName] = generatedId;
        return AutomaticFieldResult(
          fieldName: question.fieldName,
          value: generatedId,
          wasPreserved: false,
          generationFailed: false,
        );
      }
    } catch (e) {
      debugPrint('Error generating ID for ${question.fieldName}: $e');
    }

    answers[question.fieldName] = idGenerationFallback;
    return AutomaticFieldResult(
      fieldName: question.fieldName,
      value: idGenerationFallback,
      wasPreserved: false,
      generationFailed: true,
    );
  }
}
