import '../models/question.dart';
import 'answer_equality.dart';
import 'survey_loader.dart';
import 'csv_data_service.dart';
import 'database_response_service.dart';

class ChangeSummaryItem {
  final String fieldName;
  final String questionText;
  final String oldLabel;
  final String newLabel;

  ChangeSummaryItem({
    required this.fieldName,
    required this.questionText,
    required this.oldLabel,
    required this.newLabel,
  });
}

class ChangeSummaryService {
  /// Generates a list of logical changes between original and current answers.
  /// Resolves technical values (IDs) into human-readable labels.
  static Future<List<ChangeSummaryItem>> getSummary({
    required AnswerMap originalAnswers,
    required AnswerMap currentAnswers,
    required List<Question> questions,
    required CsvDataService csvService,
    required String surveyId,
  }) async {
    final List<ChangeSummaryItem> summary = [];

    // Combine all keys to ensure we check everything
    final allKeys = {...originalAnswers.keys, ...currentAnswers.keys};

    for (final fieldName in allKeys) {
      final oldValue = originalAnswers[fieldName];
      final newValue = currentAnswers[fieldName];

      // Padding, a checkbox List against the string it is stored as, and a
      // DateTime against the ISO text it was loaded from are all the same
      // answer written differently -- see AnswerEquality. This used to have
      // its own rule that handled only the first, so an edit could be listed
      // here that formchanges never recorded.
      if (AnswerEquality.sameAnswer(oldValue, newValue)) continue;

      // Find the question definition
      final question = questions.firstWhere(
        (q) => q.fieldName == fieldName,
        orElse: () => Question(
          fieldName: fieldName,
          type: QuestionType.automatic,
          fieldType: 'text',
        ),
      );

      // Skip internal/automatic fields that aren't useful in a summary
      if (question.type == QuestionType.automatic &&
          (fieldName == 'lastmod' ||
              fieldName == 'starttime' ||
              fieldName == 'stoptime' ||
              fieldName == 'uniqueid')) {
        continue;
      }

      final oldLabel = await _resolveLabel(
        value: oldValue,
        question: question,
        answers: originalAnswers,
        csvService: csvService,
        surveyId: surveyId,
      );

      final newLabel = await _resolveLabel(
        value: newValue,
        question: question,
        answers: currentAnswers,
        csvService: csvService,
        surveyId: surveyId,
      );

      summary.add(ChangeSummaryItem(
        fieldName: fieldName,
        questionText: SurveyLoader.expandPlaceholders(
          question.text ?? fieldName,
          currentAnswers,
        ),
        oldLabel: oldLabel,
        newLabel: newLabel,
      ));
    }

    return summary;
  }

  static Future<String> _resolveLabel({
    required dynamic value,
    required Question question,
    required AnswerMap answers,
    required CsvDataService csvService,
    required String surveyId,
  }) async {
    if (value == null) return '[Cleared]';
    final valStr = value.toString();
    if (valStr.isEmpty) return '[Empty]';

    // 1. Check static options
    if (question.options.isNotEmpty) {
      final option = question.options.firstWhere(
        (opt) => opt.value == valStr,
        orElse: () => QuestionOption(value: '', label: ''),
      );
      if (option.label.isNotEmpty) return option.label;
    }

    // 2. Check dynamic options (CSV/Database)
    if (question.responseConfig != null) {
      final List<QuestionOption> options;
      if (question.responseConfig!.source == ResponseSource.csv) {
        options = await csvService.getResponseOptions(
          question.responseConfig!,
          answers,
        );
      } else if (question.responseConfig!.source == ResponseSource.database) {
        options = await DatabaseResponseService.getResponseOptions(
          surveyId,
          question.responseConfig!,
          answers,
        );
      } else {
        options = [];
      }

      final option = options.firstWhere(
        (opt) => opt.value == valStr,
        orElse: () => QuestionOption(value: '', label: ''),
      );
      if (option.label.isNotEmpty) return option.label;
    }

    // 3. Fallback to raw value (for text, dates, or unresolved IDs)
    return valStr;
  }
}
