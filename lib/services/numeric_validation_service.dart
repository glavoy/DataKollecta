class NumericValidationService {
  /// Returns true when a decimal separator is the final non-space character.
  ///
  /// This catches incomplete decimal entries such as "120." while allowing
  /// whole numbers ("120") and completed decimals ("120.0", "120.5").
  static bool hasTrailingDecimalSeparator(String value) {
    return value.trimRight().endsWith('.');
  }

  /// Returns true when a numeric answer has been started but not finished —
  /// "12." rather than "12" or "12.5".
  ///
  /// The input formatter has to allow a trailing point, otherwise the point
  /// could never be typed at all, so the half-typed value is caught here
  /// instead: it shows a message and keeps Next disabled until the number is
  /// completed or the point deleted.
  ///
  /// A field counts as numeric if its type says so (`text_decimal`) or if it
  /// declares a range check — `num.tryParse('12.')` succeeds, so a range check
  /// alone would let the unfinished value through.
  static bool isIncompleteDecimal(
    String fieldType,
    String value, {
    bool hasRangeCheck = false,
  }) {
    if (value.isEmpty) return false;
    if (!hasRangeCheck && !fieldType.toLowerCase().contains('decimal')) {
      return false;
    }
    return hasTrailingDecimalSeparator(value);
  }
}
