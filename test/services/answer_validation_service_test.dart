import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/answer_validation_service.dart';
import 'package:datakollecta/services/app_strings.dart';

/// The per-keystroke validation `SurveyScreen` runs on the current answer.
///
/// The case this suite exists for is `stopsFurtherChecks`. In the original
/// code these rules lived inside a `setState` closure and signalled
/// "incomplete input" with a bare `return` -- which exited the closure and so
/// skipped the real-time duplicate check that came after it. Extracting the
/// rules into a function that returns only a message would have quietly started
/// running that check on half-typed keys. These tests pin the distinction so it
/// cannot be lost again.
const AppStrings s = AppStrings(AppConfig.isFrench);

Question textQuestion({
  String fieldName = 'hhnum',
  String fieldType = 'text_integer',
  bool fixedLength = false,
  int? maxCharacters,
  NumericCheck? numericCheck,
  String? dontKnow,
  String? refuse,
  List<LogicCheck> logicChecks = const [],
}) =>
    Question(
      fieldName: fieldName,
      type: QuestionType.text,
      fieldType: fieldType,
      text: fieldName,
      fixedLength: fixedLength,
      maxCharacters: maxCharacters,
      numericCheck: numericCheck,
      dontKnow: dontKnow,
      refuse: refuse,
      logicChecks: logicChecks,
    );

