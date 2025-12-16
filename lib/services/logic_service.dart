// lib/services/logic_service.dart
import 'package:flutter/foundation.dart';
import '../models/question.dart';

class LogicService {
  /// Evaluates the logic check expression for a given question.
  /// Returns an error message if the expression evaluates to true, otherwise null.
  static String? evaluateLogicChecks(Question question, AnswerMap answers) {
    final logicCheck = question.logicCheck;
    if (logicCheck == null) {
      return null;
    }

    try {
      // The condition is already separated in the LogicCheck object
      final String conditionStr = logicCheck.condition;
      final String message = logicCheck.message;

      // Evaluate the expression
      final bool result = _evaluateExpression(conditionStr, answers);

      debugPrint(
          '[LogicService] Evaluating logic for ${question.fieldName}: "$conditionStr" --> $result');

      // If the expression is true, the check has failed, so return the message
      if (result) {
        return message;
      }
    } catch (e) {
      debugPrint(
          '[LogicService] Error evaluating expression: "${logicCheck.condition}". Error: $e');
      // Return error message to be visible in UI for debugging
      return 'Error in logic check expression: $e';
    }

    return null;
  }

  /// Evaluates a boolean expression string with AND and OR clauses.
  static bool _evaluateExpression(String expression, AnswerMap answers) {
    // Handle OR clauses by splitting the expression and checking if any are true
    final orClauses =
        expression.split(RegExp(r'\s+or\s+', caseSensitive: false));
    for (var orClause in orClauses) {
      orClause = orClause.trim();

      // Remove outer parentheses from the OR clause if present
      if (orClause.startsWith('(') && orClause.endsWith(')')) {
        orClause = orClause.substring(1, orClause.length - 1).trim();
      }

      // Handle AND clauses within each OR clause
      final andClauses =
          orClause.split(RegExp(r'\s+and\s+', caseSensitive: false));
      bool isAndClauseTrue = true;
      for (final andClause in andClauses) {
        // If any AND condition is false, the whole AND clause is false
        if (!_evaluateSingleCondition(andClause.trim(), answers)) {
          isAndClauseTrue = false;
          break;
        }
      }
      // If any AND clause is true, the whole OR expression is true
      if (isAndClauseTrue) {
        return true;
      }
    }
    return false;
  }

  /// Evaluates a single condition like "field = 'value'" or "field1 <> field2"
  static bool _evaluateSingleCondition(String condition, AnswerMap answers) {
    // Remove outer parentheses if present
    condition = condition.trim();
    if (condition.startsWith('(') && condition.endsWith(')')) {
      condition = condition.substring(1, condition.length - 1).trim();
    }

    debugPrint('[LogicService]   Evaluating single condition: "$condition"');

    // Regex to capture: (field_name) (operator) (value)
    // The value can be a quoted string or another field name.
    // Handles operators like =, <>, <=, >=, <, >
    final regex = RegExp(r"^\s*([\w_]+)\s*([<>=!]+)\s*('[\w_]+'|[\w_]+)\s*$");
    final match = regex.firstMatch(condition);

    if (match == null) {
      debugPrint('[LogicService]   ERROR: Failed to parse condition: "$condition"');
      throw FormatException('Invalid condition format: "$condition"');
    }

    final String fieldName = match.group(1)!.trim();
    String operator = match.group(2)!.trim();
    // Normalize operators
    operator = operator.replaceAll('!=', '<>'); // != to <>
    operator = operator.replaceAll('==', '=');  // == to =
    String valueOrField = match.group(3)!.trim();

    debugPrint('[LogicService]   Parsed: $fieldName $operator $valueOrField');

    // Get the actual value of the left-hand side operand from the answers map
    final dynamic leftValue = answers[fieldName];

    // Determine the right-hand side value
    dynamic rightValue;
    if (valueOrField.startsWith("'") && valueOrField.endsWith("'")) {
      // It's a literal string value (quoted)
      rightValue = valueOrField.substring(1, valueOrField.length - 1);
    } else if (int.tryParse(valueOrField) != null || double.tryParse(valueOrField) != null) {
      // It's a numeric literal (not a field name)
      rightValue = valueOrField;
    } else {
      // It's a dynamic value from another field
      rightValue = answers[valueOrField];
    }

    debugPrint('[LogicService]   Values: leftValue="$leftValue" (${leftValue.runtimeType}), rightValue="$rightValue" (${rightValue.runtimeType})');

    // If either value is null, the condition cannot be met
    if (leftValue == null || rightValue == null) {
      debugPrint(
          '[LogicService]   One value is null, returning false.');
      return false;
    }

    final result = _compare(leftValue.toString(), rightValue.toString(), operator);
    debugPrint('[LogicService]   Result: $result');
    return result;
  }

  /// Performs a comparison between two string values based on the operator.
  static bool _compare(String val1, String val2, String operator) {
    final num1 = double.tryParse(val1);
    final num2 = double.tryParse(val2);

    if (num1 != null && num2 != null) {
      // Numeric comparison
      switch (operator) {
        case '=':
        case '==':
          return num1 == num2;
        case '<>':
        case '!=':
          return num1 != num2;
        case '>':
          return num1 > num2;
        case '<':
          return num1 < num2;
        case '>=':
          return num1 >= num2;
        case '<=':
          return num1 <= num2;
        default:
          return false;
      }
    }

    // Try date comparison for ISO date strings
    final date1 = DateTime.tryParse(val1);
    final date2 = DateTime.tryParse(val2);

    if (date1 != null && date2 != null) {
      // Date comparison
      switch (operator) {
        case '=':
        case '==':
          return date1.isAtSameMomentAs(date2);
        case '<>':
        case '!=':
          return !date1.isAtSameMomentAs(date2);
        case '>':
          return date1.isAfter(date2);
        case '<':
          return date1.isBefore(date2);
        case '>=':
          return date1.isAfter(date2) || date1.isAtSameMomentAs(date2);
        case '<=':
          return date1.isBefore(date2) || date1.isAtSameMomentAs(date2);
        default:
          return false;
      }
    }

    // Fall back to string comparison for equality only
    switch (operator) {
      case '=':
      case '==':
        return val1 == val2;
      case '<>':
      case '!=':
        return val1 != val2;
      default:
        return false;
    }
  }
}
