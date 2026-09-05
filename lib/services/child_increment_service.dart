import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'db_service.dart';

/// Decides the sibling ordinal a new child record should carry.
///
/// A child form declares an `incrementfield` in the `crfs` worksheet --
/// `linenum` for a household member, `netnum` for a net -- and this is the
/// number that goes in it: one more than the highest already issued under the
/// same parent.
///
/// Pulled out of `SurveyScreen._calculateLineNum` so it can be tested. It was
/// the most extractable method in that file: no `setState`, no `BuildContext`,
/// no `mounted`, and one caller. Following the pattern `SurveyNavigationService`
/// and `RepeatCountService` already set here -- the service decides, the screen
/// keeps the state and the UI.
///
/// **New records only.** The caller gates this on `existingAnswers == null`,
/// and that gate deliberately stays at the call site rather than moving in
/// here, because it is about which screen the interviewer came through rather
/// than about counting. Editing a record must never renumber it: reopening a
/// child and having its `linenum` recomputed was a real bug, fixed in
/// "Stop an edit from regenerating the record's own primary keys".
class ChildIncrementService {
  /// Computes the increment for a new child and writes it into [answers].
  ///
  /// Writes nothing when this form declares no increment field, or declares
  /// one the survey does not contain. Writes
  /// [DbService.degradedIncrementValue] -- rather than 1 -- whenever the real
  /// number cannot be established, so a degraded row is findable afterwards
  /// instead of being indistinguishable from a legitimate first child.
  static Future<void> assign({
    required List<Question> questions,
    required AnswerMap answers,
    required String surveyId,
    required String tableName,
    required String? incrementField,
    required String? fallbackLinkingField,
  }) async {
    try {
      // Check if an increment field is configured
      if (incrementField == null || incrementField.isEmpty) {
        return; // No increment field configured
      }

      final incrementFieldName = incrementField;

      // Check if this survey has the configured increment field
      final hasIncrementField =
          questions.any((q) => q.fieldName == incrementFieldName);
      if (!hasIncrementField) {
        return; // Configured increment field doesn't exist in this survey
      }

      // Children are grouped by the CRF's `linkingfield` -- the column that
      // defines parentage and the one the foreign key is declared on. This
      // used to read `crfs.primarykey`'s first field, which agreed with
      // `linkingfield` only by luck: nothing constrains a dictionary to list
      // the linking field first, and `primarykey = 'linenum,hhid'` would have
      // grouped every child in the survey by linenum.
      //
      // The throwing read, not the tolerant one. `getCrfConfig` returns null
      // both when the form has no crfs row and when the database cannot be
      // read at all, and this method reports *which* fallback it took -- so
      // with the tolerant read, a total database failure logged "No
      // linkingfield configured", sending an incident after a dictionary
      // problem that did not exist. A genuine read failure now falls to the
      // catch below, which says so. The value written is 0 either way.
      final crfConfig =
          await DbService.getCrfConfigOrThrow(surveyId, tableName);
      final linkingField =
          crfConfig?['linkingfield']?.toString() ?? fallbackLinkingField;

      if (linkingField == null || linkingField.isEmpty) {
        // A form with an incrementfield but no linkingfield is a mis-authored
        // dictionary: there is no column to group siblings by, so any number
        // here is a guess. Issue the degraded value rather than 1, which is
        // indistinguishable from a legitimate first child.
        debugPrint('No linkingfield configured for $tableName -- issuing '
            '$incrementFieldName=${DbService.degradedIncrementValue}');
        answers[incrementFieldName] =
            DbService.degradedIncrementValue.toString();
        return;
      }

      final linkingValue = answers[linkingField];

      if (linkingValue == null || linkingValue.toString().isEmpty) {
        // Same reasoning: without the parent's key there is no sibling set to
        // count, so 1 would be a guess dressed as a fact.
        debugPrint('Linking field $linkingField not set -- issuing '
            '$incrementFieldName=${DbService.degradedIncrementValue}');
        answers[incrementFieldName] =
            DbService.degradedIncrementValue.toString();
        return;
      }

      // Query the database for the next increment value
      final nextValue = await DbService.getNextIncrementValue(
        surveyId: surveyId,
        tableName: tableName,
        incrementField: incrementFieldName,
        linkingField: linkingField,
        linkingValue: linkingValue.toString(),
      );

      answers[incrementFieldName] = nextValue.toString();
      debugPrint(
          'Calculated $incrementFieldName=$nextValue for $linkingField=$linkingValue');
    } catch (e) {
      if (incrementField != null && incrementField.isNotEmpty) {
        debugPrint('Error calculating $incrementField -- issuing '
            '${DbService.degradedIncrementValue}: $e');
        answers[incrementField] = DbService.degradedIncrementValue.toString();
      }
    }
  }
}
