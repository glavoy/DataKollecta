import '../models/question.dart';

/// One child form that should be repeated after its parent is saved.
class RepeatPlanItem {
  /// The child's table name, and the questionnaire to push.
  final String childTableName;

  /// What to call it in a prompt -- `crfs.displayname`, or the table name.
  final String displayName;

  /// The column that links the child to this parent.
  final String linkingField;

  /// The parent's value for that column, carried into each child.
  final String linkingValue;

  /// How many children the parent says there are.
  final int repeatCount;

  /// `crfs.auto_start_repeat`: 1 prompts the interviewer, 2 starts the loop
  /// without asking.
  final int autoStartRepeat;

  /// The whole `crfs` row, which the repeat loop passes on for the fields this
  /// plan does not model (`repeat_enforce_count`, the entity names).
  final Map<String, dynamic> crf;

  const RepeatPlanItem({
    required this.childTableName,
    required this.displayName,
    required this.linkingField,
    required this.linkingValue,
    required this.repeatCount,
    required this.autoStartRepeat,
    required this.crf,
  });
}

/// Decides which child forms to repeat, and how many times.
///
/// Pulled out of `SurveyScreen._checkAndStartAutoRepeat` so the decision can be
/// tested apart from the dialogs. Following the pattern `RepeatCountService`
/// already set: the service decides, the screen supplies the prompts and the
/// `Navigator.push` per child.
///
/// The four ways a child drops out of the plan -- no count field declared, no
/// answer for it, a count of zero or less, no linking field or value -- are
/// each a silent `continue` in the original. That is deliberate and unchanged:
/// a form with no declared count simply is not auto-repeated, and the
/// interviewer starts it by hand from the questionnaire list. It works; it just
/// works quietly, which is why the cases are worth pinning in a test.
class RepeatPlanService {
  /// Every child of [parentTableName] that should repeat, in `display_order`.
  ///
  /// Order matters: a survey with several repeating children asks for them in
  /// the sequence the dictionary declares, not the order the crfs rows happen
  /// to come back in.
  static List<RepeatPlanItem> plan({
    required List<Map<String, dynamic>> crfs,
    required String parentTableName,
    required AnswerMap answers,
  }) {
    // Sort by display_order to ensure repeats happen in correct sequence
    final sortedCrfs = List<Map<String, dynamic>>.from(crfs);
    sortedCrfs.sort((a, b) {
      final orderA = (a['display_order'] as int?) ?? 0;
      final orderB = (b['display_order'] as int?) ?? 0;
      return orderA.compareTo(orderB);
    });

    final plan = <RepeatPlanItem>[];

    for (final crf in sortedCrfs) {
      final childTableName = crf['tablename']?.toString();
      final parentTable = crf['parenttable']?.toString();
      final autoStartRepeat = _asInt(crf['auto_start_repeat']);

      // Check if this is a child of the current survey
      if (childTableName == null ||
          parentTable != parentTableName ||
          autoStartRepeat <= 0) {
        continue;
      }

      // Get the repeat count field
      final repeatCountField = crf['repeat_count_field']?.toString();
      if (repeatCountField == null || repeatCountField.isEmpty) {
        continue;
      }

      // Get the repeat count from the answers
      final repeatCountValue = answers[repeatCountField];
      if (repeatCountValue == null) {
        continue;
      }

      final repeatCount = int.tryParse(repeatCountValue.toString());
      if (repeatCount == null || repeatCount <= 0) {
        continue;
      }

      // Get the linking field to pass to child surveys
      final linkingField = crf['linkingfield']?.toString();
      if (linkingField == null) {
        continue;
      }

      final linkingValue = answers[linkingField];
      if (linkingValue == null) {
        continue;
      }

      plan.add(RepeatPlanItem(
        childTableName: childTableName,
        displayName: crf['displayname']?.toString() ?? childTableName,
        linkingField: linkingField,
        linkingValue: linkingValue.toString(),
        repeatCount: repeatCount,
        autoStartRepeat: autoStartRepeat,
        crf: crf,
      ));
    }

    return plan;
  }

  /// `auto_start_repeat` arrives as an int from SQLite and as a String from a
  /// manifest that quoted it, so both spellings are accepted.
  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
