/// What the repeat loop should do next, having tried one child.
enum RepeatStep {
  /// Open the child form for this iteration.
  openChild,

  /// The interviewer left without saving and the count must be met exactly:
  /// tell them, then try the same iteration again.
  insistAndRetry,

  /// The interviewer left without saving and fewer children exist than the
  /// count question's own LowerRange allows: tell them, then try again.
  belowMinimumAndRetry,

  /// The interviewer left without saving and is allowed to: stop the loop.
  stop,

  /// Every iteration is done.
  finished,
}

/// How a repeat loop ended.
class RepeatLoopOutcome {
  const RepeatLoopOutcome({
    required this.completed,
    required this.requested,
    required this.iterations,
    required this.abandoned,
    required this.livelocked,
  });

  /// Children actually saved.
  final int completed;

  /// Children the parent said there would be.
  final int requested;

  /// How many times round the loop, retries included. Only interesting when
  /// something went wrong.
  final int iterations;

  /// True when the interviewer left before completing the requested number.
  final bool abandoned;

  /// True when [RepeatLoopRunner.maxIterations] was hit.
  ///
  /// Not reachable by a person: modes that retry do so because the interviewer
  /// was told to finish the form, and eventually they do. A driver that always
  /// declines never terminates, so this exists to turn a hang into a report.
  final bool livelocked;
}

/// Opens a child form once per repeat, and decides what to do when one is
/// abandoned.
///
/// Pulled out of `SurveyScreen._startRepeatSurveyLoop` following the pattern
/// `RepeatPlanService` already set, and says so in its own doc comment: the
/// service decides, the screen supplies the prompts and the `Navigator.push`
/// per child. Here that split is four callbacks -- and four callbacks rather
/// than an interface, because an interface whose second implementation only
/// ever exists in a test is a structure the codebase pays for forever.
///
/// The decisions themselves are the part worth having outside a widget. Which
/// enforce mode retries, which lets the interviewer leave, and where the
/// count is reconciled afterwards were previously only reachable by tapping
/// through a survey, so nothing checked them and nothing could.
class RepeatLoopRunner {
  const RepeatLoopRunner();

  /// A bound on iterations, including retries.
  ///
  /// See [RepeatLoopOutcome.livelocked]: the retry branches are deliberately
  /// unbounded for a human, so a headless driver needs something that stops.
  static const int maxIterations = 1000;

  /// What to do after one iteration.
  ///
  /// [childSaved] is the child form's own result -- true only when it saved.
  /// [belowDeclaredMinimum] is the count question's LowerRange gate, which the
  /// caller evaluates because it costs a database read.
  static RepeatStep nextStep({
    required int index,
    required int requested,
    required bool childSaved,
    required int enforceMode,
    required bool belowDeclaredMinimum,
  }) {
    if (index > requested) return RepeatStep.finished;
    if (childSaved) {
      return index >= requested ? RepeatStep.finished : RepeatStep.openChild;
    }

    // Mode 2 has no "Exit Anyway" -- the dialog it shows offers only Continue,
    // so the retry is unconditional and the loop cannot be left short.
    if (enforceMode == 2) return RepeatStep.insistAndRetry;

    // Every other mode lets the interviewer leave, but not below the floor the
    // count question itself declares. A household cannot have zero members, so
    // walking out must not leave a count the form would have rejected.
    if (belowDeclaredMinimum) return RepeatStep.belowMinimumAndRetry;

    return RepeatStep.stop;
  }

  /// Runs the loop.
  ///
  /// [openChild] opens one child form and returns whether it saved -- a
  /// `Navigator.push` in the app, and a simulated interview in the testing
  /// app. [insist] and [warnBelowMinimum] show the two dialogs. [isBelowMinimum]
  /// answers the LowerRange gate. [reconcile] runs once at the end, whether or
  /// not every child was entered. [shouldContinue] lets a caller that can be
  /// disposed (a widget) stop the loop.
  Future<RepeatLoopOutcome> run({
    required int requested,
    required int enforceMode,
    required Future<bool> Function(int index, int completed) openChild,
    required Future<void> Function(int index, int completed) insist,
    required Future<void> Function(int index, int completed) warnBelowMinimum,
    required Future<bool> Function() isBelowMinimum,
    required Future<void> Function() reconcile,
    bool Function()? shouldContinue,
  }) async {
    var completed = 0;
    var index = 1;
    var iterations = 0;
    var abandoned = false;
    var livelocked = false;

    while (index <= requested) {
      if (shouldContinue != null && !shouldContinue()) {
        abandoned = true;
        break;
      }
      if (++iterations > maxIterations) {
        livelocked = true;
        abandoned = true;
        break;
      }

      final saved = await openChild(index, completed);
      if (saved) completed++;

      final belowMinimum =
          saved || enforceMode == 2 ? false : await isBelowMinimum();

      final step = nextStep(
        index: index,
        requested: requested,
        childSaved: saved,
        enforceMode: enforceMode,
        belowDeclaredMinimum: belowMinimum,
      );

      switch (step) {
        case RepeatStep.openChild:
          index++;
        case RepeatStep.finished:
          index++;
        case RepeatStep.insistAndRetry:
          await insist(index, completed);
        // Same index again -- the iteration is retried, not skipped.
        case RepeatStep.belowMinimumAndRetry:
          await warnBelowMinimum(index, completed);
        case RepeatStep.stop:
          abandoned = true;
          index = requested + 1;
      }
    }

    if (shouldContinue == null || shouldContinue()) {
      await reconcile();
    }

    return RepeatLoopOutcome(
      completed: completed,
      requested: requested,
      iterations: iterations,
      abandoned: abandoned || completed < requested,
      livelocked: livelocked,
    );
  }
}
