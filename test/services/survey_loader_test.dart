import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/config/app_config.dart';
import 'package:GiSTX/models/question.dart';
import 'package:GiSTX/services/survey_loader.dart';

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
    test('missing ones are added', () {
      final result = SurveyLoader.finalizeQuestions([q('age')]);

      for (final field in systemFields) {
        expect(namesOf(result), contains(field));
      }
    });

    test('starttime and startdate come before the first real question', () {
      final names = namesOf(SurveyLoader.finalizeQuestions([q('age')]));

      expect(names.indexOf('starttime'), lessThan(names.indexOf('age')));
      expect(names.indexOf('startdate'), lessThan(names.indexOf('age')));
      expect(names.indexOf('starttime'), lessThan(names.indexOf('startdate')));
    });

    test('stoptime comes after the last real question', () {
      final names = namesOf(SurveyLoader.finalizeQuestions([q('age')]));

      expect(names.indexOf('stoptime'), greaterThan(names.indexOf('age')));
    });

    test('trailing fields stay ahead of the end-of-survey screen', () {
      // Navigation stops on that screen, so anything after it is never
      // computed and would be saved empty.
      final result = SurveyLoader.finalizeQuestions([
        q('age'),
        q(SurveyLoader.endOfQuestionsField, type: QuestionType.information),
      ]);
      final names = namesOf(result);
      final end = names.indexOf(SurveyLoader.endOfQuestionsField);

      for (final field in ['uniqueid', 'swver', 'survey_id', 'lastmod', 'stoptime']) {
        expect(names.indexOf(field), lessThan(end),
            reason: '$field must be reached before the final screen');
      }
      expect(end, names.length - 1);
    });

    test('declared ones are not duplicated', () {
      // Every survey package built so far declares these explicitly.
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

      final result = SurveyLoader.finalizeQuestions(declared);

      expect(namesOf(result), namesOf(declared),
          reason: 'an existing questionnaire must be left exactly as it was');
    });

    test('a partially declared questionnaire gets only what is missing', () {
      final result = SurveyLoader.finalizeQuestions([
        q('starttime', type: QuestionType.automatic),
        q('age'),
      ]);
      final names = namesOf(result);

      expect(names.where((n) => n == 'starttime').length, 1);
      expect(names, contains('stoptime'));
    });

    test('synthesized fields are automatic so they never render', () {
      final result = SurveyLoader.finalizeQuestions([q('age')]);

      for (final field in systemFields) {
        expect(result.firstWhere((q) => q.fieldName == field).type,
            QuestionType.automatic);
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
