import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/auto_fields.dart';

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

  group('contains / does not contain in a case calculation', () {
    // The capability the checkbox-List fix made possible: real membership
    // testing, rather than the mutual-exclusion `!= 99` trick above, which
    // only works when the excluded value can never co-occur with another.
    test('contains finds a value regardless of what else was selected',
        () async {
      final q = caseQuestion([
        CaseConfig(
          field: 'screen_cab_drug2',
          operator: 'contains',
          value: '99',
          result: CalculationConfig(type: 'constant', value: '0'),
        ),
      ]);

      expect(
          await AutoFields.compute(
              {'screen_cab_drug2': ['1', '99']}, q),
          '0');
      expect(
          await AutoFields.compute({'screen_cab_drug2': ['1', '3']}, q),
          '1');
    });

    test('does not contain negates membership', () async {
      final q = caseQuestion([
        CaseConfig(
          field: 'screen_cab_drug2',
          operator: 'does not contain',
          value: '99',
          result: CalculationConfig(type: 'constant', value: '1'),
        ),
      ], orElse: CalculationConfig(type: 'constant', value: '0'));

      expect(
          await AutoFields.compute({'screen_cab_drug2': ['1', '3']}, q),
          '1');
      expect(
          await AutoFields.compute(
              {'screen_cab_drug2': ['1', '99']}, q),
          '0');
    });
  });

  group('yy / ddd reserved auto fields', () {
    /// No `calculation` at all -- deliberately. See _computeTwoDigitYear's
    /// doc comment in auto_fields.dart for why these are plain registry
    /// fields rather than `calc:` fields: it's what gives them the same
    /// unconditional preserve-on-edit protection as starttime/startdate,
    /// without depending on a `preserve: true` flag a survey author could
    /// forget to set (and which SurveyGen has no way to emit today anyway).
    Question yyQuestion() =>
        Question(type: QuestionType.automatic, fieldName: 'yy', fieldType: 'text');
    Question dddQuestion() =>
        Question(type: QuestionType.automatic, fieldName: 'ddd', fieldType: 'text');

    String expectedTwoDigitYear() =>
        (DateTime.now().year % 100).toString().padLeft(2, '0');

    String expectedDayOfYear() {
      final now = DateTime.now();
      return (now.difference(DateTime(now.year, 1, 1)).inDays + 1)
          .toString()
          .padLeft(3, '0');
    }

    test('yy is the current two-digit year', () async {
      final result = await AutoFields.compute({}, yyQuestion());

      expect(result, expectedTwoDigitYear());
      expect(RegExp(r'^\d{2}$').hasMatch(result), isTrue);
    });

    test('ddd is today\'s ordinal day, zero-padded to three digits', () async {
      final result = await AutoFields.compute({}, dddQuestion());

      expect(result, expectedDayOfYear());
      expect(int.parse(result), inInclusiveRange(1, 366));
      expect(RegExp(r'^\d{3}$').hasMatch(result), isTrue,
          reason: 'expected a 3-digit zero-padded number, got "$result"');
    });

    test('editing an existing record preserves a stale yy/ddd unconditionally',
        () async {
      // The scenario the whole design exists to prevent: editing a record
      // on a later day (or in a later year, for yy) must not silently mint
      // a new subject ID. Values well outside what "today" could produce
      // prove this is the stored value surviving, not a coincidental match.
      final answers = {'yy': '19', 'ddd': '045'};

      expect(await AutoFields.compute(answers, yyQuestion(), isEditMode: true),
          '19');
      expect(
          await AutoFields.compute(answers, dddQuestion(), isEditMode: true),
          '045');
    });

    test('a stale value is preserved even outside edit mode', () async {
      // compute()'s preserve rule for a no-calculation field is unconditional
      // on isEditMode -- it fires whenever a non-empty value is already
      // present, which is also what keeps yy/ddd stable if an interviewer
      // navigates back and forth within one still-in-progress interview.
      final answers = {'yy': '19', 'ddd': '045'};

      expect(await AutoFields.compute(answers, yyQuestion()), '19');
      expect(await AutoFields.compute(answers, dddQuestion()), '045');
    });

    test('a brand new record with no stored value computes fresh', () async {
      final result = await AutoFields.compute({}, dddQuestion());

      expect(result, expectedDayOfYear());
    });
  });
}
