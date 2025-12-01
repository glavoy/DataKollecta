enum QuestionType { automatic, text, checkbox, radio, information, date, combobox, datetime }

enum ResponseSource { static_, csv, database }

class QuestionOption {
  final String value;
  final String label;
  QuestionOption({required this.value, required this.label});
}

class ResponseFilter {
  final String column;
  final String value;
  final String operator;

  ResponseFilter({
    required this.column,
    required this.value,
    this.operator = '=',
  });
}

class ResponseConfig {
  final ResponseSource source;
  final String? file;  // For CSV source
  final String? table;  // For database source
  final List<ResponseFilter> filters;
  final String? displayColumn;
  final String? valueColumn;
  final bool distinct;
  final String? emptyMessage;
  final String? dontKnowValue;  // Optional: Value for "Don't know" option
  final String? dontKnowLabel;  // Optional: Label for "Don't know" option
  final String? notInListValue; // Optional: Value for "Not in this list" option
  final String? notInListLabel; // Optional: Label for "Not in this list" option

  ResponseConfig({
    required this.source,
    this.file,
    this.table,
    this.filters = const [],
    this.displayColumn,
    this.valueColumn,
    this.distinct = true,  // Default to true - almost always want unique values
    this.emptyMessage,
    this.dontKnowValue,
    this.dontKnowLabel,
    this.notInListValue,
    this.notInListLabel,
  });
}

class NumericCheck {
  final int? minValue;
  final int? maxValue;
  final String? otherValues; // comma-separated string of allowed exceptions
  final String? message;

  const NumericCheck({this.minValue, this.maxValue, this.otherValues, this.message});
}

/// Skip condition for navigating between questions
class SkipCondition {
  final String fieldName;        // Field to check (e.g., 'sex')
  final String condition;        // Comparison operator (e.g., '=', '<>', '<', '>')
  final String response;         // Value to compare against (e.g., '1')
  final String responseType;     // 'fixed' or 'dynamic'
  final String skipToFieldName;  // Target field to skip to (e.g., 'village')

  SkipCondition({
    required this.fieldName,
    required this.condition,
    required this.response,
    required this.responseType,
    required this.skipToFieldName,
  });
}

class UniqueCheck {
  final String? message;

  UniqueCheck({this.message});
}

class Question {
  final QuestionType type;
  final String fieldName;
  final String fieldType;
  final String? text;
  final int? maxCharacters;
  final NumericCheck? numericCheck;
  final List<QuestionOption> options;
  final ResponseConfig? responseConfig;  // New: for dynamic responses
  final List<SkipCondition> preSkips;  // Evaluated before showing the question
  final List<SkipCondition> postSkips; // Evaluated after user answers
  final String? logicCheck;
  final String? dontKnow; // Special response value for "Don't know" (e.g., "-7")
  final String? refuse;   // Special response value for "Refuse" (e.g., "-8")
  final String? minDate;  // Date range constraint (e.g., "-1y")
  final String? maxDate;  // Date range constraint (e.g., "+0d")
  final UniqueCheck? uniqueCheck;

  Question({
    required this.type,
    required this.fieldName,
    required this.fieldType,
    this.text,
    this.maxCharacters,
    this.numericCheck,
    this.options = const [],
    this.responseConfig,
    this.preSkips = const [],
    this.postSkips = const [],
    this.logicCheck,
    this.dontKnow,
    this.refuse,
    this.minDate,
    this.maxDate,
    this.uniqueCheck,
  });
}

/// Simple answer store type: for checkboxes, store List<String>, for others String.
typedef AnswerMap = Map<String, dynamic>;

QuestionType parseQuestionType(String raw) {
  switch (raw.toLowerCase()) {
    case 'automatic':
      return QuestionType.automatic;
    case 'text':
      return QuestionType.text;
    case 'checkbox':
      return QuestionType.checkbox;
    case 'radio':
      return QuestionType.radio;
    case 'information':
      return QuestionType.information;
    case 'date':
      return QuestionType.date;
    case 'combobox':
      return QuestionType.combobox;
    case 'datetime':
      return QuestionType.datetime;
    default:
      return QuestionType.information;
  }
}
