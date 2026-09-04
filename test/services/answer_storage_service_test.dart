import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/answer_storage_service.dart';

/// The pure steps of the save path, previously untestable inside
/// `SurveyScreen._showDone`.
///
/// Two of the three decide what reaches the database, and both of their
/// failure modes are silent: `hasChanges` reporting false skips the write
/// entirely, and `clearSkippedAnswers` nulling the wrong field destroys an
/// answer the interviewer gave. Neither shows up as an error.

Question q(
  String fieldName, {
  QuestionType type = QuestionType.text,
}) =>
    Question(
      fieldName: fieldName,
      type: type,
      fieldType: type == QuestionType.date
          ? 'date'
          : type == QuestionType.datetime
              ? 'datetime'
              : 'text',
      text: fieldName,
    );

void main() {
  group('hasChanges', () {
    test('a new record always has changes', () {
      expect(AnswerStorageService.hasChanges({'a': '1'}, null), isTrue);
      expect(AnswerStorageService.hasChanges({}, null), isTrue);
    });

    test('an untouched record has none', () {
      final answers = {'hhnum': '1', 'sex': '2'};

      expect(
        AnswerStorageService.hasChanges(answers, {'hhnum': '1', 'sex': '2'}),
        isFalse,
      );
    });

    test('an edited value is a change', () {
      expect(
        AnswerStorageService.hasChanges({'hhnum': '2'}, {'hhnum': '1'}),
        isTrue,
      );
    });

    test('a re-padded fixed-length value is not a change', () {
      // "04" and "4" are the same answer. Reporting this would show the
      // interviewer a review dialog listing an edit they never made.
      expect(
        AnswerStorageService.hasChanges({'hhnum': '04'}, {'hhnum': '4'}),
        isFalse,
      );
    });

    test('two spellings of the same instant are not a change', () {
      // What a round trip through SQLite produces.
      expect(
        AnswerStorageService.hasChanges(
          {'visit': '2025-12-09T11:22:00.000'},
          {'visit': '2025-12-09 11:22:00.000'},
        ),
        isFalse,
      );
    });

    test('a genuinely different instant is a change', () {
      expect(
        AnswerStorageService.hasChanges(
          {'visit': '2025-12-09T11:22:00.000'},
          {'visit': '2025-12-09T11:23:00.000'},
        ),
        isTrue,
      );
    });

    test('lastmod, swver and survey_id never count', () {
      // They change on every save by definition, so counting them would make
      // "no changes" impossible to reach.
      expect(
        AnswerStorageService.hasChanges(
          {'lastmod': 'b', 'swver': 'b', 'survey_id': 'b', 'hhnum': '1'},
          {'lastmod': 'a', 'swver': 'a', 'survey_id': 'a', 'hhnum': '1'},
        ),
        isFalse,
      );
    });

    test('a removed answer is a change', () {
      expect(
        AnswerStorageService.hasChanges({}, {'hhnum': '1'}),
        isTrue,
      );
    });

    test('an added answer is a change', () {
      expect(
        AnswerStorageService.hasChanges({'hhnum': '1'}, {}),
        isTrue,
      );
    });

    group('checkbox lists', () {
      test('the same selections in the same order are not a change', () {
        expect(
          AnswerStorageService.hasChanges(
            {'nets': ['1', '2']},
            {'nets': ['1', '2']},
          ),
          isFalse,
        );
      });

      test('a different length is a change', () {
        expect(
          AnswerStorageService.hasChanges(
            {'nets': ['1', '2', '3']},
            {'nets': ['1', '2']},
          ),
          isTrue,
        );
      });

      test('a different member is a change', () {
        expect(
          AnswerStorageService.hasChanges(
            {'nets': ['1', '3']},
            {'nets': ['1', '2']},
          ),
          isTrue,
        );
      });
    });

    test('DateTime objects compare by value', () {
      final a = DateTime(2025, 12, 9, 11, 22);
      final b = DateTime(2025, 12, 9, 11, 22);
      final c = DateTime(2025, 12, 9, 11, 23);

      expect(AnswerStorageService.hasChanges({'v': a}, {'v': b}), isFalse);
      expect(AnswerStorageService.hasChanges({'v': a}, {'v': c}), isTrue);
    });
  });

  group('clearSkippedAnswers', () {
    final questions = [
      q('sex'),
      q('pregnant'),
      q('hhid'),
      q('starttime', type: QuestionType.automatic),
      q('intro', type: QuestionType.information),
    ];

    test('nulls an answered field the interviewer never reached', () {
      // Sex changed to male after pregnant was answered.
      final answers = <String, dynamic>{'sex': '1', 'pregnant': '1'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {'sex'},
        primaryKeyFields: null,
      );

      expect(answers['sex'], '1');
      expect(answers.containsKey('pregnant'), isTrue);
      expect(answers['pregnant'], isNull);
    });

    test('leaves a visited field alone', () {
      final answers = <String, dynamic>{'sex': '2', 'pregnant': '1'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {'sex', 'pregnant'},
        primaryKeyFields: null,
      );

      expect(answers['pregnant'], '1');
    });

    test('never clears a primary key, however unvisited', () {
      // A composite key of automatic fields is computed, never displayed --
      // clearing one would destroy the record's identity.
      final answers = <String, dynamic>{'hhid': '1010001', 'pregnant': '1'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {},
        primaryKeyFields: ['hhid'],
      );

      expect(answers['hhid'], '1010001');
      expect(answers['pregnant'], isNull);
    });

    test('matches a primary key case-insensitively', () {
      final answers = <String, dynamic>{'hhid': '1010001'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {},
        primaryKeyFields: ['HHID'],
      );

      expect(answers['hhid'], '1010001');
    });

    test('leaves automatic and information fields alone', () {
      // They are never "visited" -- they never render -- so treating them as
      // skipped would blank every system variable on every save.
      final answers = <String, dynamic>{'starttime': '2025-12-09T09:00', 'intro': 'x'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {},
        primaryKeyFields: null,
      );

      expect(answers['starttime'], '2025-12-09T09:00');
      expect(answers['intro'], 'x');
    });

    test('ignores an answer with no matching question', () {
      final answers = <String, dynamic>{'not_in_this_form': 'x'};

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {},
        primaryKeyFields: null,
      );

      expect(answers['not_in_this_form'], 'x');
    });

    test('mutates the map it was given, rather than a copy', () {
      // Load-bearing: the screen hands over its one shared answer map, and
      // every question view holds the same reference.
      final answers = <String, dynamic>{'sex': '1', 'pregnant': '1'};
      final sameMap = answers;

      AnswerStorageService.clearSkippedAnswers(
        answers: answers,
        questions: questions,
        visitedFields: {'sex'},
        primaryKeyFields: null,
      );

      expect(sameMap['pregnant'], isNull);
    });
  });

  group('coerceForStorage', () {
    final questions = [
      q('visit_date', type: QuestionType.date),
      q('visit_time', type: QuestionType.datetime),
      q('hhnum'),
    ];

    test('a date is stored as YYYY-MM-DD', () {
      final out = AnswerStorageService.coerceForStorage(
        {'visit_date': DateTime(2025, 12, 9, 11, 22)},
        questions,
      );

      expect(out['visit_date'], '2025-12-09');
    });

    test('a datetime keeps its time', () {
      final out = AnswerStorageService.coerceForStorage(
        {'visit_time': DateTime(2025, 12, 9, 11, 22)},
        questions,
      );

      expect(out['visit_time'], '2025-12-09T11:22:00.000');
    });

    test('a date already in string form is normalised too', () {
      final out = AnswerStorageService.coerceForStorage(
        {'visit_date': '2025-12-09T11:22:00.000'},
        questions,
      );

      expect(out['visit_date'], '2025-12-09');
    });

    test('a text answer is untouched, padding and all', () {
      final out = AnswerStorageService.coerceForStorage(
        {'hhnum': '0042'},
        questions,
      );

      expect(out['hhnum'], '0042');
    });

    test('an unparseable date is left exactly as it is', () {
      // Refusing to guess keeps a bad value visible instead of blanking it.
      final out = AnswerStorageService.coerceForStorage(
        {'visit_date': 'not a date'},
        questions,
      );

      expect(out['visit_date'], 'not a date');
    });

    test('a null is skipped rather than coerced', () {
      final out = AnswerStorageService.coerceForStorage(
        {'visit_date': null},
        questions,
      );

      expect(out.containsKey('visit_date'), isTrue);
      expect(out['visit_date'], isNull);
    });

    test('returns a copy, leaving the screen\'s own map alone', () {
      // The one place a copy is correct: the coerced values go to the
      // database while `_answers` stays as the question views know it.
      final answers = <String, dynamic>{
        'visit_date': DateTime(2025, 12, 9),
      };

      final out = AnswerStorageService.coerceForStorage(answers, questions);

      expect(out['visit_date'], '2025-12-09');
      expect(answers['visit_date'], isA<DateTime>());
    });

    test('copies everything through when there are no questions yet', () {
      final out = AnswerStorageService.coerceForStorage({'hhnum': '1'}, null);

      expect(out, {'hhnum': '1'});
    });
  });
}
