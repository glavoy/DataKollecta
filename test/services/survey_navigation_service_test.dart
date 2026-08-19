import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/survey_navigation_service.dart';

void main() {
  group('SurveyNavigationService.clearAnswersInRange', () {
    test('clears route data while preserving protected fields and keys', () {
      final questions = <Question>[
        for (final field in SurveyNavigationService.protectedAutomaticFields)
          _question(
            field,
            QuestionType.automatic,
            calculation: CalculationConfig(type: 'constant', value: 'new'),
          ),
        _question(
          'STARTTIME',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'new'),
        ),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: '1'),
        ),
        _question('custom_system_field', QuestionType.automatic),
        _question('information', QuestionType.information),
        _question('record_key', QuestionType.text),
        _question('manual_answer', QuestionType.text),
      ];
      final answers = <String, dynamic>{
        for (final field in SurveyNavigationService.protectedAutomaticFields)
          field: 'preserved',
        'STARTTIME': 'preserved',
        'derived': 'old calculation',
        'custom_system_field': 'preserved',
        'information': 'preserved',
        'record_key': 'preserved',
        'manual_answer': 'old answer',
      };

      SurveyNavigationService.clearAnswersInRange(
        questions: questions,
        answers: answers,
        startIndex: 0,
        endIndex: questions.length,
        primaryKeyFields: const ['RECORD_KEY'],
      );

      for (final field in SurveyNavigationService.protectedAutomaticFields) {
        expect(answers[field], 'preserved', reason: field);
      }
      expect(answers['STARTTIME'], 'preserved');
      expect(answers['derived'], isNull);
      expect(answers.containsKey('derived'), isTrue);
      expect(answers['custom_system_field'], 'preserved');
      expect(answers['information'], 'preserved');
      expect(answers['record_key'], 'preserved');
      expect(answers['manual_answer'], isNull);
    });
  });

  group('SurveyNavigationService navigation order', () {
    test('postskip clears dependencies before calculating its target',
        () async {
      final questions = <Question>[
        _question(
          'route',
          QuestionType.radio,
          postSkips: [_skip('route', '=', '1', 'derived')],
        ),
        _question('stale_dependency', QuestionType.text),
        _question('starttime', QuestionType.automatic),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
        _question('next', QuestionType.text),
      ];
      final answers = <String, dynamic>{
        'route': '1',
        'stale_dependency': 'old',
        'starttime': 'preserved',
        'derived': 'old result',
      };

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          if (question.fieldName == 'derived') {
            answers['derived'] =
                answers['stale_dependency'] == null ? 'clean' : 'stale';
          }
        },
      );

      expect(nextIndex, 4);
      expect(answers['stale_dependency'], isNull);
      expect(answers['starttime'], 'preserved');
      expect(answers['derived'], 'clean');
    });

    test('preskip clears dependencies before calculating a later target',
        () async {
      final questions = <Question>[
        _question('route', QuestionType.radio),
        _question(
          'skipped_question',
          QuestionType.text,
          preSkips: [_skip('route', '=', '1', 'derived')],
        ),
        _question('stale_dependency', QuestionType.text),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
        _question('next', QuestionType.text),
      ];
      final answers = <String, dynamic>{
        'route': '1',
        'skipped_question': 'old',
        'stale_dependency': 'old',
        'derived': 'old result',
      };

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          answers['derived'] =
              answers['stale_dependency'] == null ? 'clean' : 'stale';
        },
      );

      expect(nextIndex, 4);
      expect(answers['skipped_question'], isNull);
      expect(answers['stale_dependency'], isNull);
      expect(answers['derived'], 'clean');
    });

    test('ordinary automatic questions retain their fresh calculation',
        () async {
      final questions = <Question>[
        _question('current', QuestionType.text),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'fresh'),
        ),
        _question('next', QuestionType.text),
      ];
      final answers = <String, dynamic>{'derived': 'old'};

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          answers[question.fieldName] = 'fresh';
        },
      );

      expect(nextIndex, 2);
      expect(answers['derived'], 'fresh');
    });

    test('postskip clearing preserves primary keys in an existing record',
        () async {
      final questions = <Question>[
        _question(
          'route',
          QuestionType.radio,
          postSkips: [_skip('route', '=', '1', 'next')],
        ),
        _question('record_key', QuestionType.text),
        _question('next', QuestionType.text),
      ];
      final answers = <String, dynamic>{
        'route': '1',
        'record_key': 'existing-key',
      };

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (_) async {},
        primaryKeyFields: const ['RECORD_KEY'],
        isEditMode: true,
      );

      expect(nextIndex, 2);
      expect(answers['record_key'], 'existing-key');
    });

    test('invalid and non-forward skip targets fall back without looping',
        () async {
      final invalidTargetQuestions = <Question>[
        _question(
          'current',
          QuestionType.radio,
          postSkips: [_skip('route', '=', '1', 'missing')],
        ),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'fresh'),
        ),
        _question('next', QuestionType.text),
      ];
      final invalidAnswers = <String, dynamic>{'route': '1'};

      final invalidTargetIndex =
          await SurveyNavigationService.advanceFromQuestion(
        questions: invalidTargetQuestions,
        currentIndex: 0,
        answers: invalidAnswers,
        processAutomaticQuestion: (question) async {
          invalidAnswers[question.fieldName] = 'fresh';
        },
      );

      expect(invalidTargetIndex, 2);
      expect(invalidAnswers['derived'], 'fresh');

      final backwardTargetQuestions = <Question>[
        _question('current', QuestionType.radio),
        _question(
          'derived',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'fresh'),
          preSkips: [_skip('route', '=', '1', 'current')],
        ),
        _question('next', QuestionType.text),
      ];
      final backwardAnswers = <String, dynamic>{'route': '1'};

      final backwardTargetIndex =
          await SurveyNavigationService.advanceFromQuestion(
        questions: backwardTargetQuestions,
        currentIndex: 0,
        answers: backwardAnswers,
        processAutomaticQuestion: (question) async {
          backwardAnswers[question.fieldName] = 'fresh';
        },
      );

      expect(backwardTargetIndex, 2);
      expect(backwardAnswers['derived'], 'fresh');
    });

    test('automatic preskips select only the Uganda calculation branch',
        () async {
      final questions = _countryBranchQuestions();
      final answers = <String, dynamic>{
        'country': '1',
        'age_at_apr2025': 'old',
        'age_in_range_ug': 'old',
        'age_at_sep2023': 'old',
        'age_in_range_bf': 'old',
      };
      final processed = <String>[];

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          processed.add(question.fieldName);
          answers[question.fieldName] = 'calculated';
        },
      );

      expect(nextIndex, 5);
      expect(processed, ['age_at_apr2025', 'age_in_range_ug']);
      expect(answers['age_at_apr2025'], 'calculated');
      expect(answers['age_in_range_ug'], 'calculated');
      expect(answers['age_at_sep2023'], isNull);
      expect(answers['age_in_range_bf'], isNull);
    });

    test('automatic preskips select only the Burkina Faso branch', () async {
      final questions = _countryBranchQuestions();
      final answers = <String, dynamic>{
        'country': '2',
        'age_at_apr2025': 'old',
        'age_in_range_ug': 'old',
        'age_at_sep2023': 'old',
        'age_in_range_bf': 'old',
      };
      final processed = <String>[];

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          processed.add(question.fieldName);
          answers[question.fieldName] = 'calculated';
        },
      );

      expect(nextIndex, 5);
      expect(processed, ['age_at_sep2023', 'age_in_range_bf']);
      expect(answers['age_at_apr2025'], isNull);
      expect(answers['age_in_range_ug'], isNull);
      expect(answers['age_at_sep2023'], 'calculated');
      expect(answers['age_in_range_bf'], 'calculated');
    });

    test('clears every jump in a chained preskip route', () async {
      final questions = <Question>[
        _question('route', QuestionType.radio),
        _question(
          'b',
          QuestionType.text,
          preSkips: [_skip('route', '=', '1', 'd')],
        ),
        _question('c', QuestionType.text),
        _question(
          'd',
          QuestionType.text,
          preSkips: [_skip('route', '=', '1', 'h')],
        ),
        _question('e', QuestionType.text),
        _question('f', QuestionType.text),
        _question('g', QuestionType.text),
        _question(
          'h',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
        _question('next', QuestionType.text),
      ];
      final answers = <String, dynamic>{
        'route': '1',
        for (final field in ['b', 'c', 'd', 'e', 'f', 'g']) field: 'old',
      };

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          final cleaned = ['b', 'c', 'd', 'e', 'f', 'g']
              .every((field) => answers[field] == null);
          answers[question.fieldName] = cleaned ? 'clean' : 'stale';
        },
      );

      expect(nextIndex, 8);
      for (final field in ['b', 'c', 'd', 'e', 'f', 'g']) {
        expect(answers[field], isNull, reason: field);
      }
      expect(answers['h'], 'clean');
    });
  });
}

