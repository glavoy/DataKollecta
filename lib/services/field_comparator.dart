/// The one place that decides whether a field's answer satisfies a
/// comparison. skip_service.dart, logic_service.dart, and auto_fields.dart
/// each grew their own copy of this before this file existed, and they had
/// already drifted: one had a checkbox-handling bug the others didn't.
///
/// What this file does NOT decide: what an unanswered field means. Skip and
/// logic_check deliberately fail open (a check that can't be evaluated never
/// blocks navigation); a screening calculation may need the opposite (an
/// unanswered field should not silently grant eligibility). That policy
/// belongs to each caller, before it ever reaches [compare] -- this file
/// only answers "does this resolved text satisfy this operator".
class FieldComparator {
  /// The text a comparison reads for an answer. A checkbox answer is stored
  /// as a `List<String>`; this joins it the same way every part of this
  /// codebase already agrees a checkbox answer should be read for a
  /// comparison: comma-separated, e.g. `['1', '3']` -> `'1,3'`. Dart's
  /// default `List.toString()` would instead produce `'[1, 3]'` -- brackets
  /// and all -- which can never equal or contain a plain value like `'1'`.
  ///
  /// Anything else is `.toString()`. Returns null exactly when [value] is
  /// null, so a caller that needs to short-circuit on an unanswered field
  /// (skip, logic_check) can still do so; a caller that instead wants an
  /// unanswered field to compare as empty text should use
  /// [resolveTextOrEmpty].
  static String? resolveText(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).join(',');
    return value.toString();
  }

  /// Same as [resolveText], but an absent value resolves to `''` instead of
  /// null. This is a calculation's existing policy -- an unanswered field
  /// flows into an ordinary comparison rather than short-circuiting it --
  /// named here so every caller that wants it reuses the same rule instead
  /// of re-deriving it.
  static String resolveTextOrEmpty(dynamic value) => resolveText(value) ?? '';

  /// Evaluates `lhsText <operator> rhsText`. Both sides must already be
  /// resolved to text (see [resolveText]/[resolveTextOrEmpty]) -- this
  /// function has no opinion on nulls, Lists, or what an unanswered field
  /// means; that stays entirely with the caller.
  ///
  /// `=`/`==` and `!=`/`<>` are synonyms, normalized here so no caller needs
  /// its own normalization step. For those and for the four ordering
  /// operators, the comparison tries, in order:
  ///   1. numeric (`double.tryParse` both sides)
  ///   2. ISO-8601 date/datetime (`DateTime.tryParse` both sides)
  ///   3. plain string -- equality for `=`/`!=`; lexicographic ordering for
  ///      `<`/`>`/`<=`/`>=`
  ///
  /// `contains`/`does not contain` treat [lhsText] as a comma-separated
  /// list (trimmed) and test membership of [rhsText] -- no numeric/date
  /// coercion, an exact string match against each element.
  ///
  /// An unrecognized operator returns false.
  static bool compare(String lhsText, String operator, String rhsText) {
    final op = _normalizeOperator(operator);

    if (op == 'contains' || op == 'does not contain') {
      final list = lhsText.split(',').map((s) => s.trim()).toList();
      final contains = list.contains(rhsText);
      return op == 'contains' ? contains : !contains;
    }

    final lhsNum = double.tryParse(lhsText);
    final rhsNum = double.tryParse(rhsText);
    if (lhsNum != null && rhsNum != null) {
      return _compareOrdered(lhsNum.compareTo(rhsNum), op);
    }

    final lhsDate = DateTime.tryParse(lhsText);
    final rhsDate = DateTime.tryParse(rhsText);
    if (lhsDate != null && rhsDate != null) {
      return _compareOrdered(lhsDate.compareTo(rhsDate), op);
    }

    switch (op) {
      case '=':
        return lhsText == rhsText;
      case '!=':
        return lhsText != rhsText;
      case '<':
      case '>':
      case '<=':
      case '>=':
        return _compareOrdered(lhsText.compareTo(rhsText), op);
      default:
        return false;
    }
  }

  /// Decodes HTML-entity-encoded operators (an XML attribute value may
  /// arrive as `&lt;`/`&gt;`/`&amp;`) and folds `==`/`<>` onto their `=`/`!=`
  /// synonyms, so [compare]'s switch only ever sees one spelling of each.
  static String _normalizeOperator(String operator) {
    final decoded = operator
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
    if (decoded == '==') return '=';
    if (decoded == '<>') return '!=';
    return decoded;
  }

  /// Turns a three-way comparison result (as `int.compareTo` returns it)
  /// into the answer for one ordering operator.
  static bool _compareOrdered(int comparison, String operator) {
    switch (operator) {
      case '=':
        return comparison == 0;
      case '!=':
        return comparison != 0;
      case '<':
        return comparison < 0;
      case '>':
        return comparison > 0;
      case '<=':
        return comparison <= 0;
      case '>=':
        return comparison >= 0;
      default:
        return false;
    }
  }
}
