/// Type alias for the map of answers
typedef AnswerMap = Map<String, dynamic>;

enum QuestionType {
  automatic,
  text,
  checkbox,
  radio,
  information,
  date,
  combobox,
  datetime
}

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
  final String? file; // For CSV source
  final String? table; // For database source
  final List<ResponseFilter> filters;
  final String? displayColumn;
  final String? valueColumn;
  final bool distinct;
  final String? emptyMessage;
  final String? dontKnowValue; // Optional: Value for "Don't know" option
  final String? dontKnowLabel; // Optional: Label for "Don't know" option
  final String? notInListValue; // Optional: Value for "Not in this list" option
  final String? notInListLabel; // Optional: Label for "Not in this list" option

  ResponseConfig({
    required this.source,
    this.file,
    this.table,
    this.filters = const [],
    this.displayColumn,
    this.valueColumn,
    this.distinct = true, // Default to true - almost always want unique values
    this.emptyMessage,
    this.dontKnowValue,
    this.dontKnowLabel,
    this.notInListValue,
    this.notInListLabel,
  });
}

class NumericCheck {
  final num? minValue;
  final num? maxValue;
  final String? otherValues; // comma-separated string of allowed exceptions
  final String? message;

  const NumericCheck(
      {this.minValue, this.maxValue, this.otherValues, this.message});
}

/// Skip condition for navigating between questions
class SkipCondition {
  final String fieldName; // Field to check (e.g., 'sex')
  final String condition; // Comparison operator (e.g., '=', '<>', '<', '>')
  final String response; // Value to compare against (e.g., '1')
  final String responseType; // 'fixed' or 'dynamic'
  final String skipToFieldName; // Target field to skip to (e.g., 'village')

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

class LogicCheck {
  final String message;
  final String condition; // e.g., "age > 18"

  LogicCheck({required this.message, required this.condition});
}

class CalculationConfig {
  final String type; // constant, lookup, query, concat, math, case
  final String? value; // for constant, case value
  final String? field; // for lookup, case field
  final String? sql; // for query
  final Map<String, String>? sqlParams; // for query
  final String? separator; // for concat
  final String? operator; // for math, case
  final List<CalculationConfig>? parts; // for concat, math
  final List<CaseConfig>? cases; // for case
  final CalculationConfig? defaultValue; // for case else
  final bool preserve; // if true, don't recompute in edit mode if value exists

  CalculationConfig({
    required this.type,
    this.value,
    this.field,
    this.sql,
    this.sqlParams,
    this.separator,
    this.operator,
    this.parts,
    this.cases,
    this.defaultValue,
    this.preserve = false,
  });
}

class CaseConfig {
  final String field;
  final String operator;
  final String value;
  final CalculationConfig result;

  CaseConfig({
    required this.field,
    required this.operator,
    required this.value,
    required this.result,
  });
}

class Question {
  final QuestionType type;
  final String fieldName;
  final String fieldType;
  final String? text;
  final int? maxCharacters;
  final bool fixedLength;
  final int? numericRange; // For zero padding (e.g. numeric_range=x)
  final NumericCheck? numericCheck;
  final List<QuestionOption> options;
  final ResponseConfig? responseConfig; // New: for dynamic responses
  final List<SkipCondition> preSkips; // Evaluated before showing the question
  final List<SkipCondition> postSkips; // Evaluated after user answers
  final List<LogicCheck> logicChecks; // Multiple logic checks evaluated in order
  final String? dontKnow;
  final String? refuse;
  final DateTime? minDate;
  final DateTime? maxDate;
  final UniqueCheck? uniqueCheck;
  final CalculationConfig? calculation;

  Question({
    required this.type,
    required this.fieldName,
    required this.fieldType,
    this.text,
    this.maxCharacters,
    this.fixedLength = false,
    this.numericRange,
    this.numericCheck,
    this.options = const [],
    this.responseConfig,
    this.preSkips = const [],
    this.postSkips = const [],
    this.logicChecks = const [],
    this.dontKnow,
    this.refuse,
    this.minDate,
    this.maxDate,
    this.uniqueCheck,
    this.calculation,
  });
}