Question _question(
  String fieldName,
  QuestionType type, {
  CalculationConfig? calculation,
  List<SkipCondition> preSkips = const [],
  List<SkipCondition> postSkips = const [],
}) {
  return Question(
    type: type,
    fieldName: fieldName,
    fieldType: 'text',
    calculation: calculation,
    preSkips: preSkips,
    postSkips: postSkips,
  );
}

SkipCondition _skip(
  String fieldName,
  String condition,
  String response,
  String target,
) {
  return SkipCondition(
    fieldName: fieldName,
    condition: condition,
    response: response,
    responseType: 'fixed',
    skipToFieldName: target,
  );
}

List<Question> _countryBranchQuestions() {
  final calculation = CalculationConfig(type: 'constant', value: 'unused');
  return [
    _question('dob', QuestionType.date),
    _question(
      'age_at_apr2025',
      QuestionType.automatic,
      calculation: calculation,
      preSkips: [_skip('country', '<>', '1', 'age_at_sep2023')],
    ),
    _question(
      'age_in_range_ug',
      QuestionType.automatic,
      calculation: calculation,
    ),
    _question(
      'age_at_sep2023',
      QuestionType.automatic,
      calculation: calculation,
      preSkips: [_skip('country', '<>', '2', 'age')],
    ),
    _question(
      'age_in_range_bf',
      QuestionType.automatic,
      calculation: calculation,
    ),
    _question('age', QuestionType.text),
  ];
}
