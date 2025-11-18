import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../widgets/question_views.dart';
import '../services/db_service.dart';
import '../services/auto_fields.dart';
import '../services/skip_service.dart';
import '../config/app_config.dart';
import '../services/id_generator.dart';

class SurveyScreen extends StatefulWidget {
  final String questionnaireFilename;
  final Map<String, dynamic>? existingAnswers;
  final String? uniqueId;
  final List<String>? primaryKeyFields;
  final Map<String, dynamic>? prepopulatedAnswers;
  final String? idConfig;
  final String? linkingField;

  const SurveyScreen({
    super.key,
    required this.questionnaireFilename,
    this.existingAnswers,
    this.uniqueId,
    this.primaryKeyFields,
    this.prepopulatedAnswers,
    this.idConfig,
    this.linkingField,
  });

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final AnswerMap _answers = {};
  AnswerMap? _originalAnswers; // Store original answers for change detection
  int _currentQuestion = 0;
  final List<int> _history = []; // Navigation history of displayed questions
  final Set<String> _visitedFields =
      {}; // Track which questions were actually displayed
  late Future<List<Question>> _questions = _loadSurvey();
  bool _isSaving = false; // Flag to prevent multiple submissions

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<Question>> _loadSurvey() async {
    try {
      // 1) init DB
      await DbService.init();

      // 2) load questions for UI from the survey XML
      // The database tables are pre-created by another app, so we just load the XML
      final assetPath = 'assets/surveys/${widget.questionnaireFilename}';
      final questions = await SurveyLoader.loadFromAsset(assetPath);

      // 3) If we're editing an existing record, populate answers from the database
      if (widget.existingAnswers != null) {
        _populateAnswersFromRecord(widget.existingAnswers!, questions);
        debugPrint('Primary key fields: ${widget.primaryKeyFields}');
      }

      // 4) If we have prepopulated answers (from parent ID selector), add them
      if (widget.prepopulatedAnswers != null) {
        _answers.addAll(widget.prepopulatedAnswers!);
        debugPrint('Prepopulated answers: ${widget.prepopulatedAnswers}');
      }

      return questions;
    } catch (e) {
      // If database initialization fails, still allow viewing the survey
      // but warn the user
      debugPrint('Warning: Database initialization failed: $e');
      debugPrint('Survey will load but data cannot be saved.');
      final assetPath = 'assets/surveys/${widget.questionnaireFilename}';
      return SurveyLoader.loadFromAsset(assetPath);
    }
  }

  /// Populate the answers map from an existing database record
  void _populateAnswersFromRecord(
      Map<String, dynamic> record, List<Question> questions) {
    // Build a map of field names to question types for quick lookup
    final questionTypes = <String, QuestionType>{};
    for (final q in questions) {
      questionTypes[q.fieldName] = q.type;
    }

    for (final entry in record.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value == null) continue;

      // Convert database values back to their proper types
      // First convert to string for consistent handling
      final stringValue = value.toString();

      // Check if this field is a checkbox type
      final questionType = questionTypes[key];
      if (questionType == QuestionType.checkbox) {
        // For checkbox, always convert to List (even single values)
        if (stringValue.contains(',')) {
          // Multiple values: "3,4"
          final list = stringValue
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          _answers[key] = list;
          debugPrint(
              'Loaded checkbox field "$key": $list (type: ${list.runtimeType})');
        } else if (stringValue.trim().isNotEmpty) {
          // Single value: "2"
          _answers[key] = [stringValue.trim()];
          debugPrint(
              'Loaded checkbox field "$key": [${stringValue.trim()}] (type: ${_answers[key].runtimeType})');
        }
      } else if (stringValue.contains('T') && stringValue.length > 10) {
        // Likely an ISO8601 datetime string
        try {
          _answers[key] = DateTime.parse(stringValue);
        } catch (e) {
          // If parsing fails, just store as string
          _answers[key] = stringValue;
        }
      } else {
        // Store as string (works for radio, combobox, text fields)
        _answers[key] = stringValue;
      }
    }

