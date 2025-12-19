// lib/services/logic_service.dart
import 'package:flutter/foundation.dart';
import '../models/question.dart';

/// Service for evaluating logic check expressions in survey questions.
///
/// Supports complex boolean expressions with AND/OR operators and parentheses.
/// Automatically detects value types (numeric, date, or string) for comparisons.
///
/// Multiple Logic Checks:
///   Questions can have multiple <logic_check> elements.
///   They are evaluated sequentially in order.
///   The first check that fails returns its error message.
///   Subsequent checks are skipped.
///
/// Date Comparison Examples:
///   - starttime <= '2026-01-31'  (datetime field vs date literal)
///   - dob < vx_dose1_date        (date field vs date field)
///   - date1 >= '2025-12-19T14:30:00'  (datetime literal)
///
/// Supported date formats:
///   - Date only: '2026-01-31' (assumes midnight/00:00)
///   - ISO 8601: '2025-12-19T14:30:00' or '2025-12-19T14:30:00.000Z'
class LogicService {
  /// Evaluates all logic check expressions for a given question.
  /// Checks are evaluated sequentially in order.
  /// Returns the error message from the first check that fails, otherwise null.
  /// If a check fails, subsequent checks are not evaluated.
  static String? evaluateLogicChecks(Question question, AnswerMap answers) {
    final logicChecks = question.logicChecks;
    if (logicChecks.isEmpty) {
      return null;
    }

    // Evaluate each logic check in order
    for (final logicCheck in logicChecks) {
      try {
        // The condition is already separated in the LogicCheck object
        final String conditionStr = logicCheck.condition;
        final String message = logicCheck.message;

        // Evaluate the expression
        final bool result = _evaluateExpression(conditionStr, answers);

        debugPrint(
            '[LogicService] Evaluating logic for ${question.fieldName}: "$conditionStr" --> $result');

        // If the expression is true, the check has failed, so return the message
        // Don't evaluate subsequent checks
        if (result) {
          return message;
        }
      } catch (e) {
        debugPrint(
            '[LogicService] Error evaluating expression: "${logicCheck.condition}". Error: $e');
        // Return error message to be visible in UI for debugging
        return 'Error in logic check expression: $e';
      }
    }

    return null;
  }

  /// Evaluates a boolean expression string with AND and OR clauses.
  static bool _evaluateExpression(String expression, AnswerMap answers) {
    expression = expression.trim();

    // Remove all outer matching parentheses
    expression = _removeOuterParentheses(expression);

    // Split on OR (lowest precedence) respecting parentheses
    final orClauses = _splitRespectingParentheses(expression, 'or');
    for (var orClause in orClauses) {
      orClause = orClause.trim();

      // Split on AND (higher precedence) respecting parentheses
      final andClauses = _splitRespectingParentheses(orClause, 'and');
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

  /// Removes all outer matching parentheses from an expression.
  /// Example: "(((a = 1)))" becomes "a = 1"
  static String _removeOuterParentheses(String expr) {
    expr = expr.trim();
    while (expr.startsWith('(') && expr.endsWith(')')) {
      // Check if these are matching outer parentheses
      int depth = 0;
      bool isOuterPair = true;
      for (int i = 0; i < expr.length; i++) {
        if (expr[i] == '(') {
          depth++;
        } else if (expr[i] == ')') {
          depth--;
          // If depth reaches 0 before the end, the outer parens don't match
          if (depth == 0 && i < expr.length - 1) {
            isOuterPair = false;
            break;
          }
        }
      }
      if (isOuterPair) {
        expr = expr.substring(1, expr.length - 1).trim();
      } else {
        break;
      }
    }
    return expr;
  }

  /// Splits an expression by a keyword (AND/OR) while respecting parentheses.
  /// Only splits at the keyword when parentheses depth is 0.
  static List<String> _splitRespectingParentheses(String expr, String keyword) {
    final parts = <String>[];
    final pattern = RegExp(r'\s+' + keyword + r'\s+', caseSensitive: false);

    int depth = 0;
    int lastSplit = 0;

    for (int i = 0; i < expr.length; i++) {
      if (expr[i] == '(') {
        depth++;
      } else if (expr[i] == ')') {
        depth--;
      } else if (depth == 0) {
        // Check if we're at a keyword boundary
        final match = pattern.matchAsPrefix(expr, i);
        if (match != null) {
          // Found a keyword at depth 0
          parts.add(expr.substring(lastSplit, i).trim());
          i = match.end - 1; // Move past the keyword (loop will increment)
          lastSplit = match.end;
        }
      }
    }

    // Add the remaining part
    if (lastSplit < expr.length) {
      parts.add(expr.substring(lastSplit).trim());
    }

    // If no splits occurred, return the whole expression
    return parts.isEmpty ? [expr] : parts;
  }

  /// Checks if an expression contains 'and' or 'or' at parentheses depth 0.
  static bool _containsLogicalOperator(String expr) {
    final pattern = RegExp(r'\s+(and|or)\s+', caseSensitive: false);
    int depth = 0;

    for (int i = 0; i < expr.length; i++) {
      if (expr[i] == '(') {
        depth++;
      } else if (expr[i] == ')') {
        depth--;
      } else if (depth == 0) {
        final match = pattern.matchAsPrefix(expr, i);
        if (match != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Evaluates a single condition like "field = 'value'" or "field1 <> field2"
  static bool _evaluateSingleCondition(String condition, AnswerMap answers) {
    condition = condition.trim();

    // Remove outer parentheses
    condition = _removeOuterParentheses(condition);

    debugPrint('[LogicService]   Evaluating single condition: "$condition"');

    // Check if this is still a compound expression (contains 'and' or 'or' at depth 0)
    // If so, recursively evaluate it
    if (_containsLogicalOperator(condition)) {
      return _evaluateExpression(condition, answers);
    }

    // Regex to capture: (field_name) (operator) (value)
    // The value can be a quoted string (with any characters), or a field name.
    // Handles operators like =, <>, <=, >=, <, >
    final regex = RegExp(r"^\s*([\w_]+)\s*([<>=!]+)\s*('[^']+'|[\w_]+)\s*$");
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
      // It's a literal string value (quoted) - could be a date or regular string
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
  /// Automatically detects and handles numeric, date (ISO format), or string comparisons.
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

    // Try date comparison for ISO date strings (e.g., '2026-01-31', '2025-12-19T14:30:00')
    // Works with both date-only (YYYY-MM-DD) and datetime (ISO 8601) formats
    final date1 = DateTime.tryParse(val1);
    final date2 = DateTime.tryParse(val2);

    if (date1 != null && date2 != null) {
      // Date/DateTime comparison
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
