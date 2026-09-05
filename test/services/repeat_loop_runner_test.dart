import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/services/repeat_loop_runner.dart';

/// The decisions the repeat loop makes, which were previously reachable only
/// by tapping through a survey.
///
/// The enforce modes are the whole point: 2 is the one that cannot be left
/// short, and every other mode can be left but not below the floor the count
/// question declares. Those two rules decide whether a household ends up with
/// the number of members it said it had.
void main() {
  group('nextStep', () {
    RepeatStep step({
      int index = 1,
      int requested = 3,
      bool childSaved = true,
      int enforceMode = 1,
      bool belowDeclaredMinimum = false,
    }) =>
        RepeatLoopRunner.nextStep(
          index: index,
          requested: requested,
          childSaved: childSaved,
          enforceMode: enforceMode,
          belowDeclaredMinimum: belowDeclaredMinimum,
        );

    test('carries on to the next child after one saves', () {
      expect(step(index: 1, requested: 3), RepeatStep.openChild);
    });

    test('finishes once the last requested child saves', () {
      expect(step(index: 3, requested: 3), RepeatStep.finished);
    });

    test('force mode insists rather than letting the loop end', () {
      // Mode 2's dialog offers only Continue, so this retry is unconditional.
      for (final index in [1, 2, 3]) {
        expect(
          step(index: index, childSaved: false, enforceMode: 2),
          RepeatStep.insistAndRetry,
          reason: 'mode 2 has no exit, at any point in the loop',
        );
      }
    });

    test('force mode ignores the minimum gate, having already refused', () {
      expect(
        step(childSaved: false, enforceMode: 2, belowDeclaredMinimum: true),
        RepeatStep.insistAndRetry,
      );
    });

    test('every other mode lets the interviewer leave', () {
      for (final mode in [0, 1, 3]) {
        expect(
          step(childSaved: false, enforceMode: mode),
          RepeatStep.stop,
          reason: 'mode $mode should allow an early exit',
        );
      }
    });

    test('but not below the count question own floor', () {
      for (final mode in [0, 1, 3]) {
        expect(
          step(childSaved: false, enforceMode: mode, belowDeclaredMinimum: true),
          RepeatStep.belowMinimumAndRetry,
          reason: 'mode $mode must not leave a count the form would reject',
        );
      }
    });
  });

  group('run', () {
    /// Records what the loop asked for, so the sequence can be asserted rather
    /// than only the totals.
    Future<RepeatLoopOutcome> drive({
      required int requested,
      required int enforceMode,
      required bool Function(int index) saves,
      bool belowMinimum = false,
      List<String>? log,
    }) {
      return const RepeatLoopRunner().run(
        requested: requested,
        enforceMode: enforceMode,
        openChild: (index, completed) async {
          log?.add('open $index (completed $completed)');
          return saves(index);
        },
        insist: (index, completed) async => log?.add('insist $index'),
        warnBelowMinimum: (index, completed) async => log?.add('warn $index'),
        isBelowMinimum: () async => belowMinimum,
        reconcile: () async => log?.add('reconcile'),
      );
    }

    test('opens the child once per requested record', () async {
      final log = <String>[];
      final outcome = await drive(
        requested: 3,
        enforceMode: 1,
        saves: (_) => true,
        log: log,
      );

      expect(outcome.completed, 3);
      expect(outcome.abandoned, isFalse);
      expect(log, [
        'open 1 (completed 0)',
        'open 2 (completed 1)',
        'open 3 (completed 2)',
        'reconcile',
      ]);
    });

    test('retries the same index in force mode, not the next one', () async {
      final log = <String>[];
      var refusals = 2;
      await drive(
        requested: 2,
        enforceMode: 2,
        saves: (_) => refusals-- <= 0,
        log: log,
      );

      // Index 1 is attempted three times: refused, refused, then saved.
      expect(log.where((l) => l.startsWith('open 1')).length, 3);
      expect(log.where((l) => l == 'insist 1').length, 2);
    });

    test('stops early when a mode that allows it is abandoned', () async {
      final log = <String>[];
      final outcome = await drive(
        requested: 5,
        enforceMode: 1,
        saves: (index) => index == 1,
        log: log,
      );

      expect(outcome.completed, 1);
      expect(outcome.abandoned, isTrue);
      expect(log.where((l) => l.startsWith('open')).length, 2);
      expect(log.last, 'reconcile',
          reason: 'the count is reconciled even when the loop ends early');
    });

    test('reports a livelock instead of hanging', () async {
      // No person can produce this: mode 2 retries because the interviewer was
      // told to finish, and eventually they do. A driver that always declines
      // would spin forever, so the bound turns a hang into a finding.
      final outcome = await drive(
        requested: 1,
        enforceMode: 2,
        saves: (_) => false,
      );

      expect(outcome.livelocked, isTrue);
      expect(outcome.iterations, RepeatLoopRunner.maxIterations + 1);
    });

    test('stops when the caller has gone away, without reconciling', () async {
      final log = <String>[];
      final outcome = await const RepeatLoopRunner().run(
        requested: 3,
        enforceMode: 1,
        shouldContinue: () => false,
        openChild: (i, c) async => true,
        insist: (i, c) async {},
        warnBelowMinimum: (i, c) async {},
        isBelowMinimum: () async => false,
        reconcile: () async => log.add('reconcile'),
      );

      expect(outcome.completed, 0);
      expect(log, isEmpty,
          reason: 'a disposed screen must not write to the parent');
    });
  });
}
