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

    test(
        'postskip "end" computes the trailing system fields but nulls a '
        'custom calculation', () async {
      // Mirrors the shape a web-designer survey actually produces: a
      // postskip to "end" fires partway through a run of automatic fields,
      // including the trailing system ones. The reserved fields (uniqueid,
      // swver, survey_id, lastmod, stoptime) must always be computed --
      // every record needs them regardless of how the interview ended. A
      // custom calc: field like risk_level must NOT be computed: its
      // declared inputs may sit further down the questionnaire, past the
      // point the interview actually reached, and evaluating it anyway
      // would silently fabricate a value from missing data.
      final questions = <Question>[
        _question(
          'severity',
          QuestionType.radio,
          postSkips: [_skip('severity', '=', '0', 'end')],
        ),
        _question(
          'risk_level',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
        _question('uniqueid', QuestionType.automatic),
        _question('swver', QuestionType.automatic),
        _question('survey_id', QuestionType.automatic),
        _question('lastmod', QuestionType.automatic),
        _question('stoptime', QuestionType.automatic),
        _question('end_of_questions', QuestionType.information),
      ];
      final answers = <String, dynamic>{
        'severity': '0',
        'risk_level': 'stale',
      };
      final processed = <String>[];

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          processed.add(question.fieldName);
          answers[question.fieldName] = 'computed';
        },
      );

      expect(nextIndex, questions.length - 1);
      expect(processed, [
        'uniqueid',
        'swver',
        'survey_id',
        'lastmod',
        'stoptime',
      ]);
      for (final field in processed) {
        expect(answers[field], 'computed', reason: field);
      }
      expect(answers['risk_level'], isNull);
    });

    test('postskip "end" clears real questions in between without showing them',
        () async {
      final questions = <Question>[
        _question(
          'severity',
          QuestionType.radio,
          postSkips: [_skip('severity', '=', '0', 'end')],
        ),
        _question('followup_detail', QuestionType.text),
        _question('followup_notes', QuestionType.text),
        _question(
          'risk_level',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
      ];
      final answers = <String, dynamic>{
        'severity': '0',
        'followup_detail': 'stale',
        'followup_notes': 'stale',
      };

      final nextIndex = await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          answers[question.fieldName] = 'computed';
        },
      );

      expect(nextIndex, questions.length - 1);
      expect(answers['followup_detail'], isNull);
      expect(answers['followup_notes'], isNull);
      // A custom calc: field is nulled like any other skipped question, not
      // computed -- see the dedicated test above.
      expect(answers['risk_level'], isNull);
    });

    test(
        'postskip "end" still computes a registry-only automatic field with '
        'no calculation', () async {
      // yyyy/yy/mm/dd/doy (and similar) always mean "today" -- they read no
      // other answer, so there is no missing-input risk the way a custom
      // calc: field has. clearAnswersInRange already leaves these alone
      // rather than clearing them; _advanceToEnd computes them, same as it
      // always has.
      final questions = <Question>[
        _question(
          'severity',
          QuestionType.radio,
          postSkips: [_skip('severity', '=', '0', 'end')],
        ),
        _question('doy', QuestionType.automatic),
      ];
      final answers = <String, dynamic>{'severity': '0'};
      final processed = <String>[];

      await SurveyNavigationService.advanceFromQuestion(
        questions: questions,
        currentIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          processed.add(question.fieldName);
          answers[question.fieldName] = 'computed';
        },
      );

      expect(processed, ['doy']);
      expect(answers['doy'], 'computed');
    });

    test('preskip "end" is matched case-insensitively and with whitespace',
        () async {
      final questions = <Question>[
        _question(
          'gate',
          QuestionType.radio,
          preSkips: [_skip('route', '=', '1', ' End ')],
        ),
        _question('later', QuestionType.text),
        _question(
          'stoptime',
          QuestionType.automatic,
          calculation: CalculationConfig(type: 'constant', value: 'unused'),
        ),
      ];
      final answers = <String, dynamic>{'route': '1', 'later': 'stale'};

      final nextIndex = await SurveyNavigationService.findNextDisplayedQuestion(
        questions: questions,
        startIndex: 0,
        answers: answers,
        processAutomaticQuestion: (question) async {
          answers[question.fieldName] = 'computed';
        },
      );

      expect(nextIndex, questions.length - 1);
      expect(answers['later'], isNull);
      expect(answers['stoptime'], 'computed');
    });

    test('postskip "end" preserves primary keys in an existing record',
        () async {
      final questions = <Question>[
        _question(
          'route',
          QuestionType.radio,
          postSkips: [_skip('route', '=', '1', 'end')],
        ),
        _question('record_key', QuestionType.text),
        _question('later', QuestionType.text),
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

      expect(nextIndex, questions.length - 1);
      expect(answers['record_key'], 'existing-key');
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

  group('SurveyNavigationService.isGeneratedIdField', () {
    bool decide(
      Question question, {
      bool hasRegistryEntry = false,
      String? linkingField,
      String? incrementField,
    }) =>
        SurveyNavigationService.isGeneratedIdField(
          question,
          hasRegistryEntry: hasRegistryEntry,
          linkingField: linkingField,
          incrementField: incrementField,
        );

    test('an automatic field with no calculation is an ID to generate', () {
      expect(decide(_question('subjid', QuestionType.automatic)), isTrue);
    });

    test('a field the AutoFields registry knows is not', () {
      // Adding a name to that registry therefore removes it from ID
      // generation -- a sharp edge worth pinning down.
      expect(
        decide(_question('uniqueid', QuestionType.automatic),
            hasRegistryEntry: true),
        isFalse,
      );
    });

    test('a field with its own calculation is not', () {
      expect(
        decide(_question('derived', QuestionType.automatic,
            calculation: CalculationConfig(type: 'constant', value: '1'))),
        isFalse,
      );
    });

    test('a datetime-typed field with no calculation is not', () {
      // No legitimate ID target is ever typed datetime; such a field is a
      // pre-calc:timestamp custom timestamp from an already-generated survey.
      expect(
        decide(_question('visit_ts', QuestionType.automatic,
            fieldType: 'datetime')),
        isFalse,
      );
    });

    test('the screen\'s own linking and increment fields are not', () {
      expect(
        decide(_question('hhid', QuestionType.automatic),
            linkingField: 'hhid'),
        isFalse,
      );
      expect(
        decide(_question('linenum', QuestionType.automatic),
            incrementField: 'linenum'),
        isFalse,
      );
    });

    test('matches the linking and increment fields case-insensitively', () {
      // crfs values arrive verbatim from a worksheet while fieldnames come
      // from the XML, so a case difference between the two must not decide
      // whether a primary key gets regenerated.
      expect(
        decide(_question('HHID', QuestionType.automatic),
            linkingField: 'hhid'),
        isFalse,
      );
      expect(
        decide(_question('linenum', QuestionType.automatic),
            incrementField: 'LINENUM'),
        isFalse,
      );
    });

    // The defect this predicate was extracted for. RecordSelectorScreen
    // passed neither field, and advanceFromQuestion routes hidden primary
    // keys through the automatic-question path precisely in edit mode -- so
    // both guards were null and every primary-key field of a record being
    // edited reached the generator, renumbering increments on edit.
    test('a caller that knows neither field sends every key to the generator',
        () {
      expect(decide(_question('hhid', QuestionType.automatic)), isTrue);
      expect(decide(_question('linenum', QuestionType.automatic)), isTrue);

      // With the fields carried through, both are protected.
      expect(
        decide(_question('hhid', QuestionType.automatic),
            linkingField: 'hhid', incrementField: 'linenum'),
        isFalse,
      );
      expect(
        decide(_question('linenum', QuestionType.automatic),
            linkingField: 'hhid', incrementField: 'linenum'),
        isFalse,
      );
    });
  });
}

Question _question(
  String fieldName,
  QuestionType type, {
  CalculationConfig? calculation,
  List<SkipCondition> preSkips = const [],
  List<SkipCondition> postSkips = const [],
  String fieldType = 'text',
}) {
  return Question(
    type: type,
    fieldName: fieldName,
    fieldType: fieldType,
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