    // Store a deep copy of the original answers for change detection
    _originalAnswers = _deepCopyAnswers(_answers);
  }

  /// Create a deep copy of the answers map
  AnswerMap _deepCopyAnswers(AnswerMap source) {
    final copy = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is List) {
        copy[entry.key] = List.from(value);
      } else if (value is DateTime) {
        copy[entry.key] = value;
      } else {
        copy[entry.key] = value;
      }
    }
    return copy;
  }

  /// Check if answers have been modified compared to original
  bool _hasChanges() {
    if (_originalAnswers == null) return true; // New record, always has changes

    // Compare each answer
    for (final key in _answers.keys) {
      final newValue = _answers[key];
      final oldValue = _originalAnswers![key];

      // Handle different types
      if (newValue is List && oldValue is List) {
        if (newValue.length != oldValue.length) return true;
        for (int i = 0; i < newValue.length; i++) {
          if (newValue[i].toString() != oldValue[i].toString()) return true;
        }
      } else if (newValue is DateTime && oldValue is DateTime) {
        if (newValue != oldValue) return true;
      } else {
        if (newValue.toString() != oldValue.toString()) return true;
      }
    }

    // Check for removed answers
    for (final key in _originalAnswers!.keys) {
      if (!_answers.containsKey(key)) return true;
    }

    return false;
  }

  /// Clear answers for questions that were skipped (not visited)
  /// This ensures data consistency when skip logic bypasses questions
  /// For example: if sex changes from Female to Male, pregnancy questions should be cleared
  void _clearSkippedAnswers(List<Question> questions) {
    // Get all question field names that should collect data (not automatic/information)
    final dataQuestions = questions
        .where((q) =>
            q.type != QuestionType.automatic &&
            q.type != QuestionType.information)
        .map((q) => q.fieldName)
        .toSet();

    // Also preserve primary key fields (they're skipped but shouldn't be cleared)
    final primaryKeys =
        widget.primaryKeyFields?.map((f) => f.toLowerCase()).toSet() ?? {};

    // Find fields that have answers but were not visited (skipped)
    final skippedFields = <String>[];
    for (final fieldName in _answers.keys) {
      // Check if this is a data question
      if (!dataQuestions.contains(fieldName)) continue;

      // Check if it's a primary key (don't clear these)
      if (primaryKeys.contains(fieldName.toLowerCase())) continue;

      // Check if it was visited
      if (!_visitedFields.contains(fieldName)) {
        skippedFields.add(fieldName);
      }
    }

    // Clear the skipped fields
    if (skippedFields.isNotEmpty) {
      debugPrint(
          'Clearing ${skippedFields.length} skipped fields: ${skippedFields.join(", ")}');
      for (final field in skippedFields) {
        _answers[field] = null;
      }
    }
  }

  /// Called whenever an answer changes - triggers async ID generation if needed
  Future<void> _onAnswerChanged() async {
    setState(() {}); // Update UI
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
    final postSkipTarget =
        SkipService.evaluateSkips(currentQ.postSkips, _answers);

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

      // Skip primary key questions in edit mode
      if (widget.uniqueId != null && _isPrimaryKeyField(q.fieldName)) {
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

  /// Check if a field name is a primary key field
  bool _isPrimaryKeyField(String fieldName) {
    if (widget.primaryKeyFields == null) return false;

    // Case-insensitive comparison
    final fieldLower = fieldName.toLowerCase();
    for (final pkField in widget.primaryKeyFields!) {
      if (pkField.toLowerCase() == fieldLower) {
        debugPrint('Found primary key match: $fieldName matches $pkField');
        return true;
      }
    }
    return false;
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
    if (q.type == QuestionType.text &&
        q.fieldType.toLowerCase().contains('integer')) {
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
      final value =
          AutoFields.compute(_answers, q, isEditMode: widget.uniqueId != null);
      _answers[q.fieldName] = value;
    }
  }

  /// Skip to the first question that should be displayed (on initial load)
  /// Skips automatic questions and primary key questions in edit mode
  void _skipToFirstDisplayedQuestion(List<Question> questions) {
    if (_currentQuestion == 0) {
      int index = 0;

      // Find the first displayable question
      while (index < questions.length) {
        final q = questions[index];

        // Process and skip automatic questions
        if (q.type == QuestionType.automatic) {
          _processAutomaticQuestion(q);
          index++;
          continue;
        }

        // Skip primary key questions in edit mode
        if (widget.uniqueId != null && _isPrimaryKeyField(q.fieldName)) {
          debugPrint('Skipping primary key question on load: ${q.fieldName}');
          index++;
          continue;
        }

        // Found a displayable question
        break;
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
      final q = questions[i];
      // Skip automatic questions
      if (q.type == QuestionType.automatic) continue;
      // Skip primary key questions in edit mode
      if (widget.uniqueId != null && _isPrimaryKeyField(q.fieldName)) continue;
      // Found a displayable question
      return true;
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

        // Track that this question was displayed/visited
        // Skip tracking automatic questions as they're never displayed
        if (q.type != QuestionType.automatic) {
          _visitedFields.add(q.fieldName);
        }

        final isFirst = _history.isEmpty;
        final canProceed = q.type == QuestionType.information ||
            (_isAnswered(q) && _isValid(q));
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
                      // Primary key fields display (for edit mode)
                      if (widget.primaryKeyFields != null &&
                          widget.primaryKeyFields!.isNotEmpty)
                        Card(
                          color: Colors.blue.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: 18, color: Colors.blue.shade700),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Viewing/Modifying Record:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...widget.primaryKeyFields!.map((field) {
                                  final value =
                                      _answers[field]?.toString() ?? '-';
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(left: 26, top: 4),
                                    child: Text(
                                      '${field.toUpperCase()}: $value',
                                      style: TextStyle(
                                        color: Colors.blue.shade900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      if (widget.primaryKeyFields != null &&
                          widget.primaryKeyFields!.isNotEmpty)
                        const SizedBox(height: 12),

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
                                  onAnswerChanged: () => _onAnswerChanged(),
                                  onRequestNext: () => _next(questions),
                                  isEditMode: widget.uniqueId != null,
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
    // Prevent multiple submissions
    if (_isSaving) return;

    // Get questions list for clearing skipped answers
    final questions = await _questions;

    // Clear answers for any questions that were skipped due to skip logic
    // This ensures data consistency (e.g., clearing pregnancy data if sex changed to male)
    _clearSkippedAnswers(questions);

    // --- NEW: Synchronous ID Generation ---
    if (widget.idConfig != null && widget.idConfig!.isNotEmpty) {
      // Validate that all required fields are present
      if (!IdGenerator.validateIdFields(
        idConfigJson: widget.idConfig!,
        answers: _answers,
      )) {
        // Get the list of missing fields to show in the error message
        final required = IdGenerator.getRequiredFields(widget.idConfig!);
        final missing = required.where((f) => _answers[f] == null || _answers[f].toString().isEmpty).toList();

        // Show an error dialog and stop
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Missing Information'),
            content: Text('Cannot generate Subject ID. Please go back and answer the following questions:\n\n- ${missing.join('\n- ')}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return; // Stop the save process
      }

      // Generate the ID
      final tableName = widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
      final generatedId = await IdGenerator.generateId(
        tableName: tableName,
        idConfigJson: widget.idConfig!,
        answers: _answers,
      );

      // Add the generated ID to the answers map for the correct field (subjid or hhid)
      // We find the field by looking for an automatic question that isn't in the registry
      final idHolderField = questions.firstWhere(
        (q) => q.type == QuestionType.automatic && !AutoFields.getRegistry().containsKey(q.fieldName),
        orElse: () => Question(fieldName: 'subjid', type: QuestionType.automatic, fieldType: 'text'), // fallback
      ).fieldName;

      _answers[idHolderField] = generatedId;
      debugPrint('Generated ID "$generatedId" for field "$idHolderField"');
    }
    // --- End of ID Generation ---

    // Check if there are any changes (for edit mode only)
    if (widget.uniqueId != null && !_hasChanges()) {
      // No changes made, show dialog and return
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('No Changes'),
          content: const Text('No changes were made to this record.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // Pop until we reach main screen (pop survey + record selector)
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    bool saveSuccessful = false;
    String? errorMessage;

    try {
      // Determine if we're updating or inserting
      if (widget.uniqueId != null) {
        // Update existing record
        await DbService.updateInterview(
          surveyFilename: widget.questionnaireFilename,
          answers: _answers,
          uniqueId: widget.uniqueId!,
          originalAnswers: _originalAnswers,
        );
      } else {
        // Insert new record
        await DbService.saveInterview(
          surveyFilename: widget.questionnaireFilename,
          answers: _answers,
        );
      }
      saveSuccessful = true;
    } catch (e) {
      // Capture the error to show in dialog
      errorMessage = e.toString();
      debugPrint('Save failed: $e');
    }

    if (!mounted) return;

    if (saveSuccessful) {
      // Success dialog - modal (barrierDismissible: false prevents tapping outside)
      final isUpdate = widget.uniqueId != null;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('All done!'),
          content: Text(isUpdate
              ? 'Thanks! Record updated successfully.'
              : 'Thanks! Answers saved successfully.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // Pop until we reach main screen
                if (isUpdate) {
                  // In edit mode: pop survey + record selector screens
                  Navigator.of(context).popUntil((route) => route.isFirst);
                } else {
                  // In new mode: just pop survey screen
                  Navigator.of(context).pop();
                }
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
                  // Pop until we reach main screen
                  if (widget.uniqueId != null) {
                    // In edit mode: pop survey + record selector screens
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    // In new mode: just pop survey screen
                    Navigator.of(context).pop();
                  }
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
