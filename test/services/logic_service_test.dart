import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/logic_service.dart';

Question _checkboxQuestion(String condition, {String message = 'Invalid'}) {
  return Question(
    type: QuestionType.checkbox,
    fieldName: 'symptoms',
    fieldType: 'text',
    logicChecks: [LogicCheck(message: message, condition: condition)],
  );
}

void main() {
  group('contains / does not contain', () {
    test('contains is true when the value is in a List answer', () {
      final q = _checkboxQuestion("symptoms contains '99'");
      final result = LogicService.evaluateLogicChecks(
        q,
        {'symptoms': ['1', '99']},
      );
      expect(result, isNotNull); // condition true -> check fails -> message returned
    });

    test('contains is false when the value is not in a List answer', () {
      final q = _checkboxQuestion("symptoms contains '99'");
      final result = LogicService.evaluateLogicChecks(
        q,
        {'symptoms': ['1', '2']},
      );
      expect(result, isNull);
    });

    test('does not contain negates membership', () {
      final q = _checkboxQuestion("symptoms does not contain '99'");
      final passes = LogicService.evaluateLogicChecks(
        q,
        {'symptoms': ['1', '99']},
      );
      expect(passes, isNull);

      final fails = LogicService.evaluateLogicChecks(
        q,
        {'symptoms': ['1', '2']},
      );
      expect(fails, isNotNull);
    });

    test('falls back to a comma-separated string answer', () {
      final q = _checkboxQuestion("symptoms contains '99'");
      final result = LogicService.evaluateLogicChecks(
        q,
        {'symptoms': '1,99'},
      );
      expect(result, isNotNull);
    });
  });

  group('symptoms mutual-exclusion check', () {
    final condition = "symptoms contains '99' and (symptoms contains '1' or "
        "symptoms contains '2' or symptoms contains '3' or symptoms contains '4' or "
        "symptoms contains '5' or symptoms contains '6' or symptoms contains '7' or "
        "symptoms contains '8' or symptoms contains '9' or symptoms contains '10' or "
        "symptoms contains '11' or symptoms contains '12')";

    test('exclusive value alone passes', () {
      final q = _checkboxQuestion(condition, message: 'Cannot combine');
      final result = LogicService.evaluateLogicChecks(q, {
        'symptoms': ['99'],
      });
      expect(result, isNull);
    });

    test('exclusive value with another symptom fails with the message', () {
      final q = _checkboxQuestion(condition, message: 'Cannot combine');
      final result = LogicService.evaluateLogicChecks(q, {
        'symptoms': ['99', '3'],
      });
      expect(result, 'Cannot combine');
    });

    test('normal symptoms without the exclusive value pass', () {
      final q = _checkboxQuestion(condition, message: 'Cannot combine');
      final result = LogicService.evaluateLogicChecks(q, {
        'symptoms': ['1', '2', '12'],
      });
      expect(result, isNull);
    });
  });

  group('existing operators still work (regression)', () {
    test('numeric equality', () {
      final question = Question(
        type: QuestionType.text,
        fieldName: 'age',
        fieldType: 'text',
        logicChecks: [
          LogicCheck(message: 'must be 18', condition: 'age = 18')
        ],
      );
      final result = LogicService.evaluateLogicChecks(question, {'age': '18'});
      expect(result, 'must be 18');
    });

    test('date comparison', () {
      final question = Question(
        type: QuestionType.date,
        fieldName: 'dob',
        fieldType: 'date',
        logicChecks: [
          LogicCheck(
              message: 'must be after 2020', condition: "dob < '2020-01-01'")
        ],
      );
      final result = LogicService.evaluateLogicChecks(
          question, {'dob': '2019-06-01'});
      expect(result, 'must be after 2020');
    });

    test('AND/OR with parentheses', () {
      final question = Question(
        type: QuestionType.text,
        fieldName: 'status',
        fieldType: 'text',
        logicChecks: [
          LogicCheck(
              message: 'invalid status',
              condition: '(status = 1 or status = 2) and status <> 2')
        ],
      );
      final result =
          LogicService.evaluateLogicChecks(question, {'status': '1'});
      expect(result, 'invalid status');
    });
  });
}
