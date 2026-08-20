import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/models/question.dart';
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

  group('NumericValidationService.isWithinRange', () {
    const nmembers =
        NumericCheck(minValue: 1, maxValue: 30, otherValues: '1');

    test('accepts values inside the declared range', () {
      expect(NumericValidationService.isWithinRange(nmembers, 1), isTrue);
      expect(NumericValidationService.isWithinRange(nmembers, 6), isTrue);
      expect(NumericValidationService.isWithinRange(nmembers, 30), isTrue);
    });

    test('rejects values below LowerRange', () {
      expect(NumericValidationService.isWithinRange(nmembers, 0), isFalse);
      expect(NumericValidationService.isWithinRange(nmembers, -1), isFalse);
    });

    test('rejects values above UpperRange', () {
      expect(NumericValidationService.isWithinRange(nmembers, 31), isFalse);
    });

    test('accepts an out-of-range value listed in other_values', () {
      const withDontKnow =
          NumericCheck(minValue: 1, maxValue: 30, otherValues: '99, 88');
      expect(NumericValidationService.isWithinRange(withDontKnow, 99), isTrue);
      expect(NumericValidationService.isWithinRange(withDontKnow, 88), isTrue);
      expect(NumericValidationService.isWithinRange(withDontKnow, 31), isFalse);
    });

    test('a half-declared range only constrains the end it declares', () {
      expect(
        NumericValidationService.isWithinRange(
            const NumericCheck(minValue: 1), 900),
        isTrue,
      );
      expect(
        NumericValidationService.isWithinRange(
            const NumericCheck(maxValue: 30), 0),
        isTrue,
      );
    });
  });
}
