import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/app_strings.dart';
import 'package:datakollecta/services/survey_loader.dart';

/// Run under both flavors to cover the end-of-survey wording:
///
///     flutter test
///     flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"
void main() {
  Question q(String fieldName,
          {QuestionType type = QuestionType.text, String? text}) =>
      Question(
        type: type,
        fieldName: fieldName,
        fieldType: 'text',
        text: text ?? 'Question $fieldName',
      );

  List<String> namesOf(List<Question> questions) =>
      questions.map((q) => q.fieldName).toList();

  const systemFields = [
    'starttime',
    'startdate',
    'uniqueid',
    'swver',
    'survey_id',
    'lastmod',
    'stoptime',
  ];

  group('question type spellings', () {
    test('every spelling of automatic maps to the same type', () {
      for (final spelling in ['automatic', 'calc', 'calculation', 'calculated']) {
        expect(parseQuestionType(spelling), QuestionType.automatic,
            reason: '"$spelling" should be an automatic question');
      }
    });

    test('spellings are case-insensitive', () {
      expect(parseQuestionType('Calculated'),
          QuestionType.automatic);
    });

    test('ordinary types are unaffected', () {
      expect(parseQuestionType('radio'), QuestionType.radio);
      expect(parseQuestionType('checkbox'), QuestionType.checkbox);
      expect(parseQuestionType('date'), QuestionType.date);
    });
  });

  group('system variables', () {
    test('the loader neither adds nor moves them', () {
      // The survey generator writes all seven, in the positions that make them
      // correct, so the app takes the questionnaire exactly as it finds it.
      final declared = [
        q('starttime', type: QuestionType.automatic),
        q('startdate', type: QuestionType.automatic),
        q('age'),
        q('uniqueid', type: QuestionType.automatic),
        q('swver', type: QuestionType.automatic),
        q('survey_id', type: QuestionType.automatic),
        q('lastmod', type: QuestionType.automatic),
        q('stoptime', type: QuestionType.automatic),
      ];

      expect(namesOf(SurveyLoader.finalizeQuestions(declared)),
          namesOf(declared));
    });

    test('a questionnaire without them does not gain them', () {
      final names = namesOf(SurveyLoader.finalizeQuestions([q('age')]));

      expect(names, ['age']);
      for (final field in systemFields) {
        expect(names, isNot(contains(field)));
      }
    });
  });

  group('end-of-survey screen', () {
    test('the generated wording is translated to the build language', () {
      final result = SurveyLoader.finalizeQuestions([
        q('age'),
        q(SurveyLoader.endOfQuestionsField,
            type: QuestionType.information,
            text: "Press the 'Finish' button to save the data."),
      ]);

      final screen = result.firstWhere(
          (q) => q.fieldName == SurveyLoader.endOfQuestionsField);

      if (AppConfig.isFrench) {
        expect(screen.text, 'Appuyez sur le bouton « Terminer » pour enregistrer les données.');
      } else {
        expect(screen.text, "Press the 'Finish' button to save the data.");
      }
    });

    test('custom wording is never overwritten', () {
      const custom = 'Thank you. Please return the tablet to the supervisor.';
      final result = SurveyLoader.finalizeQuestions([
        q(SurveyLoader.endOfQuestionsField,
            type: QuestionType.information, text: custom),
      ]);

      expect(
          result
              .firstWhere(
                  (q) => q.fieldName == SurveyLoader.endOfQuestionsField)
              .text,
          custom);
    });

    test('a questionnaire without the screen does not gain one', () {
      // The screen comes from the survey generator; the app only translates it.
      final result = SurveyLoader.finalizeQuestions([q('age')]);

      expect(namesOf(result),
          isNot(contains(SurveyLoader.endOfQuestionsField)));
    });
  });

  group('numeric range message', () {
    // The generator composes this sentence from the range columns and writes
    // it in English into every questionnaire, French ones included. The app
    // recognises its own wording so it can show the right language, and leaves
    // anything an author wrote alone.

    test('the generated wording is recognised', () {
      // Every distinct message in the live Burkina Faso package.
      const generated = [
        'Number must be between 100 and 999!',
        'Number must be between 0 and 999999!',
        'Number must be between 1 and 4!',
        'Number must be between 50 and 300!',
        'Number must be between 3 and 99!',
        'Number must be between 0 and 99999999!',
      ];

      for (final message in generated) {
        expect(SurveyLoader.isGeneratedNumericRangeMessage(message), isTrue,
            reason: message);
      }
    });

    test('a decimal range is recognised', () {
      // Matched on shape, so a spreadsheet's '0.50' is caught even though the
      // parsed bound would render as '0.5'.
      expect(
          SurveyLoader.isGeneratedNumericRangeMessage(
              'Number must be between 0.50 and 12.75!'),
          isTrue);
    });

    test('a message an author wrote is left alone', () {
      for (final message in [
        'Le nombre doit être compris entre 100 et 999 !',
        'Weight looks implausible — please re-measure.',
        'Number must be between 1 and 4',   // no exclamation mark
      ]) {
        expect(SurveyLoader.isGeneratedNumericRangeMessage(message), isFalse,
            reason: message);
      }
    });

    test('a missing message is not mistaken for generated wording', () {
      expect(SurveyLoader.isGeneratedNumericRangeMessage(null), isFalse);
    });

    test('the replacement follows the build language', () {
      const s = AppStrings(AppConfig.isFrench);

      if (AppConfig.isFrench) {
        expect(s.numberMustBeBetween(100, 999),
            'Le nombre doit être compris entre 100 et 999 !');
      } else {
        // Byte-identical to what the generator writes, so the English build
        // shows exactly what it always did.
        expect(s.numberMustBeBetween(100, 999),
            'Number must be between 100 and 999!');
        expect(
            SurveyLoader.isGeneratedNumericRangeMessage(
                s.numberMustBeBetween(100, 999)),
            isTrue);
      }
    });
  });

  group('a real generated questionnaire', () {
    // Shaped exactly as GiSTXConfig_Python writes it: system variables
    // declared explicitly, and the end-of-survey screen appended last.
    const generatedXml = '''
<?xml version = '1.0' encoding = 'utf-8'?>
<survey>

	<question type = 'automatic' fieldname = 'starttime' fieldtype = 'datetime'>
	</question>

	<question type = 'automatic' fieldname = 'startdate' fieldtype = 'date'>
	</question>

	<question type = 'text' fieldname = 'age' fieldtype = 'text_integer'>
		<text>What is your age?</text>
		<maxCharacters>3</maxCharacters>
	</question>

	<question type = 'calculated' fieldname = 'age_group' fieldtype = 'integer'>
		<calculation type='constant'>
			<value>1</value>
		</calculation>
	</question>

	<question type = 'automatic' fieldname = 'uniqueid' fieldtype = 'text'>
	</question>

	<question type = 'automatic' fieldname = 'swver' fieldtype = 'text'>
	</question>

	<question type = 'automatic' fieldname = 'survey_id' fieldtype = 'text'>
	</question>

	<question type = 'automatic' fieldname = 'lastmod' fieldtype = 'datetime'>
	</question>

	<question type = 'automatic' fieldname = 'stoptime' fieldtype = 'datetime'>
	</question>

	<question type = 'information' fieldname = 'end_of_questions' fieldtype = 'n/a'>
		<text>Press the 'Finish' button to save the data.</text >
	</question>

</survey>
''';

    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('survey_loader'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<List<Question>> loadGenerated() async {
      final file = File('${tempDir.path}/demo.xml')
        ..writeAsStringSync(generatedXml);
      return SurveyLoader.loadFromFile(file);
    }

    test('nothing is duplicated and order is preserved', () async {
      final names = namesOf(await loadGenerated());

      expect(names, [
        'starttime',
        'startdate',
        'age',
        'age_group',
        'uniqueid',
        'swver',
        'survey_id',
        'lastmod',
        'stoptime',
        'end_of_questions',
      ]);
    });

    test("a 'calculated' question is loaded as automatic", () async {
      final question =
          (await loadGenerated()).firstWhere((q) => q.fieldName == 'age_group');

      expect(question.type, QuestionType.automatic);
      expect(question.calculation, isNotNull);
    });

    test('the final screen is shown in the build language', () async {
      final screen = (await loadGenerated())
          .firstWhere((q) => q.fieldName == 'end_of_questions');

      expect(
        screen.text,
        AppConfig.isFrench
            ? 'Appuyez sur le bouton « Terminer » pour enregistrer les données.'
            : "Press the 'Finish' button to save the data.",
      );
    });
  });
}
