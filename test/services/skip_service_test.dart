import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/skip_service.dart';

/// The coverage hook on skip evaluation.
///
/// It exists for `DataKollecta-SurveyTest`, which has to tell a rule that was
/// tried and did not fire from one that was never reached at all -- a green
/// run whose branches were never taken proves nothing about them. The two
/// properties that make it useful are pinned here: an unanswered tested field
/// is reported as "did not fire" rather than not reported, and rules behind a
/// match are reported not at all.
SkipCondition rule(
  String field,
  String condition,
  String response,
  String target,
) =>
    SkipCondition(
      fieldName: field,
      condition: condition,
      response: response,
      responseType: 'fixed',
      skipToFieldName: target,
    );

void main() {
  group('evaluateSkip onEvaluated', () {
    test('reports a rule that fired', () {
      final r = rule('sex', '=', '1', 'treatment');
      final seen = <SkipCondition, bool>{};

      SkipService.evaluateSkip(r, {'sex': '1'},
          onEvaluated: (s, fired) => seen[s] = fired);

      expect(seen, {r: true});
    });

    test('reports a rule that was tried and did not fire', () {
      final r = rule('sex', '=', '1', 'treatment');
      final seen = <SkipCondition, bool>{};

      SkipService.evaluateSkip(r, {'sex': '2'},
          onEvaluated: (s, fired) => seen[s] = fired);

      expect(seen, {r: false});
    });

    test('an unanswered tested field is reported, not silently dropped', () {
      // The fail-open case. It is still an evaluation -- the rule was reached
      // and declined to fire -- and reporting it as "never evaluated" would
      // point the harness at the wrong defect.
      final r = rule('sex', '=', '1', 'treatment');
      final seen = <SkipCondition, bool>{};

      final target = SkipService.evaluateSkip(r, const {},
          onEvaluated: (s, fired) => seen[s] = fired);

      expect(target, isNull);
      expect(seen, {r: false});
    });

    test('the observer is optional and evaluation is unchanged without it',
        () {
      final r = rule('sex', '=', '1', 'treatment');
      expect(SkipService.evaluateSkip(r, {'sex': '1'}), 'treatment');
      expect(SkipService.evaluateSkip(r, {'sex': '2'}), isNull);
      expect(SkipService.evaluateSkip(r, const {}), isNull);
    });
  });

  group('evaluateSkips onEvaluated', () {
    test('rules after the first match are not evaluated', () {
      // First match wins, so the rest never run. That silence is exactly how
      // a shadowed rule shows up in coverage, and papering over it here would
      // hide the thing worth finding.
      final first = rule('sex', '=', '2', 'comments');
      final second = rule('fever48h', '<>', '1', 'symptom_days');
      final order = <SkipCondition>[];

      final target = SkipService.evaluateSkips(
        [first, second],
        {'sex': '2', 'fever48h': '0'},
        onEvaluated: (s, _) => order.add(s),
      );

      expect(target, 'comments');
      expect(order, [first]);
    });

    test('every rule is reported when none matches', () {
      final first = rule('sex', '=', '2', 'comments');
      final second = rule('fever48h', '<>', '1', 'symptom_days');
      final order = <SkipCondition>[];

      final target = SkipService.evaluateSkips(
        [first, second],
        {'sex': '1', 'fever48h': '1'},
        onEvaluated: (s, _) => order.add(s),
      );

      expect(target, isNull);
      expect(order, [first, second]);
    });
  });
}
