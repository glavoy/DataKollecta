import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../widgets/question_views.dart';
import '../services/answer_storage_service.dart';
import '../services/answer_validation_service.dart';
import '../services/child_increment_service.dart';
import '../services/duplicate_key_service.dart';
import '../services/db_service.dart';
import '../services/auto_fields.dart';
import '../services/automatic_field_service.dart';
import '../config/app_config.dart';
import '../services/logic_service.dart';
import '../services/survey_config_service.dart';
import '../services/survey_navigation_service.dart';
import '../services/csv_data_service.dart';
import '../services/change_summary_service.dart';
import '../services/app_strings.dart';
import '../services/repeat_count_service.dart';
import '../services/repeat_loop_runner.dart';
import '../services/repeat_plan_service.dart';

class SurveyScreen extends StatefulWidget {
  final String questionnaireFilename;
  final Map<String, dynamic>? existingAnswers;
  final String? uniqueId;
  final List<String>? primaryKeyFields;
  final Map<String, dynamic>? prepopulatedAnswers;
  final String? idConfig;
  final String? linkingField;
  final String?
      incrementField; // Field to auto-increment (e.g., 'linenum', 'netnum')
  final int? repeatIndex; // Current iteration (e.g., 2)
  final int? repeatTotal; // Total iterations (e.g., 5)
  final String?
      repeatEntityName; // Entity name for repeat surveys (e.g., "Member", "Structure", "Net")
  final String?
      repeatEntityNamePlural; // Plural form, for the count-mismatch warning (e.g., "Members")
  // repeat_enforce_count for this loop -- only set (and only relevant) inside
  // an auto-repeat child form, so the Cancel dialog can warn about the count
  // it's about to leave short, per mode.
  final int? repeatEnforceMode;
  final int?
      repeatCompletedSoFar; // Records already saved this loop, before this one