void main() {
  group('isPaddingOnlyChange', () {
    test('"04" and "4" are the same answer', () {
      expect(AnswerValidationService.isPaddingOnlyChange('04', '4'), isTrue);
      expect(AnswerValidationService.isPaddingOnlyChange('4', '04'), isTrue);
    });

    test('an identical string is not reported as a padding change', () {
      // The caller handles the exact match before asking; reporting it here
      // would be harmless but misleading.
      expect(AnswerValidationService.isPaddingOnlyChange('4', '4'), isFalse);
    });

    test('genuinely different numbers are a real change', () {
      expect(AnswerValidationService.isPaddingOnlyChange('4', '5'), isFalse);
      expect(AnswerValidationService.isPaddingOnlyChange('4', '40'), isFalse);
    });

    test('non-numeric text is always a real change', () {
      expect(AnswerValidationService.isPaddingOnlyChange('abc', 'ABC'), isFalse);
      expect(AnswerValidationService.isPaddingOnlyChange('', ' '), isFalse);
    });

    test('a null on either side is a real change', () {
      // Clearing an answer, or answering for the first time, must cascade.
      expect(AnswerValidationService.isPaddingOnlyChange(null, '4'), isFalse);
      expect(AnswerValidationService.isPaddingOnlyChange('4', null), isFalse);
    });

    test('handles a numeric type as well as its string form', () {
      expect(AnswerValidationService.isPaddingOnlyChange(4, '04'), isTrue);
    });
  });

  group('stopsFurtherChecks -- the flag that guards the duplicate check', () {
    test('a fixed-length field that is not yet full stops, with no message',
        () {
      final q = textQuestion(fixedLength: true, maxCharacters: 7);

      final result =
          AnswerValidationService.evaluate(q, {'hhnum': '101'}, s);

      // No message: an interviewer mid-way through typing has not made a
      // mistake, so nothing is shown. Next stays disabled by other means.
      expect(result.message, isNull);
      expect(result.stopsFurtherChecks, isTrue);
    });

    test('a fixed-length field that is full does not stop', () {
      final q = textQuestion(fixedLength: true, maxCharacters: 7);

      final result =
          AnswerValidationService.evaluate(q, {'hhnum': '1010001'}, s);

      expect(result.message, isNull);
      expect(result.stopsFurtherChecks, isFalse);
    });

    test('a field longer than its fixed length also stops', () {
      final q = textQuestion(fixedLength: true, maxCharacters: 7);

      final result =
          AnswerValidationService.evaluate(q, {'hhnum': '10100019'}, s);

      expect(result.stopsFurtherChecks, isTrue);
    });

    test('an unfinished decimal stops, and does show a message', () {
      final q = textQuestion(fieldType: 'text_decimal');

      final result = AnswerValidationService.evaluate(q, {'hhnum': '12.'}, s);

      expect(result.message, s.incompleteDecimalValue);
      expect(result.stopsFurtherChecks, isTrue);
    });

    test('a finished decimal does not stop', () {
      final q = textQuestion(fieldType: 'text_decimal');

      final result = AnswerValidationService.evaluate(q, {'hhnum': '12.5'}, s);

      expect(result.message, isNull);
      expect(result.stopsFurtherChecks, isFalse);
    });

    test('an out-of-range value reports but does NOT stop', () {
      // The difference that matters: a range failure is a finished answer that
      // happens to be wrong, so the duplicate check still runs after it. Only
      // an *unfinished* answer short-circuits.
      final q = textQuestion(
        numericCheck: NumericCheck(minValue: 1, maxValue: 30),
      );

      final result = AnswerValidationService.evaluate(q, {'hhnum': '99'}, s);

      expect(result.message, isNotNull);
      expect(result.stopsFurtherChecks, isFalse);
    });

    test('a non-text question never stops', () {
      final q = Question(
        fieldName: 'sex',
        type: QuestionType.radio,
        fieldType: 'integer',
        text: 'Sex',
      );

      final result = AnswerValidationService.evaluate(q, {'sex': '1'}, s);

      expect(result.stopsFurtherChecks, isFalse);
    });
  });

  group('the numeric range check', () {
    final q = textQuestion(
      numericCheck: NumericCheck(minValue: 1, maxValue: 30),
    );

    test('accepts a value inside the range', () {
      expect(
          AnswerValidationService.evaluate(q, {'hhnum': '15'}, s).message, isNull);
      expect(
          AnswerValidationService.evaluate(q, {'hhnum': '1'}, s).message, isNull);
      expect(AnswerValidationService.evaluate(q, {'hhnum': '30'}, s).message,
          isNull);
    });

    test('rejects a value outside it, in the build language', () {
      final result = AnswerValidationService.evaluate(q, {'hhnum': '0'}, s);

      expect(result.message, s.numberMustBeBetween('1', '30'));
    });

    test('uses the dictionary author\'s own message when there is one', () {
      // A message the author wrote is already in the dictionary's language, so
      // it is shown as-is rather than replaced by the app's wording.
      final authored = textQuestion(
        numericCheck: NumericCheck(
          minValue: 1,
          maxValue: 30,
          message: 'Combien de personnes vivent ici?',
        ),
      );

      final result =
          AnswerValidationService.evaluate(authored, {'hhnum': '99'}, s);

      expect(result.message, 'Combien de personnes vivent ici?');
    });

    test('an empty answer is not range-checked', () {
      expect(AnswerValidationService.evaluate(q, {'hhnum': ''}, s).message,
          isNull);
      expect(AnswerValidationService.evaluate(q, {}, s).message, isNull);
    });

    test('a special response bypasses the range check', () {
      // "don't know" is stored as -7, which is outside every sensible range.
      final special = textQuestion(
        numericCheck: NumericCheck(minValue: 1, maxValue: 30),
        dontKnow: '-7',
        refuse: '-8',
      );

      expect(
          AnswerValidationService.evaluate(special, {'hhnum': '-7'}, s).message,
          isNull);
      expect(
          AnswerValidationService.evaluate(special, {'hhnum': '-8'}, s).message,
          isNull);
      // A value that is neither special nor in range still fails.
      expect(
          AnswerValidationService.evaluate(special, {'hhnum': '99'}, s).message,
          isNotNull);
    });

    test('non-numeric text is not range-checked', () {
      expect(AnswerValidationService.evaluate(q, {'hhnum': 'abc'}, s).message,
          isNull);
    });
  });
}
