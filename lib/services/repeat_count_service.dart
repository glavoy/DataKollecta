import '../models/question.dart';
import 'db_service.dart';
import 'numeric_validation_service.dart';
import 'question_cache_service.dart';

/// What reconciling a parent's repeat count against its children should do.
enum RepeatCountOutcome {
  /// The declared count already matches the number of child records.
  inSync,

  /// `repeat_enforce_count = 0` -- any number of children is acceptable.
  noEnforcement,

  /// The parent's count field is NULL because its question was skipped.
  /// Writing a count here would contradict the skip logic, so nothing is done.
  countNotDeclared,

  /// Fewer children than the count question's `LowerRange` allows. Never
  /// written -- the interviewer could not have typed this number either.
  belowMinimum,

  /// More children than the count question's `UpperRange` allows. Never
  /// written; the data needs correcting instead.
  aboveMaximum,

  /// `repeat_enforce_count = 2` -- the repeat loop blocks until the counts
  /// agree, so there is nothing to reconcile afterwards.
  forceModeHandledInLoop,

  /// `repeat_enforce_count = 1` -- offer to update the count.
  askToUpdate,

  /// `repeat_enforce_count = 3` -- update the count without asking, then
  /// tell the interviewer it happened. There is no choice to offer (the
  /// write is unconditional), just an acknowledgement so the count on
  /// screen doesn't change with no explanation.
  updateSilently,
}

/// The result of comparing a parent's declared repeat count with the number of
/// child records actually stored.
class RepeatCountReconciliation {
  final RepeatCountOutcome outcome;
  final String parentTable;
  final String childTable;
  final String linkingField;
  final String linkingValue;
  final String countField;
  final String displayName;
  final int actualCount;

  /// The count the interviewer declared, or null when that question was
  /// skipped.
  final int? declaredCount;

  /// The count question's own range check, when it declares one.
  final NumericCheck? check;

  const RepeatCountReconciliation({
    required this.outcome,
    required this.parentTable,
    required this.childTable,
    required this.linkingField,
    required this.linkingValue,
    required this.countField,
    required this.displayName,
    required this.actualCount,
    required this.declaredCount,
    required this.check,
  });

  num? get minimum => check?.minValue;
  num? get maximum => check?.maxValue;

  /// True when the count may legitimately be written -- either unconditionally
  /// (mode 3, with the interviewer informed after the fact) or after the
  /// interviewer agrees (mode 1).
  bool get canWrite =>
      outcome == RepeatCountOutcome.updateSilently ||
      outcome == RepeatCountOutcome.askToUpdate;
}

/// Keeps a parent form's repeat count (`nmembers`, `nstructures`, ...) in step
/// with the number of child records actually entered.
///
/// The count is reconciled from one place so that it behaves the same however
/// the children got there -- through the auto-repeat loop that follows the
/// parent's save, or through a record added later from the questionnaire menu.
///
/// Every write is gated on the count question's own `LowerRange`/`UpperRange`
/// via [NumericValidationService.isWithinRange]. The interviewer cannot type a
/// number the form rejects, and neither can the app: a household that declared
/// six members can never be silently reduced to zero because someone backed out
/// of the first child form.
class RepeatCountService {
  /// Reads `repeat_enforce_count` tolerantly. SQLite declares the column
  /// INTEGER, but the value has also arrived as a string from hand-built
  /// manifests, and a failed cast here would abort the whole repeat loop.
  /// Blank means warn, matching the data dictionary's documented default.
  static int parseEnforceMode(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 1;
    return 1;
  }

  /// The range check declared by the parent's count question, if any.
  static Future<NumericCheck?> countCheckFor({
    required String surveyId,
    required String countField,
  }) async {
    final cache = QuestionCacheService();
    await cache.ensureLoadedForSurvey(surveyId);
    return cache.getQuestion(countField)?.numericCheck;
  }

  /// Compares the declared count with the child records on disk and reports
  /// what should happen. Performs no writes and shows no UI, so the caller
  /// decides how (and whether) to involve the interviewer.
  ///
  /// Returns null when [childTableName] is not a counted repeating form.
  static Future<RepeatCountReconciliation?> evaluate({
    required String surveyId,
    required String childTableName,
    required String linkingValue,
  }) async {
    final crf = await DbService.getCrfConfig(surveyId, childTableName);
    if (crf == null) return null;

    final countField = crf['repeat_count_field']?.toString();
    final parentTable = crf['parenttable']?.toString();
    final linkingField = crf['linkingfield']?.toString();
    if (countField == null ||
        countField.isEmpty ||
        parentTable == null ||
        parentTable.isEmpty ||
        linkingField == null ||
        linkingField.isEmpty) {
      return null;
    }

    final displayName = crf['displayname']?.toString() ?? childTableName;
    final mode = parseEnforceMode(crf['repeat_enforce_count']);

    final actualCount = await DbService.getRecordCount(
      surveyId: surveyId,
      tableName: childTableName,
      where: '$linkingField = ?',
      whereArgs: [linkingValue],
    );

    final declaredRaw = await DbService.getFieldValue(
      surveyId: surveyId,
      tableName: parentTable,
      field: countField,
      where: '$linkingField = ?',
      whereArgs: [linkingValue],
    );
    final declaredText = declaredRaw?.toString().trim();
    final declaredCount =
        (declaredText == null || declaredText.isEmpty) ? null : int.tryParse(declaredText);

    final check = await countCheckFor(surveyId: surveyId, countField: countField);

    RepeatCountReconciliation result(RepeatCountOutcome outcome) {
      return RepeatCountReconciliation(
        outcome: outcome,
        parentTable: parentTable,
        childTable: childTableName,
        linkingField: linkingField,
        linkingValue: linkingValue,
        countField: countField,
        displayName: displayName,
        actualCount: actualCount,
        declaredCount: declaredCount,
        check: check,
      );
    }

    // A skipped count question stores NULL. Filling it in would undo the skip
    // logic that emptied it -- a household with no nets keeps nnets NULL even
    // once a nets record is added by hand.
    if (declaredText == null || declaredText.isEmpty) {
      return result(RepeatCountOutcome.countNotDeclared);
    }

    if (declaredCount == actualCount) {
      return result(RepeatCountOutcome.inSync);
    }

    // The gate that makes an impossible count unwritable. `other_values`
    // exceptions are honoured here exactly as they are for a typed answer.
    if (check != null &&
        !NumericValidationService.isWithinRange(check, actualCount)) {
      final minimum = check.minValue;
      if (minimum != null && actualCount < minimum) {
        return result(RepeatCountOutcome.belowMinimum);
      }
      return result(RepeatCountOutcome.aboveMaximum);
    }

    switch (mode) {
      case 0:
        return result(RepeatCountOutcome.noEnforcement);
      case 2:
        return result(RepeatCountOutcome.forceModeHandledInLoop);
      case 3:
        return result(RepeatCountOutcome.updateSilently);
      default:
        return result(RepeatCountOutcome.askToUpdate);
    }
  }

  /// Writes the reconciled count onto the parent record.
  ///
  /// Goes through [DbService.updateField], so the corrected count clears
  /// `synced_at` and leaves a `formchanges` trail like any other edit.
  static Future<void> applyCount({
    required String surveyId,
    required RepeatCountReconciliation reconciliation,
  }) async {
    await DbService.updateField(
      surveyId: surveyId,
      tableName: reconciliation.parentTable,
      field: reconciliation.countField,
      value: reconciliation.actualCount,
      where: '${reconciliation.linkingField} = ?',
      whereArgs: [reconciliation.linkingValue],
    );
  }
}
