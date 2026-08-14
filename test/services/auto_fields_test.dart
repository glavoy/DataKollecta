import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/models/question.dart';
import 'package:GiSTX/services/auto_fields.dart';

/// A checkbox answer is stored as a List<String>, not a String -- radio,
/// text and date answers are plain Strings. A calculation reading a field's
/// value has to treat that consistently, or a `when:` condition against a
/// checkbox field silently never matches the way its literal suggests.
void main() {
  Question caseQuestion(List<CaseConfig> cases, {CalculationConfig? orElse}) =>
      Question(
        type: QuestionType.automatic,
        fieldName: 'result',
        fieldType: 'integer',
        calculation: CalculationConfig(
          type: 'case',
          cases: cases,
          defaultValue:
              orElse ?? CalculationConfig(type: 'constant', value: '1'),
        ),
      );

  CaseConfig excludeIfNot99(String field) => CaseConfig(
        field: field,
        operator: '!=',
        value: '99',
        result: CalculationConfig(type: 'constant', value: '0'),
      );

  group('case calculation against a checkbox field', () {
    test('a single checkbox selection matches a literal exactly', () async {
      // Before the fix, answers['screen_cab_drug2'] being a List meant
      // val.toString() produced '[99]', which never equals the literal '99'.
      final AnswerMap answers = {'screen_cab_drug2': ['99']};
      final result = await AutoFields.compute(
          answers, caseQuestion([excludeIfNot99('screen_cab_drug2')]));

      expect(result, '1', reason: '99 alone means "not on any listed drug", '
          'so != 99 must be false and the else branch must run');
    });

    test('a real selection (99 not among them) still excludes', () async {
      final AnswerMap answers = {'screen_cab_drug2': ['1', '3']};
      final result = await AutoFields.compute(
          answers, caseQuestion([excludeIfNot99('screen_cab_drug2')]));

      expect(result, '0');
    });

    test('a plain radio answer is unaffected by the fix', () async {
      final AnswerMap answers = {'neg_hiv_cab2': '1'};
      final result = await AutoFields.compute(
          answers,
          caseQuestion([
            CaseConfig(
              field: 'neg_hiv_cab2',
              operator: '=',
              value: '1',
              result: CalculationConfig(type: 'constant', value: '0'),
            ),
          ]));

      expect(result, '0');
    });

    test('an unanswered checkbox field is treated as empty, not "[]"',
        () async {
      final result = await AutoFields.compute(
          {}, caseQuestion([excludeIfNot99('screen_cab_drug2')]));

      // '' != '99' is true, so this still excludes -- an unanswered
      // screening question must not silently grant eligibility.
      expect(result, '0');
    });
  });

  group('lookup calculation against a checkbox field', () {
    test('copies the joined value, not the bracketed one', () async {
      final AnswerMap answers = {'symptoms': ['1', '3']};
      final q = Question(
        type: QuestionType.automatic,
        fieldName: 'symptoms_copy',
        fieldType: 'text',
        calculation: CalculationConfig(type: 'lookup', field: 'symptoms'),
      );

      expect(await AutoFields.compute(answers, q), '1,3');
    });
  });
}
