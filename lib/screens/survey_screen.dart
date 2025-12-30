import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../widgets/question_views.dart';
import '../services/db_service.dart';
import '../services/auto_fields.dart';
import '../services/skip_service.dart';
import '../config/app_config.dart';
import '../services/id_generator.dart';
import '../services/logic_service.dart';
import '../services/survey_config_service.dart';
import '../services/csv_data_service.dart';
import '../services/change_summary_service.dart';

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
  List<Question>?
      _loadedQuestions; // Holds the questions after future completes
  bool _isSaving = false; // Flag to prevent multiple submissions
  String? _activeSurveyId;
  final CsvDataService _csvDataService = CsvDataService();

  // Duplicate check variables
  Set<String> _existingPrimaryKeys = {};
  List<String> _pkFields = [];

  @override
  void initState() {
    super.initState();
  }

  String? _logicError; // Holds the current logic check error message

  @override
  void dispose() {
    super.dispose();
  }

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
        final surveyId = await SurveyConfigService().getActiveSurveyId();
        if (surveyId != null) {
          final tableName =
              widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
          _pkFields = await DbService.getPrimaryKeyFields(surveyId, tableName);

          if (_pkFields.isNotEmpty) {
            final allKeys = await DbService.getAllPrimaryKeys(
                surveyId, tableName, _pkFields);

            _existingPrimaryKeys = allKeys.map((row) {
              return _pkFields.map((f) => row[f]?.toString() ?? '').join('|');
            }).toSet();

            debugPrint(
                'Loaded ${_existingPrimaryKeys.length} existing primary keys for duplicate check');
          }
        }
      }

      // 4b) Load existing primary keys for duplicate checking (New Record Mode only)
      if (widget.existingAnswers == null) {
        final surveyId = await SurveyConfigService().getActiveSurveyId();
        if (surveyId != null) {
          final tableName =
              widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
          _pkFields = await DbService.getPrimaryKeyFields(surveyId, tableName);

          if (_pkFields.isNotEmpty) {
            final allKeys = await DbService.getAllPrimaryKeys(
                surveyId, tableName, _pkFields);

            _existingPrimaryKeys = allKeys.map((row) {
              return _pkFields.map((f) => row[f]?.toString() ?? '').join('|');
            }).toSet();

            debugPrint(
                'Loaded ${_existingPrimaryKeys.length} existing primary keys for duplicate check');
          }
        }
      }

      // 5) Calculate linenum if needed (for new records only)
      if (widget.existingAnswers == null) {
        await _calculateLineNum(questions);
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

  /// Calculate auto-increment field for the current record based on primary key
  Future<void> _calculateLineNum(List<Question> questions) async {
    try {
      // Check if an increment field is configured
      if (widget.incrementField == null || widget.incrementField!.isEmpty) {
        return; // No increment field configured
      }

      final incrementFieldName = widget.incrementField!;

      // Check if this survey has the configured increment field
      final hasIncrementField =
          questions.any((q) => q.fieldName == incrementFieldName);
      if (!hasIncrementField) {
        return; // Configured increment field doesn't exist in this survey
      }

      // Get the table name
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      // Get the primary key fields from the CRFs table
      final surveyId = await SurveyConfigService().getActiveSurveyId();
      if (surveyId == null) return;

      final primaryKeyFields =
          await DbService.getPrimaryKeyFields(surveyId, tableName);

      if (primaryKeyFields.isEmpty) {
        debugPrint(
            'No primary key fields found for $tableName, defaulting $incrementFieldName to 1');
        _answers[incrementFieldName] = '1';
        return;
      }

      // The first field in the primary key is the base field (e.g., hhid)
      final primaryKeyField = primaryKeyFields.first;

      // Get the value of the primary key field from answers
      final primaryKeyValue = _answers[primaryKeyField];

      if (primaryKeyValue == null || primaryKeyValue.toString().isEmpty) {
        debugPrint(
            'Primary key field $primaryKeyField not set, defaulting $incrementFieldName to 1');
        _answers[incrementFieldName] = '1';
        return;
      }

      // Query the database for the next increment value
      final nextValue = await DbService.getNextIncrementValue(
        surveyId: surveyId,
        tableName: tableName,
        incrementField: incrementFieldName,
        primaryKeyField: primaryKeyField,
        primaryKeyValue: primaryKeyValue.toString(),
      );

      _answers[incrementFieldName] = nextValue.toString();
      debugPrint(
          'Calculated $incrementFieldName=$nextValue for $primaryKeyField=${primaryKeyValue.toString()}');
    } catch (e) {
      if (widget.incrementField != null && widget.incrementField!.isNotEmpty) {
        debugPrint('Error calculating ${widget.incrementField}: $e');
        _answers[widget.incrementField!] = '1'; // Default to 1 on error
      }
    }
  }

  /// Check if answers have been modified compared to original
  bool _hasChanges() {
    if (_originalAnswers == null) return true; // New record, always has changes

    // Compare each answer
    for (final key in _answers.keys) {
      // Ignore automatic fields that auto-update
      if (key == 'lastmod' || key == 'swver' || key == 'survey_id') continue;

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
        if (newValue.toString() != oldValue.toString()) {
          final s1 = newValue.toString();
          final s2 = oldValue.toString();

          // Check if they are numeric equivalent (e.g. "04" vs "4")
          final n1 = num.tryParse(s1);
          final n2 = num.tryParse(s2);
          if (n1 != null && n2 != null && n1 == n2) {
            continue;
          }

          // Check if they are DateTime equivalent (e.g. "2025-12-09 11:22" vs "2025-12-09T11:22")
          try {
            final d1 = DateTime.tryParse(s1);
            final d2 = DateTime.tryParse(s2);
            if (d1 != null && d2 != null && d1.isAtSameMomentAs(d2)) {
              continue; // Same moment in time
            }
          } catch (_) {}

          return true;
        }
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

  /// Called whenever an answer changes
  void _onAnswerChanged(String fieldName, dynamic oldValue, dynamic newValue) {
    if (_loadedQuestions == null || !mounted) return;

    // Check if it's a "logical" change (numeric-aware)
    if (oldValue != null && newValue != null) {
      final s1 = oldValue.toString();
      final s2 = newValue.toString();
      if (s1 == s2) return; // Exact match, no change

      final n1 = num.tryParse(s1);
      final n2 = num.tryParse(s2);
      if (n1 != null && n2 != null && n1 == n2) {
        // Numeric equivalent, ignore as a change for cascade clearing
        debugPrint(
            '[SurveyScreen] Ignoring padding-only change for $fieldName: "$s1" -> "$s2"');
        // Still update logic checks for the current question
        setState(() {
          final q = _loadedQuestions![_currentQuestion];
          _logicError = LogicService.evaluateLogicChecks(q, _answers);
        });
        return;
      }
    }

    _clearDependents(fieldName);

    setState(() {
      final q = _loadedQuestions![_currentQuestion];
      _logicError = LogicService.evaluateLogicChecks(q, _answers);

      // Perform numeric check validation
      if (q.type == QuestionType.text) {
        final raw = _answers[q.fieldName]?.toString() ?? '';

        // Strict length check (if configured with <maxCharacters>=N)
        if (q.fixedLength && q.maxCharacters != null) {
          if (raw.length != q.maxCharacters) {
            // Incomplete input: keep Next disabled, but HIDE error message
            _logicError = null;
            return; // Skip further validation until length is met
          }
        }

        if (_logicError == null && q.numericCheck != null && raw.isNotEmpty) {
          final parsed = num.tryParse(raw);
          if (parsed != null) {
            final nc = q.numericCheck!;
            final exceptions = (nc.otherValues ?? '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toSet();

            if (!exceptions.contains(parsed.toString())) {
              if ((nc.minValue != null && parsed < nc.minValue!) ||
                  (nc.maxValue != null && parsed > nc.maxValue!)) {
                _logicError = nc.message ??
                    'Value must be between ${nc.minValue} and ${nc.maxValue}';
              }
            }
          }
        }
      }

      // Real-time duplicate check (New Record Mode only)
      if (widget.existingAnswers == null &&
          _pkFields.contains(q.fieldName.toLowerCase())) {
        // Check if all PK fields have values
        bool allPkPresent = true;
        for (final pkField in _pkFields) {
          if (_answers[pkField] == null ||
              _answers[pkField].toString().isEmpty) {
            allPkPresent = false;
            break;
          }
        }

        if (allPkPresent) {
          final signature =
              _pkFields.map((f) => _answers[f]?.toString() ?? '').join('|');
          if (_existingPrimaryKeys.contains(signature)) {
            // Duplicate found!
            _showDuplicateErrorDialog(q.fieldName);
            // Don't clear the answer, but set logic error to prevent proceeding
            _logicError = 'A record with this ID already exists.';
          }
        }
      }
    });
  }

  void _showDuplicateErrorDialog(String fieldName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Record'),
        content: Text(
            'A record with this ID already exists. Please enter a unique ID.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
              _logicError = currentQ.uniqueCheck!.message ??
                  'This value already exists in the database.';
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

    // Check for postskip conditions on the current question
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
    nextIndex = await _findNextDisplayedQuestion(qs, nextIndex);

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

    // Show verification reminder for hhid_verif question
    // if (nextIndex < qs.length) {
    //   final nextQuestion = qs[nextIndex];
    //   if (nextQuestion.fieldName.toLowerCase() == 'hhid_verif') {
    //     await _showVerificationReminder('hhid');
    //   }
    // }
  }

  /// Find the next question that should be displayed
  /// Handles automatic questions and preskip conditions
  Future<int> _findNextDisplayedQuestion(
      List<Question> qs, int startIndex) async {
    int index = startIndex;

    while (index < qs.length) {
      final q = qs[index];

      // Process and skip automatic questions
      if (q.type == QuestionType.automatic) {
        await _processAutomaticQuestion(q);
        index++;
        continue;
      }

      // Skip primary key questions in edit mode
      if (widget.uniqueId != null && _isPrimaryKeyField(q.fieldName)) {
        // CRITICAL FIX: Even if we skip DISPLAYING the primary key in edit mode,
        // we MUST recalculate it because the user might have changed the fields that compose it
        // (e.g. changing vcode should update hhid, so hhid_verif validation works)
        await _processAutomaticQuestion(q);
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
      _logicError = null; // Clear error on navigation

      // Re-evaluate logic checks for the question we're returning to
      if (_loadedQuestions != null &&
          _currentQuestion < _loadedQuestions!.length) {
        final question = _loadedQuestions![_currentQuestion];
        _logicError = LogicService.evaluateLogicChecks(question, _answers);
      }
    });
  }

  bool _isAnswered(Question q) {
    // Special case: 'comments' field is always optional
    if (q.fieldName.toLowerCase() == 'comments') {
      return true;
    }

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
        // For date questions, must have a date selected or special response
        if (val == null) return false;
        final valStr = val.toString();
        if (valStr.isEmpty) return false;
        // Special responses (don't know, refuse) are valid
        if (q.dontKnow != null && valStr == q.dontKnow) return true;
        if (q.refuse != null && valStr == q.refuse) return true;
        // Otherwise, must be a valid DateTime
        return val is DateTime ||
            (val is String && DateTime.tryParse(valStr) != null);
      case QuestionType.datetime:
        return val != null && val.toString().isNotEmpty;
      case QuestionType.information:
      case QuestionType.automatic:
        return true; // not applicable
    }
  }

  bool _isValid(Question q) {
    // For integer text fields, enforce numeric_check range
    // For text fields with numeric_check, enforce range
    // For integer text fields, enforce numeric_check range
    // For text fields with numeric_check, enforce range
    if (q.type == QuestionType.text) {
      final raw = _answers[q.fieldName]?.toString() ?? '';

      // Strict length check
      if (q.fixedLength && q.maxCharacters != null) {
        if (raw.length != q.maxCharacters) return false;
      }

      if (q.numericCheck != null) {
        if (raw.isEmpty) return false;

        final parsed = num.tryParse(raw);
        if (parsed == null) return false;

        final nc = q.numericCheck!;
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
  Future<void> _processAutomaticQuestion(Question q) async {
    // The automatic value calculation is already handled in QuestionView.initState
    // But we can also do it here for automatic questions we skip over

    // Check if this is a primary key field that needs ID generation
    // Fields are considered ID fields if they are NOT in the AutoFields registry
    // AND do not have a calculation configuration
    final isIdField = !AutoFields.getRegistry().containsKey(q.fieldName) &&
        q.calculation == null;

    debugPrint(
        '[ProcessingAuto] ${q.fieldName} isIdField=$isIdField hasCalculation=${q.calculation != null}');
    if (q.fieldName == 'hhid') {
      debugPrint(
          '[ProcessingAuto] hhid components: vcode=${_answers['vcode']}, mrccode=${_answers['mrccode']}, hhnum=${_answers['hhnum']}');
      debugPrint('[ProcessingAuto] idConfig: ${widget.idConfig}');
    }

    // For primary key fields, check if we need to regenerate or preserve existing value
    if (isIdField && widget.idConfig != null && widget.idConfig!.isNotEmpty) {
      // This is a primary key field (hhid, subjid, etc.)
      try {
        final tableName =
            widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
        final surveyId = await SurveyConfigService().getActiveSurveyId();

        if (surveyId != null) {
          // Check if all required fields are present
          if (IdGenerator.validateIdFields(
            idConfigJson: widget.idConfig!,
            answers: _answers,
          )) {
            // In edit mode, preserve existing ID if component fields haven't changed
            final existingId = _answers[q.fieldName]?.toString();
            final isEditMode = widget.uniqueId != null;

            if (isEditMode &&
                existingId != null &&
                existingId.isNotEmpty &&
                existingId != '-9') {
              // Check if the base ID components have changed
              final hasChanged = IdGenerator.hasBaseIdChanged(
                existingId: existingId,
                idConfigJson: widget.idConfig!,
                answers: _answers,
              );

              if (!hasChanged) {
                // Component fields haven't changed - preserve existing ID including increment
                debugPrint(
                    'Preserving existing ID "$existingId" for field "${q.fieldName}" (no component changes)');
                return;
              } else {
                debugPrint(
                    'Component fields changed for "${q.fieldName}" - regenerating ID');
              }
            }

            // Generate new ID (either new mode or component fields changed)
            final generatedId = await IdGenerator.generateId(
              surveyId: surveyId,
              tableName: tableName,
              idConfigJson: widget.idConfig!,
              answers: _answers,
            );
            _answers[q.fieldName] = generatedId;
            debugPrint(
                'Generated ID "$generatedId" for field "${q.fieldName}" in real-time');
            return;
          }
        }
      } catch (e) {
        debugPrint('Error generating ID for ${q.fieldName}: $e');
      }

      // Fallback if generation fails
      _answers[q.fieldName] = '-9';
    } else {
      // Regular automatic field (starttime, uniqueid, etc.)

      // Force re-calculation even if value exists (unless preserve is handled by AutoFields)
      // This ensures dependent fields update when their dependencies change.

      final value = await AutoFields.compute(
        _answers,
        q,
        isEditMode: widget.uniqueId != null,
        surveyId: _activeSurveyId,
      );
      _answers[q.fieldName] = value;
    }
  }

  /// Skip to the first question that should be displayed
  Future<void> _skipToFirstDisplayedQuestion(List<Question> questions) async {
    int index = 0;

    // Find the first displayable question
    while (index < questions.length) {
      final q = questions[index];

      // Process and skip automatic questions
      if (q.type == QuestionType.automatic) {
        await _processAutomaticQuestion(q);
        index++;
        continue;
      }

      // Skip primary key questions in edit mode
      if (widget.uniqueId != null && _isPrimaryKeyField(q.fieldName)) {
        debugPrint('Skipping primary key question on load: ${q.fieldName}');
        // CRITICAL FIX: Recalculate PK even if hidden
        await _processAutomaticQuestion(q);
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
          return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
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
        final canProceed = (q.type == QuestionType.information ||
                (_isAnswered(q) && _isValid(q))) &&
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
              tooltip: 'Cancel Interview',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Cancel Interview'),
                    content: const Text(
                        'Are you sure you want to cancel the interview? \n\nAll edits/modifications will be lost!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                          Navigator.of(context)
                              .pop(false); // Return false to indicate cancelled
                        },
                        child: const Text('Yes'),
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
                                    onRequestNext: () => _next(questions),
                                    isEditMode: widget.uniqueId != null,
                                    logicError: _logicError,
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

    // Note: Primary key ID (hhid/subjid) is now generated in real-time
    // when the automatic question is processed, not here at save time

    // Check if there are any changes (for edit mode only)
    if (widget.uniqueId != null) {
      if (!_hasChanges()) {
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

      // Show review summary before saving
      final summary = await ChangeSummaryService.getSummary(
        originalAnswers: _originalAnswers!,
        currentAnswers: _answers,
        questions: questions,
        csvService: _csvDataService,
        surveyId: _activeSurveyId ?? '',
      );

      if (summary.isNotEmpty) {
        final result = await _showReviewChangesDialog(context, summary);
        if (result == 'discard') {
          // Exit without saving
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        } else if (result != 'save') {
          // 'back' or null (dialog dismissed/canceled)
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
    });

    // Update lastmod timestamp only when actually saving
    AutoFields.touchLastMod(_answers);

    // Create a deep copy for saving
    // Values are saved as-is (padding preserved)
    final answersToSave = Map<String, dynamic>.from(_answers);

    if (_loadedQuestions != null) {
      for (final q in _loadedQuestions!) {
        final val = answersToSave[q.fieldName];
        if (val == null) continue;

        if (q.type == QuestionType.date) {
          final valStr = val.toString();
          try {
            final dt = DateTime.tryParse(valStr);
            if (dt != null) {
              answersToSave[q.fieldName] = dt.toIso8601String().split('T')[0];
            }
          } catch (_) {}
        } else if (q.type == QuestionType.datetime) {
          final valStr = val.toString();
          try {
            final dt = DateTime.tryParse(valStr);
            if (dt != null) {
              answersToSave[q.fieldName] = dt.toIso8601String();
            }
          } catch (_) {}
        }
      }
    }

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

    if (!mounted) return;

    if (saveSuccessful) {
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

  /// Check if any child surveys should auto-repeat after this survey completes
  Future<void> _checkAndStartAutoRepeat(BuildContext context) async {
    try {
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      final surveyId = await SurveyConfigService().getActiveSurveyId();
      if (surveyId == null) return;

      // Get all CRF records to find child surveys
      final allCrfs = await DbService.getExistingRecords(surveyId, 'crfs');

      // Sort by display_order to ensure repeats happen in correct sequence
      final sortedCrfs = List<Map<String, dynamic>>.from(allCrfs);
      sortedCrfs.sort((a, b) {
        final orderA = (a['display_order'] as int?) ?? 0;
        final orderB = (b['display_order'] as int?) ?? 0;
        return orderA.compareTo(orderB);
      });

      for (final crf in sortedCrfs) {
        final childTableName = crf['tablename']?.toString();
        final parentTable = crf['parenttable']?.toString();

        // Safely parse auto_start_repeat, handling both int and String
        int autoStartRepeat = 0;
        final autoStartVal = crf['auto_start_repeat'];
        if (autoStartVal is int) {
          autoStartRepeat = autoStartVal;
        } else if (autoStartVal is String) {
          autoStartRepeat = int.tryParse(autoStartVal) ?? 0;
        }

        // Check if this is a child of the current survey
        // Use parentTable
        if (childTableName != null &&
            parentTable == tableName &&
            autoStartRepeat > 0) {
          // Get the repeat count field
          final repeatCountField = crf['repeat_count_field']?.toString();
          if (repeatCountField == null || repeatCountField.isEmpty) {
            continue;
          }

          // Get the repeat count from the answers
          final repeatCountValue = _answers[repeatCountField];
          if (repeatCountValue == null) {
            continue;
          }

          final repeatCount = int.tryParse(repeatCountValue.toString());
          if (repeatCount == null || repeatCount <= 0) {
            continue;
          }

          // Get the linking field to pass to child surveys
          final linkingField = crf['linkingfield']?.toString();
          if (linkingField == null) {
            continue;
          }

          final linkingValue = _answers[linkingField];
          if (linkingValue == null) {
            continue;
          }

          // Prompt user to start repeat surveys
          final displayName = crf['displayname']?.toString() ?? childTableName;

          if (autoStartRepeat == 1) {
            // Prompt mode
            final shouldStart = await _promptStartRepeatSurveys(
              context,
              childTableName,
              displayName,
              repeatCount,
            );

            if (shouldStart == true) {
              await _startRepeatSurveyLoop(
                context,
                childTableName,
                displayName,
                repeatCount,
                linkingField,
                linkingValue.toString(),
                crf,
              );
              // Don't return - continue to check for more repeating sections
            } else {
              // User declined to start this repeat section - skip to next
              continue;
            }
          } else if (autoStartRepeat == 2) {
            // Force mode - auto start
            await _startRepeatSurveyLoop(
              context,
              childTableName,
              displayName,
              repeatCount,
              linkingField,
              linkingValue.toString(),
              crf,
            );
            // Don't return - continue to check for more repeating sections
          }
        }
      }

      // No auto-repeat configured, show success dialog
      _showSaveSuccessDialog(context);
    } catch (e) {
      debugPrint('Error checking auto-repeat: $e');
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
        title: Text('Add $displayName Now?'),
        content: Text(
            'You indicated $count ${count == 1 ? 'record' : 'records'}.\n\n'
            'Would you like to add them now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Add Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Now'),
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
    final repeatCountField = crfConfig['repeat_count_field']?.toString();
    final enforceCountMode = (crfConfig['repeat_enforce_count'] as int?) ??
        1; // Default to warn mode

    int completedCount = 0;

    // Convert displayName to singular form for entity name
    // "Household members" -> "Household member"
    // "Sleeping Structures" -> "Sleeping Structure"
    String entityName = displayName;
    if (entityName.endsWith('s')) {
      entityName = entityName.substring(0, entityName.length - 1);
    }

    for (int i = 1; i <= repeatCount; i++) {
      if (!mounted) break;

      // Navigate to child survey
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => SurveyScreen(
            questionnaireFilename: '$childTableName.xml',
            prepopulatedAnswers: {linkingField: linkingValue},
            incrementField: crfConfig['incrementfield']?.toString(),
            repeatIndex: i,
            repeatTotal: repeatCount,
            repeatEntityName: entityName,
          ),
        ),
      );

      // Check if user completed the survey (result == true means saved)
      if (result == true) {
        completedCount++;
      } else {
        // User exited without saving
        // Check if we should enforce count
        if (enforceCountMode == 2) {
          // Force mode - must complete (no exit option)
          await _showMustCompleteDialogWithEntity(
            context,
            repeatCount,
            i,
            entityName,
            allowExit: false, // Force mode: user cannot exit
          );
          // In force mode, dialog will always return true (user can only click Continue)
          i--; // Retry this iteration
          continue;
        } else {
          // User can exit, but we'll check count at the end
          break;
        }
      }
    }

    if (!mounted) return;

    // After loop, check if count matches
    // Note: This will handle the mismatch but NOT show success dialog yet
    // We need to check for more repeating sections first
    await _handleRepeatCountMismatch(
      context,
      childTableName,
      displayName,
      linkingField,
      linkingValue,
      repeatCount,
      completedCount,
      enforceCountMode,
      repeatCountField,
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
        title: Text('Must Complete All $entityNamePlural'),
        content: Text(
            'You must add all $total $entityNamePlural.\n\nCurrently on ${entityName.toLowerCase()} $current of $total.'),
        actions: [
          if (allowExit)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Exit Anyway'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return result ?? true;
  }

  /// Handle repeat count mismatch (without showing success dialog)
  /// Returns true if everything is ok, false if there was an issue
  Future<bool> _handleRepeatCountMismatch(
    BuildContext context,
    String childTableName,
    String displayName,
    String linkingField,
    String linkingValue,
    int expectedCount,
    int completedCount,
    int enforceCountMode,
    String? repeatCountField,
  ) async {
    final surveyId = await SurveyConfigService().getActiveSurveyId();
    if (surveyId == null) return false;

    // Get actual count from database
    final actualCount = await DbService.getRecordCount(
      surveyId: surveyId,
      tableName: childTableName,
      where: '$linkingField = ?',
      whereArgs: [linkingValue],
    );

    if (actualCount == expectedCount) {
      // Perfect match
      return true;
    }

    // Mismatch detected
    debugPrint('Count mismatch: expected=$expectedCount, actual=$actualCount');

    if (enforceCountMode == 0) {
      // Flexible mode - allow any count
      return true;
    } else if (enforceCountMode == 1) {
      // Warn mode - show dialog with options
      final action = await _showCountMismatchDialog(
        context,
        displayName,
        expectedCount,
        actualCount,
      );

      if (action == 'update' && repeatCountField != null) {
        // Update the parent record's count field
        final parentTableName =
            widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
        final parentLinkingValue = _answers[linkingField];

        await DbService.updateField(
          surveyId: surveyId,
          tableName: parentTableName,
          field: repeatCountField,
          value: actualCount,
          where: '$linkingField = ?',
          whereArgs: [parentLinkingValue],
        );

        debugPrint(
            'Updated $parentTableName.$repeatCountField to $actualCount');
      }
      return true;
    } else if (enforceCountMode == 3) {
      // Auto-sync mode - silently update parent record
      if (repeatCountField != null) {
        final parentTableName =
            widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
        final parentLinkingValue = _answers[linkingField];

        await DbService.updateField(
          surveyId: surveyId,
          tableName: parentTableName,
          field: repeatCountField,
          value: actualCount,
          where: '$linkingField = ?',
          whereArgs: [parentLinkingValue],
        );

        debugPrint(
            'Auto-synced $parentTableName.$repeatCountField to $actualCount');
      }
      return true;
    }

    return true;
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
        title: const Text('Incomplete Data'),
        content: Text(
            'You indicated $expected ${expected == 1 ? 'record' : 'records'} for $displayName but only added $actual.\n\n'
            'This will cause data quality issues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'force'),
            child: const Text('Exit Anyway ⚠️'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text('Update Count to $actual'),
          ),
        ],
      ),
    );
  }

  /// Show verification reminder dialog before user enters verification field
  // Future<void> _showVerificationReminder(String fieldToVerify) async {
  //   final value = _answers[fieldToVerify]?.toString();
  //   if (value == null || value.isEmpty) return;

  //   await showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (context) => AlertDialog(
  //       title: Row(
  //         children: [
  //           Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
  //           const SizedBox(width: 8),
  //           const Text('Please Verify'),
  //         ],
  //       ),
  //       content: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             'You entered the following value for ${fieldToVerify.toUpperCase()}:',
  //             style: const TextStyle(fontWeight: FontWeight.w500),
  //           ),
  //           const SizedBox(height: 12),
  //           Container(
  //             padding: const EdgeInsets.all(12),
  //             decoration: BoxDecoration(
  //               color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
  //               borderRadius: BorderRadius.circular(8),
  //               border: Border.all(
  //                 color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
  //               ),
  //             ),
  //             child: Text(
  //               value,
  //               style: TextStyle(
  //                 fontSize: 20,
  //                 fontWeight: FontWeight.bold,
  //                 color: Theme.of(context).colorScheme.primary,
  //               ),
  //             ),
  //           ),
  //           const SizedBox(height: 12),
  //           const Text(
  //             'Please re-enter this value in the next field to verify.',
  //             style: TextStyle(fontSize: 13),
  //           ),
  //         ],
  //       ),
  //       actions: [
  //         FilledButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('OK'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

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
    }
  }

  /// Show save error dialog
  void _showSaveErrorDialog(BuildContext context, String? errorMessage) {
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
                setState(() {
                  _isSaving = false;
                });
              },
              child: const Text('Close'),
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
        title: const Row(
          children: [
            Icon(Icons.rate_review_outlined, color: Colors.blue),
            SizedBox(width: 8),
            Text('Review Changes'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: summary.isEmpty
              ? const Text('No logical changes detected.')
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Discard Changes?'),
                      content: const Text(
                          'Are you sure you want to discard all changes and exit? This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Discard & Exit',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    Navigator.pop(context, 'discard');
                  }
                },
                child: const Text('Discard & Exit',
                    style: TextStyle(color: Colors.red)),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'back'),
                    child: const Text('Back to Edit'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
