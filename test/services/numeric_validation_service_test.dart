import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/numeric_validation_service.dart';

void main() {
  group('NumericValidationService.hasTrailingDecimalSeparator', () {
    test('rejects values ending with a decimal separator', () {
      expect(
        NumericValidationService.hasTrailingDecimalSeparator('120.'),
        isTrue,
      );
      expect(
        NumericValidationService.hasTrailingDecimalSeparator('120. '),
        isTrue,
      );
    });

    test('allows whole numbers and completed decimals', () {
      expect(
        NumericValidationService.hasTrailingDecimalSeparator('120'),
        isFalse,
      );
      expect(
        NumericValidationService.hasTrailingDecimalSeparator('120.0'),
        isFalse,
      );
      expect(
        NumericValidationService.hasTrailingDecimalSeparator('120.5'),
        isFalse,
      );
    });
  });

  group('NumericValidationService.isIncompleteDecimal', () {
    bool incomplete(String fieldType, String value, {bool range = false}) =>
        NumericValidationService.isIncompleteDecimal(fieldType, value,
            hasRangeCheck: range);

    test('a decimal field is blocked mid-number', () {
      expect(incomplete('text_decimal', '12.'), isTrue);
    });

    test('a decimal field without a range check is still blocked', () {
      // The guard used to live inside the range check, so a decimal field
      // that declared no range let "12." through.
      expect(incomplete('text_decimal', '12.', range: false), isTrue);
    });

    test('a completed or whole number passes', () {
      expect(incomplete('text_decimal', '12.5'), isFalse);
      expect(incomplete('text_decimal', '12'), isFalse);
    });

    test('an empty field is not incomplete — it is unanswered', () {
      // Whether a blank answer is allowed is a separate question; flagging it
      // here would show the wrong message.
      expect(incomplete('text_decimal', ''), isFalse);
    });

    test('a range check makes any field numeric enough to block', () {
      // num.tryParse('12.') succeeds, so a range check alone would otherwise
      // let the unfinished value through.
      expect(incomplete('text', '12.', range: true), isTrue);
    });

    test('a plain text field with no range check is left alone', () {
      // A trailing full stop is ordinary punctuation in a free-text answer.
      expect(incomplete('text', 'Apac Rd.'), isFalse);
    });
  });
}
