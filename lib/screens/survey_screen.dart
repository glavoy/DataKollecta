import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../widgets/question_views.dart';
import '../services/db_service.dart';
import '../services/auto_fields.dart';
import '../services/skip_service.dart';
import '../config/app_config.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final AnswerMap _answers = {};
  int _currentQuestion = 0;
  final List<int> _history = []; // Navigation history of displayed questions
  late Future<List<Question>> _questions = _loadSurvey();

  Future<List<Question>> _loadSurvey() async {
    try {
      // 1) init DB
      await DbService.init();

      // 2) load questions for UI from the survey XML
      // The database tables are pre-created by another app, so we just load the XML
      return SurveyLoader.loadFromAsset(AppConfig.surveyAssetPath);
    } catch (e) {
      // If database initialization fails, still allow viewing the survey
      // but warn the user
      debugPrint('Warning: Database initialization failed: $e');
      debugPrint('Survey will load but data cannot be saved.');
      return SurveyLoader.loadFromAsset(AppConfig.surveyAssetPath);
    }
  }

  /// Navigate to the next question, auto-skipping automatic questions
  /// Information questions ARE displayed to the user
  void _next(List<Question> qs) {
    if (_currentQuestion >= qs.length - 1) return;

    // Push current displayed question to history (skip automatic)
    if (qs[_currentQuestion].type != QuestionType.automatic) {
      _history.add(_currentQuestion);
      // history keeps track of previous questions implicitly
    }

    // Check for postskip conditions on the current question
    final currentQ = qs[_currentQuestion];
    final postSkipTarget = SkipService.evaluateSkips(currentQ.postSkips, _answers);

    int nextIndex;
    if (postSkipTarget != null) {
      // Postskip condition met - find the target question
      nextIndex = _findQuestionByFieldName(qs, postSkipTarget);
      if (nextIndex == -1) {
        // Target not found, go to next question normally
        nextIndex = _currentQuestion + 1;
      }
    } else {
      // No postskip, move to next question
      nextIndex = _currentQuestion + 1;
    }

    // Skip automatic questions and evaluate preskips
    nextIndex = _findNextDisplayedQuestion(qs, nextIndex);

    setState(() {
      _currentQuestion = nextIndex;
    });
  }

  /// Find the next question that should be displayed
  /// Handles automatic questions and preskip conditions
  int _findNextDisplayedQuestion(List<Question> qs, int startIndex) {
    int index = startIndex;

    while (index < qs.length) {
      final q = qs[index];

      // Process and skip automatic questions
      if (q.type == QuestionType.automatic) {
        _processAutomaticQuestion(q);
        index++;
        continue;
      }

      // Check preskip conditions
      final preSkipTarget = SkipService.evaluateSkips(q.preSkips, _answers);
      if (preSkipTarget != null) {
        // Preskip condition met - jump to target
        final targetIndex = _findQuestionByFieldName(qs, preSkipTarget);
        if (targetIndex != -1) {
          index = targetIndex;
          continue; // Re-evaluate the target question
        }
      }

      // This question should be displayed
      return index;
    }

    // Reached end of survey
    return qs.length - 1;
  }

  /// Find a question by its fieldName
  int _findQuestionByFieldName(List<Question> qs, String fieldName) {
    for (int i = 0; i < qs.length; i++) {
      if (qs[i].fieldName == fieldName) {
        return i;
      }
    }
    return -1; // Not found
  }

  /// Navigate to the previous displayed question
  void _prev() {
    if (_history.isEmpty) return;
    setState(() {
      _currentQuestion = _history.removeLast();
    });
  }

  bool _isAnswered(Question q) {
    final val = _answers[q.fieldName];
    switch (q.type) {
      case QuestionType.text:
        return (val is String) && val.trim().isNotEmpty;
      case QuestionType.radio:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.checkbox:
        return (val is List) && val.isNotEmpty;
      case QuestionType.combobox:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.date:
      case QuestionType.datetime:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.information:
      case QuestionType.automatic:
        return true; // not applicable
    }
  }

  bool _isValid(Question q) {
    // For integer text fields, enforce numeric_check range
    if (q.type == QuestionType.text && q.fieldType.toLowerCase().contains('integer')) {
      final raw = _answers[q.fieldName]?.toString() ?? '';
      if (raw.isEmpty) return false;
      final parsed = int.tryParse(raw);
      if (parsed == null) return false;
      final nc = q.numericCheck;
      if (nc != null) {
        final exceptions = (nc.otherValues ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        if (!exceptions.contains(parsed.toString())) {
          if (nc.minValue != null && parsed < nc.minValue!) return false;
          if (nc.maxValue != null && parsed > nc.maxValue!) return false;
        }
      }
    }
    return true;
  }

  // Previous question lookup is handled by _history

  /// Process an automatic question by calculating its value
  void _processAutomaticQuestion(Question q) {
    // The automatic value calculation is already handled in QuestionView.initState
    // But we can also do it here for automatic questions we skip over
    if (_answers[q.fieldName] == null) {
      final value = AutoFields.compute(_answers, q);
      _answers[q.fieldName] = value;
    }
  }

  /// Skip to the first question that should be displayed (on initial load)
  /// Only skips automatic questions, information questions are displayed
  void _skipToFirstDisplayedQuestion(List<Question> questions) {
    if (_currentQuestion == 0 && questions[0].type == QuestionType.automatic) {
      // Process all automatic questions at the start
      int index = 0;
      while (index < questions.length &&
          questions[index].type == QuestionType.automatic) {
        _processAutomaticQuestion(questions[index]);
        index++;
      }

      if (index < questions.length && index != _currentQuestion) {
        setState(() {
          _currentQuestion = index;
        });
      }
    }
  }

  /// Check if there's a next question to display (not automatic)
  /// Information questions ARE displayed
  bool _hasNextDisplayedQuestion(List<Question> questions, int fromIndex) {
    for (int i = fromIndex + 1; i < questions.length; i++) {
      if (questions[i].type != QuestionType.automatic) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Question>>(
      future: _questions,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
        }

        final questions = snap.data!;

        // Skip automatic and information questions on initial load
        if (_currentQuestion == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _skipToFirstDisplayedQuestion(questions);
          });
        }

        final q = questions[_currentQuestion];
        final isFirst = _history.isEmpty;
        final canProceed = q.type == QuestionType.information || (_isAnswered(q) && _isValid(q));
        final isLast = _currentQuestion == questions.length - 1 ||
            !_hasNextDisplayedQuestion(questions, _currentQuestion);
        final progress = (_currentQuestion + 1) / questions.length;

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 120,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/branding/gistx.png',
                    width: 100,
                    height: 100,
                  ),
                ),
                const SizedBox(width: 10),
                // const Text("Geoff's Dart Questionnaire"), // or your new name
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: FilledButton.tonal(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Cancel Interview'),
                        content: const Text(
                            'Are you sure you want to cancel the interview? \n\nAll data will be lost!'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('No'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop(); // Close dialog
                              Navigator.of(context)
                                  .pop(); // Return to main screen
                            },
                            child: const Text('Yes'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancel Interview'),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header with progress
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                      'Step ${_currentQuestion + 1} of ${questions.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const Spacer(),
                                  Text('${(progress * 100).round()}%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                    value: progress, minHeight: 8),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Animated question card
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: Card(
                            key: ValueKey(
                                q.fieldName), // forces fresh state per question
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: SingleChildScrollView(
                                child: QuestionView(
                                  key: ValueKey('view_${q.fieldName}'),
                                  question: q,
                                  answers: _answers,
                                  onAnswerChanged: () => setState(() {}),
                                  onRequestNext: () => _next(questions),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Nav bar
                      Row(
                        children: [
                          if (!isFirst)
                            OutlinedButton.icon(
                              onPressed: _prev,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Previous'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          if (!isFirst) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: canProceed
                                  ? () => isLast
                                      ? _showDone(context)
                                      : _next(questions)
                                  : null,
                              icon: Icon(
                                  isLast ? Icons.check : Icons.arrow_forward),
                              label: Text(isLast ? 'Finish' : 'Next'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDone(BuildContext context) async {
    final questions = await _questions; // already loaded
    final surveyFilename = await DbService.firstSurveyId();
    if (surveyFilename == null) return;

    bool saveSuccessful = false;
    String? errorMessage;

    try {
      await DbService.saveInterview(
        surveyFilename: surveyFilename,
        answers: _answers,
        questions: questions,
      );
      saveSuccessful = true;
    } catch (e) {
      // Capture the error to show in dialog
      errorMessage = e.toString();
      debugPrint('Save failed: $e');
    }

    if (!mounted) return;

    if (saveSuccessful) {
      // Success dialog
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('All done!'),
          content: Text(
              'Thanks! Answers saved successfully.\n\nInterview ID: ${_answers['uniqueid']}\nDatabase: ${DbService.databasePath ?? 'Unknown'}'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Return to main screen
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
    } else {
      // Error dialog
      if (AppConfig.enableErrorDialogs) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('Save Failed'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Failed to save the interview data to the database.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text('Error details:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      errorMessage ?? 'Unknown error',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please check:\n'
                    '• Database file exists at the configured path\n'
                    '• Table name matches the survey filename\n'
                    '• All required columns exist in the table',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Return to main screen
                },
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }
}