  const SurveyScreen({
    super.key,
    required this.questionnaireFilename,
    this.existingAnswers,
    this.uniqueId,
    this.primaryKeyFields,
    this.prepopulatedAnswers,
    this.idConfig,
    this.linkingField,
    this.incrementField,
    this.repeatIndex,
    this.repeatTotal,
    this.repeatEntityName,
    this.repeatEntityNamePlural,
    this.repeatEnforceMode,
    this.repeatCompletedSoFar,
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
  late final Future<List<Question>> _questions = _loadSurvey();
  List<Question>?
      _loadedQuestions; // Holds the questions after future completes
  bool _isSaving = false;
  String? _activeSurveyId;
  final CsvDataService _csvDataService = CsvDataService();
  static const AppStrings _s = AppStrings(AppConfig.isFrench);

  // Duplicate check variables
  DuplicateKeySnapshot _duplicateKeys = DuplicateKeySnapshot.empty;

  String? _logicError; // Holds the current logic check error message

  Future<List<Question>> _loadSurvey() async {
    try {
      // 1) init DB
      await DbService.init();

      // Get active survey ID
      final surveyConfig = SurveyConfigService();
      final surveyId = await surveyConfig.getActiveSurveyId();
      if (surveyId == null) {
        throw Exception('No active survey found');
      }
      _activeSurveyId = surveyId;

      // 2) load questions for UI from the survey XML
      // Get the asset path from the survey config service
      final assetPath = await surveyConfig
          .getQuestionnaireAssetPath(widget.questionnaireFilename);

      if (assetPath == null) {
        throw Exception(
            'No survey configured. Please configure settings first.');
      }

      final questions = await SurveyLoader.loadFromFile(File(assetPath));

      // 2b) Load CSV files for questions with CSV responses
      final surveyDirectory = p.dirname(assetPath);
      await _csvDataService.loadAllCsvFiles(surveyDirectory, questions);

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

      // 4b) Load existing primary keys for duplicate checking (New Record Mode only)
      if (widget.existingAnswers == null) {
        _duplicateKeys = await DuplicateKeySnapshot.load(
          surveyId: surveyId,
          tableName:
              widget.questionnaireFilename.toLowerCase().replaceAll('.xml', ''),
        );
      }

      // 5) Calculate linenum if needed (for new records only).
      //
      // The new-record gate stays here rather than inside the service: it is
      // about which screen the interviewer came through, not about counting,
      // and editing a record must never renumber it.
      if (widget.existingAnswers == null) {
        await ChildIncrementService.assign(
          questions: questions,
          answers: _answers,
          surveyId: surveyId,
          tableName:
              widget.questionnaireFilename.toLowerCase().replaceAll('.xml', ''),
          incrementField: widget.incrementField,
          fallbackLinkingField: widget.linkingField,
        );
      }

      return questions;
    } catch (e) {
      // If database initialization fails, still allow viewing the survey
      // but warn the user
      debugPrint('Warning: Database initialization failed: $e');
      debugPrint('Survey will load but data cannot be saved.');

      final surveyConfig = SurveyConfigService();
      final assetPath = await surveyConfig
          .getQuestionnaireAssetPath(widget.questionnaireFilename);

      if (assetPath == null) {
        throw Exception(
            'No survey configured. Please configure settings first.');
      }

      return SurveyLoader.loadFromFile(File(assetPath));
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

    // The baseline every later change is measured against.
    _originalAnswers = _snapshotAnswers(_answers);
  }

  /// A copy of [source] that later edits to `_answers` cannot reach through.
  ///
  /// Not a deep copy, despite what this was called: only a `List` is copied,
  /// because a checkbox answer is the one value a question view mutates in
  /// place. Everything else stored in an answer map is immutable -- `String`,
  /// `num`, `DateTime`, `null` -- so sharing the reference is safe and copying
  /// it would achieve nothing.
  AnswerMap _snapshotAnswers(AnswerMap source) {
    final copy = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      copy[entry.key] = value is List ? List.from(value) : value;
    }
    return copy;
  }

  /// Called whenever an answer changes
  void _onAnswerChanged(String fieldName, dynamic oldValue, dynamic newValue) {
    if (_loadedQuestions == null || !mounted) return;

    // Exact match, no change
    if (oldValue != null &&
        newValue != null &&
        oldValue.toString() == newValue.toString()) {
      return;
    }

    if (AnswerValidationService.isPaddingOnlyChange(oldValue, newValue)) {
      // Numeric equivalent, ignore as a change for cascade clearing
      debugPrint('[SurveyScreen] Ignoring padding-only change for $fieldName: '
          '"$oldValue" -> "$newValue"');
      // Still update logic checks for the current question
      setState(() {
        final q = _loadedQuestions![_currentQuestion];
        _logicError = LogicService.evaluateLogicChecks(q, _answers);
      });
      return;
    }

    _clearDependents(fieldName);

    setState(() {
      final q = _loadedQuestions![_currentQuestion];
      final validation = AnswerValidationService.evaluate(q, _answers, _s);
      _logicError = validation.message;

      // A half-typed fixed-length field or an unfinished decimal stops here,
      // and deliberately does not reach the duplicate check below -- that is
      // what the bare `return` inside this closure used to do. Running the
      // check on a partial key would be new behaviour, not a tidy-up.
      if (validation.stopsFurtherChecks) return;

      // Real-time duplicate check (New Record Mode only)
      if (_duplicateKeys.isKeyField(q.fieldName) && _isDuplicatePrimaryKey()) {
        _showDuplicateErrorDialog(q.fieldName);
        // Don't clear the answer, but set logic error to prevent proceeding
        _logicError = _s.duplicateRecordMessage;
      }
    });
  }

  /// This record's own `uniqueid`, to be carried into any child started from
  /// here, or null if it is somehow not set.
  ///
  /// Null should not happen -- every generated survey declares `uniqueid`, and
  /// `AutoFields` computes it before navigation reaches the end. Returning
  /// null rather than an empty string keeps the distinction visible at the
  /// call site instead of writing a blank join key.
  String? _parentUniqueIdForChildren() {
    final value =
        DuplicateKeySnapshot.answerFor(_answers, 'uniqueid')?.toString();
    if (value == null || value.isEmpty) {
      debugPrint('[SurveyScreen] No uniqueid on this record, so children '
          'started from here will have an empty '
          '${AutoFields.parentUniqueIdField}.');
      return null;
    }
    return value;
  }

  /// Whether the primary key now in `_answers` already exists in this table.
  ///
  /// The comparison lives in [DuplicateKeySnapshot]; what stays here is the
  /// edit-mode gate. In edit mode no snapshot is loaded at all, so this is
  /// belt and braces -- an existing record's own key would be in the snapshot,
  /// and checking it would always report a duplicate of itself.
  bool _isDuplicatePrimaryKey() {
    if (widget.existingAnswers != null) return false;
    return _duplicateKeys.isDuplicate(_answers);
  }

  void _showDuplicateErrorDialog(String fieldName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.duplicateRecord),
        content: Text(_s.duplicateRecordMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s.ok),
          ),
        ],
      ),
    );
  }

  /// Recursively clear any fields that depend on the changed field
  void _clearDependents(String fieldName) {
    if (_loadedQuestions == null) return;

    final clearedNow = <String>[];

    for (final q in _loadedQuestions!) {
      if (q.fieldName == fieldName) continue;

      if (q.dependsOn(fieldName)) {
        if (_answers[q.fieldName] != null) {
          debugPrint('Cascade clearing ${q.fieldName} (depends on $fieldName)');
          _answers[q.fieldName] = null;
          clearedNow.add(q.fieldName);
        }
      }
    }

    // Recursively clear dependents of the fields we just cleared
    for (final childField in clearedNow) {
      _clearDependents(childField);
    }
  }

  /// Navigate to the next question, auto-skipping automatic questions
  /// Information questions ARE displayed to the user
  Future<void> _next(List<Question> qs) async {
    if (_currentQuestion >= qs.length - 1) return;

    final currentQ = qs[_currentQuestion];

    // Perform uniqueness check if configured
    if (currentQ.uniqueCheck != null) {
      final value = _answers[currentQ.fieldName]?.toString();

      // Get the original value (if any) to see if it changed
      final originalValue = _originalAnswers?[currentQ.fieldName]?.toString();

      // Only check if value is present AND it is different from the original
      // If value == originalValue, it means the user hasn't changed it,
      // so it's valid (it's their own record).
      if (value != null && value.isNotEmpty && value != originalValue) {
        final tableName =
            widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

        final surveyId = await SurveyConfigService().getActiveSurveyId();
        if (surveyId != null) {
          bool isUnique = await DbService.isValueUnique(
              surveyId, tableName, currentQ.fieldName, value);

          if (!isUnique) {
            setState(() {
              _logicError =
                  currentQ.uniqueCheck!.message ?? _s.valueAlreadyExists;
            });
            return;
          }
        }
      }
    }

    // Push current displayed question to history (skip automatic)
    if (qs[_currentQuestion].type != QuestionType.automatic) {
      _history.add(_currentQuestion);
      // history keeps track of previous questions implicitly
    }

    final nextIndex = await SurveyNavigationService.advanceFromQuestion(
      questions: qs,
      currentIndex: _currentQuestion,
      answers: _answers,
      processAutomaticQuestion: _processAutomaticQuestion,
      primaryKeyFields: widget.primaryKeyFields ?? const [],
      isEditMode: widget.uniqueId != null,
    );

    setState(() {
      _currentQuestion = nextIndex;
      _logicError = null; // Clear error on navigation

      // Re-evaluate logic checks for the new question
      // This ensures that if user went back and changed a dependent field,
      // the logic check runs again (e.g., hhid_verif after hhid changed)
      if (nextIndex < qs.length) {
        final nextQuestion = qs[nextIndex];
        _logicError = LogicService.evaluateLogicChecks(nextQuestion, _answers);
      }
    });
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

  /// Navigate to the previous displayed question
  void _prev() {
    if (_history.isEmpty) return;

    setState(() {
      _currentQuestion = _history.removeLast();
      _logicError = null; // Clear error on navigation

      // Re-evaluate logic checks for the question we're returning to
      if (_loadedQuestions != null &&
          _currentQuestion < _loadedQuestions!.length) {
        final question = _loadedQuestions![_currentQuestion];
        _logicError = LogicService.evaluateLogicChecks(question, _answers);
      }
    });
  }

  // Previous question lookup is handled by _history
  /// Process an automatic question by calculating its value
  Future<void> _processAutomaticQuestion(Question q) async {
    // The body moved to AutomaticFieldService so it can run without a widget
    // tree. The call site did not move: an automatic question is computed when
    // navigation *reaches* it, so `starttime` records the moment it was
    // crossed, and this stays the AutomaticQuestionProcessor that
    // SurveyNavigationService invokes.
    await AutomaticFieldService.compute(
      question: q,
      answers: _answers,
      surveyId:
          _activeSurveyId ?? await SurveyConfigService().getActiveSurveyId(),
      tableName:
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', ''),
      idConfig: widget.idConfig,
      linkingField: widget.linkingField,
      incrementField: widget.incrementField,
      isEditMode: widget.uniqueId != null,
    );

    // The duplicate check has to run here, not only in _onAnswerChanged.
    // That method fires for the question the interviewer is *on*, so a
    // primary key built entirely from `automatic` fields -- which is exactly
    // what PRISM CSS's `(hhid, linenum)` is -- never rendered and never
    // triggered it. Now the check runs where the key is computed.
    //
    // Telling the interviewer here, while `hhnum` can still be corrected, is
    // the whole point: hh_info declares `incrementLength: 0`, so `hhid` is a
    // pure function of typed answers with no spare digit to move. There is no
    // degraded value available for a duplicate household -- only prevention
    // at entry, with the UNIQUE constraint as the visible backstop.
    if (_duplicateKeys.isKeyField(q.fieldName) && _isDuplicatePrimaryKey()) {
      if (!mounted) return;
      setState(() {
        _logicError = _s.duplicateRecordMessage;
      });
      _showDuplicateErrorDialog(q.fieldName);
    }
  }

  /// Skip to the first question that should be displayed
  Future<void> _skipToFirstDisplayedQuestion(List<Question> questions) async {
    final index = await SurveyNavigationService.findNextDisplayedQuestion(
      questions: questions,
      startIndex: 0,
      answers: _answers,
      processAutomaticQuestion: _processAutomaticQuestion,
      primaryKeyFields: widget.primaryKeyFields ?? const [],
      isEditMode: widget.uniqueId != null,
    );

    if (index < questions.length && index != _currentQuestion) {
      setState(() {
        _currentQuestion = index;
      });
    }

    // Initial validation check
    if (mounted && index < questions.length) {
      setState(() {
        _logicError =
            LogicService.evaluateLogicChecks(questions[index], _answers);
      });
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
          return Scaffold(
              body: Center(child: Text('${_s.error}: ${snap.error}')));
        }

        final questions = snap.data!;
        _loadedQuestions =
            questions; // Keep a reference to the loaded questions

        // Skip automatic and information questions on initial load
        if (_currentQuestion == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await _skipToFirstDisplayedQuestion(questions);
          });
        }

        final q = questions[_currentQuestion];

        // Track that this question was displayed/visited
        // Skip tracking automatic questions as they're never displayed
        if (q.type != QuestionType.automatic) {
          _visitedFields.add(q.fieldName);
        }

        final isFirst = _history.isEmpty;
        // The gate itself lives in AnswerValidationService, so the survey
        // testing harness walks the form under the same rule rather than a
        // copy of it. `_logicError` is still read from state rather than
        // recomputed: it also carries the unique-check and duplicate-key
        // messages, which are not decidable from the answer map alone.
        final canProceed = (q.type == QuestionType.information ||
                (AnswerValidationService.isAnswered(q, _answers) &&
                    AnswerValidationService.isValid(q, _answers))) &&
            _logicError == null;
        final isLast = _currentQuestion == questions.length - 1 ||
            !_hasNextDisplayedQuestion(questions, _currentQuestion);
        // final progress = (_currentQuestion + 1) / questions.length;

        return Scaffold(
          backgroundColor: widget.uniqueId != null
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.blueGrey.shade800
                  : Colors.blueGrey.shade50)
              : null,
          appBar: AppBar(
            backgroundColor: widget.uniqueId != null
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.blueGrey.shade800
                    : Colors.blueGrey.shade50)
                : null,
            toolbarHeight: 60,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: _s.cancelInterview,
              onPressed: () {
                final (cancelTitle, cancelMessage) = _cancelDialogContent();
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(cancelTitle),
                    content: Text(cancelMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_s.no),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                          Navigator.of(context)
                              .pop(false); // Return false to indicate cancelled
                        },
                        child: Text(_s.yes),
                      ),
                    ],
                  ),
                );
              },
            ),
            title: (widget.repeatIndex != null && widget.repeatTotal != null) ||
                    (widget.primaryKeyFields != null &&
                        widget.primaryKeyFields!.isNotEmpty)
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade700
                          : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.repeatIndex != null && widget.repeatTotal != null
                          ? '${widget.repeatEntityName ?? "Member"} ${widget.repeatIndex} of ${widget.repeatTotal}'
                          : widget.primaryKeyFields != null &&
                                  widget.primaryKeyFields!.isNotEmpty
                              ? 'Viewing: ${widget.primaryKeyFields!.map((field) => '${field.toUpperCase()}: ${_answers[field]?.toString() ?? '-'}').join(', ')}'
                              : '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.blue.shade900,
                      ),
                    ),
                  )
                : null,
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
                      // Question text (fixed at top)
                      if ((q.text ?? '').isNotEmpty &&
                          q.type != QuestionType.information)
                        Builder(builder: (context) {
                          final expandedText = SurveyLoader.expandPlaceholders(
                              q.text!, _answers);
                          final isWarning =
                              SurveyLoader.isWarning(expandedText);

                          if (isWarning) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.amber.shade900
                                        .withValues(alpha: 0.2)
                                    : Colors.amber.shade50,
                                border: Border.all(
                                    color: Colors.amber.shade400, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade900,
                                      size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      expandedText,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.amber.shade100
                                            : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              expandedText,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          );
                        }),

                      // Error display (fixed below question text) - shows only ONE error at a time
                      if (_logicError != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _logicError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Response area (scrollable)
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.topCenter,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          child: Align(
                            key: ValueKey(q.fieldName),
                            alignment: Alignment.topCenter,
                            child: Card(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: QuestionView(
                                    key: ValueKey('view_${q.fieldName}'),
                                    question: q,
                                    answers: _answers,
                                    onAnswerChanged:
                                        (fieldName, oldVal, newVal) =>
                                            _onAnswerChanged(
                                                fieldName, oldVal, newVal),
                                    isEditMode: widget.uniqueId != null,
                                    csvDataService: _csvDataService,
                                    surveyId: _activeSurveyId ?? '',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 56),

                      // Nav bar
                      Row(
                        children: [
                          if (!isFirst)
                            OutlinedButton.icon(
                              onPressed: _prev,
                              icon: const Icon(Icons.arrow_back),
                              label: Text(_s.previous),
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
                              // Disabled while a save is in flight. Without
                              // this the button stays live and gives no sign
                              // anything is happening, which is what prompted
                              // interviewers to press it again.
                              onPressed: (canProceed && !_isSaving)
                                  ? () => isLast
                                      ? _showDone(context)
                                      : _next(questions)
                                  : null,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(isLast
                                      ? Icons.check
                                      : Icons.arrow_forward),
                              label: Text(isLast ? _s.finish : _s.next),
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
    // Claim the save synchronously, before the first await.
    //
    // Everything below this point suspends at least once, and the Finish button
    // stays mounted while it does. Checking the flag here but setting it after
    // an await leaves a window in which a second tap passes the check and
    // inserts a second record: five copies of one interview reached the field
    // that way, identical but for their save timestamp.
    //
    // The invariant: the flag is released on every path that does not insert a
    // record, and stays set once one exists. That second half also stops a
    // record being saved twice by going back, editing an answer and pressing
    // Finish again — which is still an insert, not an update.
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    // Get questions list for clearing skipped answers
    final questions = await _questions;
    if (!context.mounted) return;

    // Clear answers for any questions that were skipped due to skip logic
    // This ensures data consistency (e.g., clearing pregnancy data if sex changed to male)
    AnswerStorageService.clearSkippedAnswers(
      answers: _answers,
      questions: questions,
      visitedFields: _visitedFields,
      primaryKeyFields: widget.primaryKeyFields,
    );

    // Note: Primary key ID (hhid/subjid) is now generated in real-time
    // when the automatic question is processed, not here at save time

    // Check if there are any changes (for edit mode only)
    if (widget.uniqueId != null) {
      if (!AnswerStorageService.hasChanges(_answers, _originalAnswers)) {
        // No changes made, show dialog and return
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(_s.noChanges),
            content: Text(_s.noChangesMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  // Pop until we reach main screen (pop survey + record selector)
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Text(_s.ok),
              )
            ],
          ),
        );
        setState(() {
          _isSaving = false;
        });
        return;
      }

      // Show review summary before saving
      final summary = await ChangeSummaryService.getSummary(
        originalAnswers: _originalAnswers!,
        currentAnswers: _answers,
        questions: questions,
        csvService: _csvDataService,
        surveyId: _activeSurveyId ?? '',
      );

      if (summary.isNotEmpty) {
        if (!context.mounted) return;
        final result = await _showReviewChangesDialog(context, summary);
        if (result == 'discard') {
          // Exit without saving
          if (context.mounted) {
            setState(() {
              _isSaving = false;
            });
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        } else if (result != 'save') {
          // 'back' or null (dialog dismissed/canceled). The user stays on this
          // screen, so release the guard or Finish is dead for good.
          if (context.mounted) {
            setState(() {
              _isSaving = false;
            });
          }
          return;
        }
      }
    }

    // Update lastmod timestamp only when actually saving
    AutoFields.touchLastMod(_answers);

    final answersToSave =
        AnswerStorageService.coerceForStorage(_answers, _loadedQuestions);

    bool saveSuccessful = false;
    String? errorMessage;

    try {
      final surveyId = await SurveyConfigService().getActiveSurveyId();
      if (surveyId == null) throw Exception('No active survey found');

      // Determine if we're updating or inserting
      if (widget.uniqueId != null) {
        // Update existing record
        await DbService.updateInterview(
          surveyId: surveyId,
          surveyFilename: widget.questionnaireFilename,
          answers: answersToSave,
          uniqueId: widget.uniqueId!,
          originalAnswers: _originalAnswers,
        );
      } else {
        // Insert new record
        await DbService.saveInterview(
          surveyId: surveyId,
          surveyFilename: widget.questionnaireFilename,
          answers: answersToSave,
        );
      }
      saveSuccessful = true;
    } catch (e) {
      // Capture the error to show in dialog
      errorMessage = e.toString();
      debugPrint('Save failed: $e');
    }

    if (!context.mounted) return;

    // The guard is released only when the save failed, so the user can retry.
    // On success it stays set: the record is in the database, and the success
    // dialog is about to pop this screen. Clearing it here would leave the
    // Finish button live on a screen whose record has already been inserted.
    if (saveSuccessful) {
      // A child record saved outside the auto-repeat loop -- one added later
      // from the questionnaire menu, or edited -- still changes how many
      // children the parent has, so the parent's count is reconciled here too.
      // Inside the loop the reconciliation happens once at the end instead.
      if (widget.repeatIndex == null) {
        await _reconcileCountOnParentOfThisForm(context);
        if (!context.mounted) return;
      }

      // Check if we should start auto-repeat for child surveys (only for new records, not modifications)
      if (widget.uniqueId == null) {
        await _checkAndStartAutoRepeat(context);
      } else {
        // Modifying an existing record - just show success and close
        _showSaveSuccessDialog(context);
      }
    } else {
      // Error dialog
      _showSaveErrorDialog(context, errorMessage);
    }
  }

  /// Reconcile the count on this form's parent, if this form is a counted
  /// repeating child.
  ///
  /// The auto-repeat loop only runs when a parent is saved, so without this a
  /// household member added weeks later would never be counted -- the parent
  /// would keep the number declared at enrolment forever.
  Future<void> _reconcileCountOnParentOfThisForm(BuildContext context) async {
    try {
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      final surveyId = await SurveyConfigService().getActiveSurveyId();
      if (surveyId == null) return;

      final crf = await DbService.getCrfConfig(surveyId, tableName);
      final linkingField = crf?['linkingfield']?.toString();
      if (linkingField == null || linkingField.isEmpty) return;

      final linkingValue = _answers[linkingField]?.toString();
      if (linkingValue == null || linkingValue.isEmpty) return;

      if (!context.mounted) return;
      await _reconcileRepeatCount(context, tableName, linkingValue);
    } catch (e) {
      debugPrint('Error reconciling parent count: $e');
    }
  }

  /// Check if any child surveys should auto-repeat after this survey completes
  Future<void> _checkAndStartAutoRepeat(BuildContext context) async {
    try {
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      final surveyId = await SurveyConfigService().getActiveSurveyId();
      if (surveyId == null) return;

      // Get all CRF records to find child surveys
      final allCrfs = await DbService.getExistingRecords(surveyId, 'crfs');
      if (!context.mounted) return;

      final repeats = RepeatPlanService.plan(
        crfs: allCrfs,
        parentTableName: tableName,
        answers: _answers,
      );

      for (final item in repeats) {
        // Re-checked per iteration, not just once above: the prompt and the
        // repeat loop below both await, so a later pass can resume after the
        // user has already left this screen.
        if (!context.mounted) return;

        if (item.autoStartRepeat == 1) {
          // Prompt mode
          final shouldStart = await _promptStartRepeatSurveys(
            context,
            item.childTableName,
            item.displayName,
            item.repeatCount,
          );

          if (shouldStart != true) {
            // User declined to start this repeat section - skip to next
            continue;
          }
          if (!context.mounted) return;
        }

        // Prompt mode with a yes, or force mode. Either way, run the loop --
        // and do not return, so later repeating sections are still offered.
        await _startRepeatSurveyLoop(
          context,
          item.childTableName,
          item.displayName,
          item.repeatCount,
          item.linkingField,
          item.linkingValue,
          item.crf,
        );
      }

      // No auto-repeat configured, show success dialog
      if (!context.mounted) return;
      _showSaveSuccessDialog(context);
    } catch (e) {
      debugPrint('Error checking auto-repeat: $e');
      if (!context.mounted) return;
      _showSaveSuccessDialog(context);
    }
  }

  /// Prompt user to start repeat surveys
  Future<bool?> _promptStartRepeatSurveys(
    BuildContext context,
    String childTableName,
    String displayName,
    int count,
  ) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.addEntityNow(displayName)),
        content: Text(_s.addEntityMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_s.addLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_s.addNow),
          ),
        ],
      ),
    );
  }

  /// Start the repeat survey loop
  Future<void> _startRepeatSurveyLoop(
    BuildContext context,
    String childTableName,
    String displayName,
    int repeatCount,
    String linkingField,
    String linkingValue,
    Map<String, dynamic> crfConfig,
  ) async {
    final enforceCountMode = RepeatCountService.parseEnforceMode(
      crfConfig['repeat_enforce_count'],
    );

    // "Household members" -> "Household member"
    var entityName = displayName;
    if (entityName.endsWith('s')) {
      entityName = entityName.substring(0, entityName.length - 1);
    }

    // The loop itself lives in RepeatLoopRunner so its decisions -- which
    // enforce mode retries, which lets the interviewer leave -- can be tested
    // without tapping through a survey. What stays here is the four things
    // that need a widget: the push, the two dialogs, and the mounted check.
    final outcome = await const RepeatLoopRunner().run(
      requested: repeatCount,
      enforceMode: enforceCountMode,
      shouldContinue: () => mounted,
      openChild: (index, completed) async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => SurveyScreen(
              questionnaireFilename: '$childTableName.xml',
              // This loop runs inside the parent's own screen, so `_answers`
              // still holds the parent's record -- its `uniqueid` is the
              // immutable join key the child carries alongside the linking
              // value. Unlike the parent-ID selector, nothing has to be
              // looked up for it.
              prepopulatedAnswers: {
                linkingField: linkingValue,
                if (_parentUniqueIdForChildren() != null)
                  AutoFields.parentUniqueIdField: _parentUniqueIdForChildren()!,
              },
              incrementField: crfConfig['incrementfield']?.toString(),
              repeatIndex: index,
              repeatTotal: repeatCount,
              repeatEntityName: entityName,
              repeatEntityNamePlural: displayName,
              repeatEnforceMode: enforceCountMode,
              repeatCompletedSoFar: completed,
            ),
          ),
        );
        return result == true;
      },
      insist: (index, completed) async {
        if (!context.mounted) return;
        await _showMustCompleteDialogWithEntity(
          context,
          repeatCount,
          index,
          entityName,
          allowExit: false, // Force mode: user cannot exit
        );
      },
      isBelowMinimum: () =>
          _isBelowDeclaredMinimum(childTableName, linkingValue, entityName),
      // _isBelowDeclaredMinimum shows its own dialog before returning true, so
      // there is nothing further to say here.
      warnBelowMinimum: (index, completed) async {},
      reconcile: () async {
        if (!context.mounted) return;
        await _reconcileRepeatCount(context, childTableName, linkingValue);
      },
    );

    debugPrint(
      'Repeat loop for $childTableName finished: '
      '${outcome.completed} of ${outcome.requested} entered '
      '(enforce mode $enforceCountMode)',
    );
  }

  /// Show dialog when user must complete all entities
  /// When enforceCountMode is 2 (Force), user cannot exit
  Future<bool> _showMustCompleteDialogWithEntity(
      BuildContext context, int total, int current, String entityName,
      {bool allowExit = true}) async {
    final entityNamePlural =
        entityName.endsWith('s') ? entityName : '${entityName}s';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.mustCompleteAll(entityNamePlural)),
        content: Text(_s.mustCompleteMessage(
            total, entityNamePlural, entityName, current)),
        actions: [
          if (allowExit)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(_s.exitAnyway),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_s.continueLabel),
          ),
        ],
      ),
    );

    return result ?? true;
  }

  /// True when fewer child records exist than the count question's declared
  /// `LowerRange` allows -- and, when so, tells the interviewer they have to
  /// keep going.
  ///
  /// This is the same range check that gates the interviewer's own typed
  /// answer, so the loop can never be abandoned in a state that would force an
  /// impossible count onto the parent record.
  Future<bool> _isBelowDeclaredMinimum(
    String childTableName,
    String linkingValue,
    String entityName,
  ) async {
    final surveyId = await SurveyConfigService().getActiveSurveyId();
    if (surveyId == null) return false;

    final reconciliation = await RepeatCountService.evaluate(
      surveyId: surveyId,
      childTableName: childTableName,
      linkingValue: linkingValue,
    );
    if (reconciliation == null ||
        reconciliation.outcome != RepeatCountOutcome.belowMinimum) {
      return false;
    }

    if (!mounted) return true;

    final minimum = reconciliation.minimum!.toInt();
    final entityNamePlural =
        entityName.endsWith('s') ? entityName : '${entityName}s';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(_s.mustEnterAtLeast(minimum, entityNamePlural)),
        content: Text(_s.mustEnterAtLeastMessage(
            minimum, entityNamePlural, reconciliation.actualCount)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_s.continueLabel),
          ),
        ],
      ),
    );

    return true;
  }

  /// Reconcile the parent's repeat count with the children actually entered.
  ///
  /// Delegates the decision to [RepeatCountService] so that the auto-repeat
  /// loop and an ad-hoc child added later from the questionnaire menu apply
  /// exactly the same rules; this method only supplies the dialogs.
  Future<bool> _reconcileRepeatCount(
    BuildContext context,
    String childTableName,
    String linkingValue,
  ) async {
    final surveyId = await SurveyConfigService().getActiveSurveyId();
    if (surveyId == null) return false;

    final reconciliation = await RepeatCountService.evaluate(
      surveyId: surveyId,
      childTableName: childTableName,
      linkingValue: linkingValue,
    );
    if (reconciliation == null) return true;

    switch (reconciliation.outcome) {
      case RepeatCountOutcome.updateSilently:
        await RepeatCountService.applyCount(
          surveyId: surveyId,
          reconciliation: reconciliation,
        );
        debugPrint('Auto-synced ${reconciliation.parentTable}.'
            '${reconciliation.countField} to ${reconciliation.actualCount}');
        if (!context.mounted) return true;
        // The count is already written by the time this shows -- unlike
        // _showCountMismatchDialog, there is nothing left to decide, so a
        // single acknowledgement button is the only action offered.
        await _showCountAutoUpdatedDialog(
          context,
          reconciliation.displayName,
          reconciliation.declaredCount ?? 0,
          reconciliation.actualCount,
        );
        return true;

      case RepeatCountOutcome.askToUpdate:
        if (!context.mounted) return true;
        final action = await _showCountMismatchDialog(
          context,
          reconciliation.displayName,
          reconciliation.declaredCount ?? 0,
          reconciliation.actualCount,
        );
        if (action == 'update') {
          await RepeatCountService.applyCount(
            surveyId: surveyId,
            reconciliation: reconciliation,
          );
        }
        return true;

      case RepeatCountOutcome.aboveMaximum:
        if (!context.mounted) return true;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(_s.incompleteData),
            content: Text(_s.countExceedsMaximum(
              reconciliation.actualCount,
              reconciliation.displayName,
              reconciliation.maximum!.toInt(),
            )),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_s.ok),
              ),
            ],
          ),
        );
        return false;

      case RepeatCountOutcome.belowMinimum:
      case RepeatCountOutcome.countNotDeclared:
      case RepeatCountOutcome.forceModeHandledInLoop:
      case RepeatCountOutcome.noEnforcement:
      case RepeatCountOutcome.inSync:
        debugPrint('Repeat count for ${reconciliation.childTable} left as is: '
            '${reconciliation.outcome}');
        return true;
    }
  }

  /// Show count mismatch warning dialog
  Future<String?> _showCountMismatchDialog(
    BuildContext context,
    String displayName,
    int expected,
    int actual,
  ) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.incompleteData),
        content: Text(_s.incompleteDataMessage(expected, displayName, actual)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'force'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_s.exitAnywayWarning),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(_s.updateCountTo(actual)),
          ),
        ],
      ),
    );
  }

  /// Title and message for the AppBar's Cancel/X dialog.
  ///
  /// Outside a repeat loop this is the plain "Cancel Interview" warning.
  /// Inside one, confirming only discards *this* record -- the parent and
  /// any records already saved this loop stay -- so the generic
  /// "everything will be lost" wording is actively misleading there, and is
  /// replaced with record-scoped wording. When stopping now would also
  /// leave the parent's declared count short (modes 1 and 3 only -- mode 2
  /// cannot reach this dialog with a shortfall, since the loop forces
  /// completion), the consequence is appended so the interviewer sees it
  /// before confirming, not as a surprise afterward.
  (String, String) _cancelDialogContent() {
    if (widget.repeatIndex == null) {
      return (_s.cancelInterview, _s.cancelInterviewMessage);
    }

    final entityName = widget.repeatEntityName ?? _s.repeatEntityFallback;
    final title = _s.skipRepeatRecordTitle(entityName);
    var message = _s.skipRepeatRecordMessage;

    final mode = widget.repeatEnforceMode;
    final completed = widget.repeatCompletedSoFar;
    final declared = widget.repeatTotal;
    if ((mode == 1 || mode == 3) &&
        completed != null &&
        declared != null &&
        completed < declared) {
      message += '\n\n${_s.skipRepeatRecordCountWarning(
        completed,
        declared,
        widget.repeatEntityNamePlural ?? entityName,
        willAskFirst: mode == 1,
      )}';
    }

    return (title, message);
  }

  /// Show an acknowledgement-only dialog after `repeat_enforce_count = 3`
  /// has already auto-corrected a mismatched count. Unlike
  /// [_showCountMismatchDialog], there is no choice to make here -- the
  /// write already happened -- so this exists purely so the interviewer
  /// isn't left wondering why the count on screen changed.
  Future<void> _showCountAutoUpdatedDialog(
    BuildContext context,
    String displayName,
    int expected,
    int actual,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.countAutoUpdated),
        content:
            Text(_s.countAutoUpdatedMessage(expected, displayName, actual)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s.ok),
          ),
        ],
      ),
    );
  }

  /// Show save success dialog
  void _showSaveSuccessDialog(BuildContext context) {
    final isUpdate = widget.uniqueId != null;

    // Check if we're in a repeat loop by seeing if we have prepopulated answers (indicates child survey)
    final isInRepeatLoop = widget.prepopulatedAnswers != null && !isUpdate;

    if (isInRepeatLoop) {
      // In repeat loop - just return true to continue to next iteration
      Navigator.of(context).pop(true);
    } else {
      // Normal flow - show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(_s.allDone),
          content:
              Text(isUpdate ? _s.recordUpdatedSuccess : _s.answersSavedSuccess),
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
              child: Text(_s.ok),
            )
          ],
        ),
      );
    }
  }

  /// Show save error dialog
  void _showSaveErrorDialog(BuildContext context, String? errorMessage) {
    if (AppConfig.enableErrorDialogs) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              Text(_s.saveFailed),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.saveFailedMessage,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(_s.errorDetails),
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
                Text(
                  _s.saveFailedChecklist,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                setState(() {
                  _isSaving = false;
                });
              },
              child: Text(_s.close),
            ),
          ],
        ),
      );
    }
  }

  /// Show review changes dialog for edit mode
  Future<String?> _showReviewChangesDialog(
      BuildContext context, List<ChangeSummaryItem> summary) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.rate_review_outlined, color: Colors.blue),
            const SizedBox(width: 8),
            Text(_s.reviewChanges),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: summary.isEmpty
              ? Text(_s.noChangesDetected)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: summary.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = summary[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.questionText,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.oldLabel,
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ),
                            const Icon(Icons.arrow_forward,
                                size: 14, color: Colors.grey),
                            Expanded(
                              child: Text(
                                item.newLabel,
                                style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(_s.discardChangesTitle),
                        content: Text(_s.discardChangesMessage),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(_s.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(_s.discardAndExit,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    // `context` here is this dialog's own builder
                    // context, and the nested confirm above awaited --
                    // the review dialog can already be gone.
                    if (confirm == true && context.mounted) {
                      Navigator.pop(context, 'discard');
                    }
                  },
                  child: Text(_s.discardAndExit,
                      style: const TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'back'),
                  child: Text(_s.backToEdit),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'save'),
                  child: Text(_s.saveChanges),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
