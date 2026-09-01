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

  group('Computed Automatic Variables (yyyy/yy/mm/dd/doy)', () {
    /// No `calculation` at all -- deliberately. See _formatDatePart's doc
    /// comment in auto_fields.dart for why these are plain registry fields
    /// rather than `calc:` fields: it's what gives them the same
    /// unconditional preserve-on-edit protection as starttime/startdate,
    /// without depending on a `preserve: true` flag a survey author could
    /// forget to set (and which SurveyGen has no way to emit for these
    /// anyway -- they're never declared with a calc: block at all).
    Question computedQuestion(String fieldName) => Question(
        type: QuestionType.automatic, fieldName: fieldName, fieldType: 'text');

    String expected(String part) {
      final now = DateTime.now();
      switch (part) {
        case 'yyyy':
          return now.year.toString().padLeft(4, '0');
        case 'yy':
          return (now.year % 100).toString().padLeft(2, '0');
        case 'mm':
          return now.month.toString().padLeft(2, '0');
        case 'dd':
          return now.day.toString().padLeft(2, '0');
        case 'doy':
          return (now.difference(DateTime(now.year, 1, 1)).inDays + 1)
              .toString()
              .padLeft(3, '0');
        default:
          throw ArgumentError(part);
      }
    }

    const widths = {'yyyy': 4, 'yy': 2, 'mm': 2, 'dd': 2, 'doy': 3};

    for (final part in widths.keys) {
      test('$part is today\'s value, zero-padded to ${widths[part]} digits',
          () async {
        final result = await AutoFields.compute({}, computedQuestion(part));

        expect(result, expected(part));
        expect(RegExp('^\\d{${widths[part]}}\$').hasMatch(result), isTrue,
            reason: 'expected ${widths[part]} digits, got "$result"');
      });
    }

    test(
        'editing an existing record preserves stale values unconditionally,'
        ' for every field', () async {
      // The scenario the whole design exists to prevent: editing a record on
      // a later day (or in a later year/month) must not silently mint a new
      // subject ID. Values well outside what "today" could produce prove
      // this is the stored value surviving, not a coincidental match.
      final answers = {
        'yyyy': '1999',
        'yy': '19',
        'mm': '01',
        'dd': '01',
        'doy': '045',
      };

      for (final entry in answers.entries) {
        expect(
            await AutoFields.compute(answers, computedQuestion(entry.key),
                isEditMode: true),
            entry.value);
      }
    });

    test('a stale value is preserved even outside edit mode', () async {
      // compute()'s preserve rule for a no-calculation field is unconditional
      // on isEditMode -- it fires whenever a non-empty value is already
      // present, which is also what keeps these fields stable if an
      // interviewer navigates back and forth within one in-progress
      // interview.
      final answers = {
        'yyyy': '1999',
        'yy': '19',
        'mm': '01',
        'dd': '01',
        'doy': '045',
      };

      for (final entry in answers.entries) {
        expect(await AutoFields.compute(answers, computedQuestion(entry.key)),
            entry.value);
      }
    });

    test('a brand new record with no stored value computes fresh', () async {
      for (final part in widths.keys) {
        final result = await AutoFields.compute({}, computedQuestion(part));
        expect(result, expected(part));
      }
    });
  });

  group('date_part calculation', () {
    Question datePartQuestion(String field, String unit,
            {bool preserve = false}) =>
        Question(
          type: QuestionType.automatic,
          fieldName: 'result',
          fieldType: 'text',
          calculation: CalculationConfig(
            type: 'date_part',
            field: field,
            unit: unit,
            preserve: preserve,
          ),
        );

    test('extracts each unit from a named date field', () async {
      final answers = {'dob': '1990-03-05'};

      expect(await AutoFields.compute(answers, datePartQuestion('dob', 'yyyy')),
          '1990');
      expect(
          await AutoFields.compute(answers, datePartQuestion('dob', 'yy')),
          '90');
      expect(
          await AutoFields.compute(answers, datePartQuestion('dob', 'mm')),
          '03');
      expect(
          await AutoFields.compute(answers, datePartQuestion('dob', 'dd')),
          '05');
      expect(
          await AutoFields.compute(answers, datePartQuestion('dob', 'doy')),
          '064');
    });

    test('unit is matched case-insensitively', () async {
      final answers = {'dob': '1990-03-05'};

      expect(await AutoFields.compute(answers, datePartQuestion('dob', 'MM')),
          '03');
    });

    test('field:today behaves like the equivalent Computed Automatic Variable',
        () async {
      final now = DateTime.now();
      final expectedMm = now.month.toString().padLeft(2, '0');

      final result =
          await AutoFields.compute({}, datePartQuestion('today', 'mm'));

      expect(result, expectedMm);
    });

    test('an unanswered source field produces an empty result', () async {
      final result =
          await AutoFields.compute({}, datePartQuestion('dob', 'mm'));

      expect(result, '');
    });

    test('an unparseable date value produces an empty result', () async {
      final answers = {'dob': 'not a date'};

      final result =
          await AutoFields.compute(answers, datePartQuestion('dob', 'mm'));

      expect(result, '');
    });

    test('an unrecognized unit produces an empty result', () async {
      final answers = {'dob': '1990-03-05'};

      final result =
          await AutoFields.compute(answers, datePartQuestion('dob', 'hh'));

      expect(result, '');
    });

    test(
        'without preserve, editing recomputes from a changed source field --'
        ' the contrast with the Computed Automatic Variable flavor',
        () async {
      final answers = {'dob': '1990-03-05', 'result': '01'};

      final result = await AutoFields.compute(
          answers, datePartQuestion('dob', 'mm'),
          isEditMode: true);

      expect(result, '03',
          reason: 'a date_part field with no preserve:true must track its '
              'source field even in edit mode, unlike yy/yyyy/mm/dd/doy');
    });

    test('preserve:true keeps the stored value even if the source changes',
        () async {
      final answers = {'dob': '1990-03-05', 'result': '01'};

      final result = await AutoFields.compute(
          answers, datePartQuestion('dob', 'mm', preserve: true),
          isEditMode: true);

      expect(result, '01');
    });
  });

  group('timestamp calculation', () {
    // SurveyGen always emits preserve='true' for this type (never
    // Excel-authorable), so the question fixture matches that -- there is no
    // preserve:false variant to test the way date_part has.
    final question = Question(
      type: QuestionType.automatic,
      fieldName: 'time_eligible',
      fieldType: 'datetime',
      calculation: CalculationConfig(type: 'timestamp', preserve: true),
    );

    test('stamps the current date-and-time when the row is reached',
        () async {
      final before = DateTime.now();
      final result = await AutoFields.compute({}, question);
      final after = DateTime.now();

      final parsed = DateTime.parse(result);
      expect(parsed.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(parsed.isAfter(after.add(const Duration(seconds: 1))), isFalse);
    });

    test('freezes on first capture -- an edit-mode revisit keeps it',
        () async {
      final answers = {'time_eligible': '2020-01-01T00:00:00.000'};

      final result = await AutoFields.compute(answers, question,
          isEditMode: true);

      expect(result, '2020-01-01T00:00:00.000');
    });
  });
}
