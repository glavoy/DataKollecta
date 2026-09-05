import 'field_comparator.dart';

/// The one place that decides whether two answers are the same answer.
///
/// Four implementations of this existed -- `isPaddingOnlyChange` in
/// `AnswerValidationService`, `_isLogicallyEqual` in `ChangeSummaryService`,
/// `_isSameStoredValue` in `DbService` and the comparison inside
/// `AnswerStorageService.hasChanges` -- and they did not agree. Only the last
/// treated `2025-12-09 11:22` and `2025-12-09T11:22` as the same moment, and
/// only two canonicalised a checkbox `List` the way the rest of the codebase
/// reads one. So on a save where something else had also changed, the change
/// summary could show the interviewer a date change that `formchanges` never
/// recorded.
///
/// This is the same failure `field_comparator.dart` was written to end for
/// skip/logic/calculation, one layer up: three services each grew their own
/// copy and drifted.
///
/// **The rule is the union of what the four already intended**, so it is the
/// most tolerant of the set: a change has to survive every test below before
/// it counts as a change.
class AnswerEquality {
  /// The text an answer is compared and stored as.
  ///
  /// A checkbox answer is a `List`, and joins comma-separated -- delegated to
  /// [FieldComparator.resolveText], which is already the codebase's agreed
  /// reading of one (`['1','3']` -> `'1,3'`, not Dart's `'[1, 3]'`). A
  /// `DateTime` becomes ISO-8601, which is the form it is stored in, so a
  /// value loaded back from SQLite compares equal to the one in memory.
  ///
  /// Null in, null out: an unanswered field is not the empty string, and the
  /// callers that care about that distinction handle it themselves.
  static String? canonical(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    return FieldComparator.resolveText(value);
  }

  /// Whether [a] and [b] are the same answer, however each is written.
  ///
  /// Equal canonical text, **or** both parse as numbers and are numerically
  /// equal (`'04'` and `'4'`), **or** both parse as dates and name the same
  /// moment (`'2025-12-09 11:22'` and `'2025-12-09T11:22'`).
  ///
  /// **`num.tryParse`, never `double.tryParse`.** A 17-digit barcode
  /// round-trips exactly through `num` and loses precision through `double`,
  /// which would make two different IDs compare equal. This is why
  /// [FieldComparator.compare] is not reused here despite looking like it
  /// would serve -- it parses with `double`.
  static bool sameAnswer(dynamic a, dynamic b) {
    final left = canonical(a);
    final right = canonical(b);

    if (left == right) return true;
    if (left == null || right == null) return false;

    final leftNum = num.tryParse(left);
    final rightNum = num.tryParse(right);
    if (leftNum != null && rightNum != null) return leftNum == rightNum;

    final leftDate = DateTime.tryParse(left);
    final rightDate = DateTime.tryParse(right);
    if (leftDate != null && rightDate != null) {
      return leftDate.isAtSameMomentAs(rightDate);
    }

    return false;
  }

  /// Whether [oldValue] and [newValue] are written differently but mean the
  /// same thing -- `'04'` becoming `'4'`, or a date being re-rendered.
  ///
  /// Not an equality predicate: an exact match is `false`, because the caller
  /// has already handled that case and this one exists to answer "should the
  /// cascade-clear run". Re-padding a fixed-length field must not discard
  /// every dependent answer the interviewer has already given.
  static bool isRepresentationOnlyChange(dynamic oldValue, dynamic newValue) {
    if (oldValue == null || newValue == null) return false;
    if (canonical(oldValue) == canonical(newValue)) return false;
    return sameAnswer(oldValue, newValue);
  }
}
