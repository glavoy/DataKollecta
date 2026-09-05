import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'answer_equality.dart';

/// The pure steps between "the interviewer pressed Finish" and "write the row".
///
/// Pulled out of `SurveyScreen._showDone`, which is 180 lines of which only
/// these are decidable without a `BuildContext`. The orchestration stays there:
/// claiming the save guard, the four dialogs, the `mounted` checks and the two
/// `Navigator` calls all depend on the widget tree and cannot be tested by this
/// suite.
///
/// Every method takes the answer map as an argument and, where it mutates,
/// mutates that same map. **None of them may take a copy.** `SurveyScreen`'s
/// `_answers` is one map handed by reference to the question views, the logic
/// service, `AutoFields`, `IdGenerator` and the navigation service; a service
/// that quietly worked on its own copy would drop whatever those wrote next.
class AnswerStorageService {
  /// Fields that change on every save and so never count as an edit.
  static const Set<String> _fieldsThatAlwaysChange = {
    'lastmod',
    'swver',
    'survey_id',
  };

  /// Whether [answers] differs from [original] in any way that counts.
  ///
  /// Null [original] means a new record, which always has changes.
  ///
  /// Tolerant in two directions on purpose, because both would otherwise show
  /// up as edits the interviewer never made: `"04"` equals `"4"` (a
  /// fixed-length field re-padded), and two spellings of the same instant are
  /// equal (`"2025-12-09 11:22"` against `"2025-12-09T11:22"`, which is what a
  /// round trip through SQLite produces).
  static bool hasChanges(AnswerMap answers, AnswerMap? original) {
    if (original == null) return true; // New record, always has changes

    // Compare each answer
    for (final key in answers.keys) {
      // Ignore automatic fields that auto-update
      if (_fieldsThatAlwaysChange.contains(key)) continue;

      // The three-branch comparison that used to sit here was the most
      // complete of the four in the codebase -- it alone treated two spellings
      // of the same instant as equal -- so it became the shared rule rather
      // than being replaced by one. See [AnswerEquality]; the verdicts are the
      // same, including that a reordered checkbox still counts as a change.
      if (!AnswerEquality.sameAnswer(answers[key], original[key])) {
        return true;
      }
    }

    // Check for removed answers
    for (final key in original.keys) {
      if (!answers.containsKey(key)) return true;
    }

    return false;
  }

  /// Nulls any answered field that skip logic bypassed, in place.
  ///
  /// Keeps the record consistent with the path actually taken: if `sex` changes
  /// from female to male, the pregnancy answers given before that change must
  /// not survive into the row.
  ///
  /// [visitedFields] is owned by the screen -- it is written during `build`, as
  /// each question is displayed -- and is passed in rather than rebuilt here,
  /// because "was this shown to the interviewer" is a fact about navigation
  /// that only the screen holds.
  ///
  /// Primary keys are exempt. They are frequently never displayed (a composite
  /// key of `automatic` fields is computed, not asked) and clearing one would
  /// destroy the record's identity.
  static void clearSkippedAnswers({
    required AnswerMap answers,
    required List<Question> questions,
    required Set<String> visitedFields,
    required List<String>? primaryKeyFields,
  }) {
    // Get all question field names that should collect data (not automatic/information)
    final dataQuestions = questions
        .where((q) =>
            q.type != QuestionType.automatic &&
            q.type != QuestionType.information)
        .map((q) => q.fieldName)
        .toSet();

    // Also preserve primary key fields (they're skipped but shouldn't be cleared)
    final primaryKeys =
        primaryKeyFields?.map((f) => f.toLowerCase()).toSet() ?? {};

    // Find fields that have answers but were not visited (skipped)
    final skippedFields = <String>[];
    for (final fieldName in answers.keys) {
      // Check if this is a data question
      if (!dataQuestions.contains(fieldName)) continue;

      // Check if it's a primary key (don't clear these)
      if (primaryKeys.contains(fieldName.toLowerCase())) continue;

      // Check if it was visited
      if (!visitedFields.contains(fieldName)) {
        skippedFields.add(fieldName);
      }
    }

    // Clear the skipped fields
    if (skippedFields.isNotEmpty) {
      debugPrint(
          'Clearing ${skippedFields.length} skipped fields: ${skippedFields.join(", ")}');
      for (final field in skippedFields) {
        answers[field] = null;
      }
    }
  }

  /// A copy of [answers] with date and datetime values in their stored form.
  ///
  /// A date column holds `YYYY-MM-DD` and a datetime column a full ISO string.
  /// In the answer map either may be a `DateTime`, or a string in whatever
  /// shape the picker or a previous read left it, so both are normalised here
  /// rather than at every place that writes one.
  ///
  /// Returns a new map: this is the one place a copy is correct, because the
  /// coerced values are what goes to the database while `answers` stays as the
  /// screen and its question views know it. A value that cannot be parsed is
  /// left exactly as it is -- refusing to guess is what keeps an unparseable
  /// answer visible rather than silently blanked.
  static AnswerMap coerceForStorage(
    AnswerMap answers,
    List<Question>? questions,
  ) {
    // Values are saved as-is (padding preserved)
    final answersToSave = Map<String, dynamic>.from(answers);

    if (questions == null) return answersToSave;

    for (final q in questions) {
      final val = answersToSave[q.fieldName];
      if (val == null) continue;

      if (q.type == QuestionType.date) {
        final dt = DateTime.tryParse(val.toString());
        if (dt != null) {
          answersToSave[q.fieldName] = dt.toIso8601String().split('T')[0];
        }
      } else if (q.type == QuestionType.datetime) {
        final dt = DateTime.tryParse(val.toString());
        if (dt != null) {
          answersToSave[q.fieldName] = dt.toIso8601String();
        }
      }
    }

    return answersToSave;
  }
}
