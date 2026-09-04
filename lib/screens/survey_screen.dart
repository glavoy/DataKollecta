import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../widgets/question_views.dart';
import '../services/child_increment_service.dart';
import '../services/db_service.dart';
import '../services/auto_fields.dart';
import '../config/app_config.dart';
import '../services/id_generator.dart';
import '../services/logic_service.dart';
import '../services/survey_config_service.dart';
import '../services/survey_navigation_service.dart';
import '../services/csv_data_service.dart';
import '../services/change_summary_service.dart';
import '../services/app_strings.dart';
import '../services/numeric_validation_service.dart';
import '../services/repeat_count_service.dart';

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
  final int? repeatCompletedSoFar; // Records already saved this loop, before this one

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
  Set<String> _existingPrimaryKeys = {};
  List<String> _pkFields = [];

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
        final surveyId = await SurveyConfigService().getActiveSurveyId();
        if (surveyId != null) {
          final tableName =
              widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
          _pkFields = await DbService.getPrimaryKeyFields(surveyId, tableName);

          if (_pkFields.isNotEmpty) {
            final allKeys = await DbService.getAllPrimaryKeys(
                surveyId, tableName, _pkFields);

            // Both sides of the comparison are built the same way, from the
            // same lowercased field list, so a case difference between the
            // worksheet and the XML cannot make them disagree. The snapshot
            // is loaded once per screen, which is enough: the auto-repeat
            // loop pushes a fresh SurveyScreen per child, so each child sees
            // its siblings.
            _existingPrimaryKeys = allKeys.map((row) {
              return _pkFields.map((f) => row[f]?.toString() ?? '').join('|');
            }).toSet();

            debugPrint(
                'Loaded ${_existingPrimaryKeys.length} existing primary keys for duplicate check');
          }
        }
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
          tableName: widget.questionnaireFilename
              .toLowerCase()
              .replaceAll('.xml', ''),
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

        // Special responses (don't know / refuse) bypass the numeric range check
        final isSpecialResponse = raw.isNotEmpty &&
            ((q.dontKnow != null && raw == q.dontKnow) ||
                (q.refuse != null && raw == q.refuse));

        if (_logicError == null && raw.isNotEmpty && !isSpecialResponse) {
          // "12." is a number the interviewer has not finished typing. Flag it
          // on any decimal field, not just one that also declares a range.
          if (NumericValidationService.isIncompleteDecimal(q.fieldType, raw,
              hasRangeCheck: q.numericCheck != null)) {
            _logicError = _s.incompleteDecimalValue;
            return;
          }

          final parsed = num.tryParse(raw);
          if (q.numericCheck != null && parsed != null) {
            final nc = q.numericCheck!;
            if (!NumericValidationService.isWithinRange(nc, parsed)) {
              // The generator writes this sentence in English whatever the
              // build, so the app supplies the wording. A message the author
              // wrote is already in the dictionary's language: use it as-is.
              final ownWording =
                  _s.numberMustBeBetween(nc.minValue ?? '', nc.maxValue ?? '');
              _logicError =
                  SurveyLoader.isGeneratedNumericRangeMessage(nc.message)
                      ? ownWording
                      : (nc.message ?? ownWording);
            }
          }
        }
      }

      // Real-time duplicate check (New Record Mode only)
      if (_pkFields.contains(q.fieldName.toLowerCase()) &&
          _isDuplicatePrimaryKey()) {
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
    final value = _answerFor('uniqueid')?.toString();
    if (value == null || value.isEmpty) {
      debugPrint('[SurveyScreen] No uniqueid on this record, so children '
          'started from here will have an empty '
          '${AutoFields.parentUniqueIdField}.');
      return null;
    }
    return value;
  }

  /// Reads an answer by field name, ignoring case.
  ///
  /// `_pkFields` are lowercased crfs values while `_answers` is keyed by the
  /// XML's own fieldname, so the two only line up when the dictionary happens
  /// to agree with itself about case.
  dynamic _answerFor(String fieldName) {
    if (_answers.containsKey(fieldName)) return _answers[fieldName];
    final target = fieldName.toLowerCase();
    for (final entry in _answers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  /// Whether the primary key now in `_answers` already exists in this table.
  ///
  /// Pure, and separate from [_onAnswerChanged], because that method only
  /// runs for the question the interviewer is *on* -- so a primary key made
  /// entirely of `automatic` fields could never trigger it. In PRISM CSS both
  /// halves of `(hhid, linenum)` are `type='automatic'` with no
  /// `<calculation>`, so neither ever renders and this check has never once
  /// fired for that survey. [_processAutomaticQuestion] now calls it too,
  /// where the key is actually computed.
  ///
  /// New records only: an existing record's own key is in the snapshot, so
  /// editing one would always look like a duplicate of itself.
  bool _isDuplicatePrimaryKey() {
    if (widget.existingAnswers != null) return false;
    if (_pkFields.isEmpty || _existingPrimaryKeys.isEmpty) return false;

    final values = <String>[];
    for (final pkField in _pkFields) {
      final value = _answerFor(pkField)?.toString() ?? '';
      // A partial key cannot be compared -- every record would collide on the
      // same half-empty signature.
      if (value.isEmpty) return false;
      values.add(value);
    }

    return _existingPrimaryKeys.contains(values.join('|'));
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

  bool _isAnswered(Question q) {
    // A question the dictionary marked <optional> may be left blank -- the
    // Next button stays enabled with no answer. Replaces the old hardcoded
    // 'comments' fieldname special-case, which applied regardless of what
    // the XML actually declared and gave every survey exactly one skippable
    // field, always named 'comments'.
    if (q.optional) {
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

      // Special responses (don't know / refuse) bypass format/length/numeric checks
      if (raw.isNotEmpty &&
          ((q.dontKnow != null && raw == q.dontKnow) ||
              (q.refuse != null && raw == q.refuse))) {
        return true;
      }

      // Strict length check
      if (q.fixedLength && q.maxCharacters != null) {
        if (raw.length != q.maxCharacters) return false;
      }

      // A half-typed decimal blocks Next whether or not a range is declared.
      if (NumericValidationService.isIncompleteDecimal(q.fieldType, raw,
          hasRangeCheck: q.numericCheck != null)) {
        return false;
      }

      if (q.numericCheck != null) {
        if (raw.isEmpty) return false;

        final parsed = num.tryParse(raw);
        if (parsed == null) return false;

        if (!NumericValidationService.isWithinRange(q.numericCheck!, parsed)) {
          return false;
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

    // Check if this is a primary key field that needs ID generation. The
    // predicate lives in SurveyNavigationService so it can be tested --
    // getting it wrong silently overwrites a correct, already-populated value
    // with a freshly generated one.
    final isIdField = SurveyNavigationService.isGeneratedIdField(
      q,
      hasRegistryEntry: AutoFields.getRegistry().containsKey(q.fieldName),
      linkingField: widget.linkingField,
      incrementField: widget.incrementField,
    );

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
              fieldName: q.fieldName,
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
    if (_pkFields.contains(q.fieldName.toLowerCase()) &&
        _isDuplicatePrimaryKey()) {
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
          return Scaffold(body: Center(child: Text('${_s.error}: ${snap.error}')));
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

      // Sort by display_order to ensure repeats happen in correct sequence
      final sortedCrfs = List<Map<String, dynamic>>.from(allCrfs);
      sortedCrfs.sort((a, b) {
        final orderA = (a['display_order'] as int?) ?? 0;
        final orderB = (b['display_order'] as int?) ?? 0;
        return orderA.compareTo(orderB);
      });

      for (final crf in sortedCrfs) {
        // Re-checked per iteration, not just once above: the prompt and the
        // repeat loop below both await, so a later pass can resume after the
        // user has already left this screen.
        if (!context.mounted) return;

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
              if (!context.mounted) return;
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
    final repeatCountField = crfConfig['repeat_count_field']?.toString();
    final enforceCountMode =
        RepeatCountService.parseEnforceMode(crfConfig['repeat_enforce_count']);

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
            // This loop runs inside the parent's own screen, so `_answers`
            // still holds the parent's record -- its `uniqueid` is the
            // immutable join key the child carries alongside the linking
            // value. Unlike the parent-ID selector, nothing has to be looked
            // up for it.
            prepopulatedAnswers: {
              linkingField: linkingValue,
              if (_parentUniqueIdForChildren() != null)
                AutoFields.parentUniqueIdField: _parentUniqueIdForChildren()!,
            },
            incrementField: crfConfig['incrementfield']?.toString(),
            repeatIndex: i,
            repeatTotal: repeatCount,
            repeatEntityName: entityName,
            repeatEntityNamePlural: displayName,
            repeatEnforceMode: enforceCountMode,
            repeatCompletedSoFar: completedCount,
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
          if (!context.mounted) return;
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
        }

        // Leaving early is allowed in every other mode -- but not below the
        // floor the count question itself declares. A household cannot have
        // zero members, so the interviewer must not be able to walk out of
        // the loop leaving a count the form would have rejected.
        if (await _isBelowDeclaredMinimum(
            childTableName, linkingValue, entityName)) {
          if (!mounted) break;
          i--; // Retry this iteration
          continue;
        }

        // User can exit, but we'll check count at the end
        break;
      }
    }

    if (!context.mounted) return;

    // After loop, reconcile the parent's count with what was actually entered.
    // This does not show the success dialog -- more repeating sections may
    // still follow.
    debugPrint('Repeat loop for $childTableName finished: '
        '$completedCount of $repeatCount entered '
        '(count field $repeatCountField, enforce mode $enforceCountMode)');
    await _reconcileRepeatCount(context, childTableName, linkingValue);
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
        content: Text(_s.mustCompleteMessage(total, entityNamePlural, entityName, current)),
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
        content: Text(_s.countAutoUpdatedMessage(expected, displayName, actual)),
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
          content: Text(isUpdate ? _s.recordUpdatedSuccess : _s.answersSavedSuccess),
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
