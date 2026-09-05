// lib/services/logic_service.dart
import 'package:flutter/foundation.dart';
import '../models/question.dart';
import 'field_comparator.dart';

/// Service for evaluating logic check expressions in survey questions.
///
/// Supports complex boolean expressions with AND/OR operators and parentheses.
/// Automatically detects value types (numeric, date, or string) for comparisons.
///
/// Multiple Logic Checks:
///   Questions can have multiple `<logic_check>` elements.
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

    // Regex to capture: (field_name) contains|does not contain (value)
    // Used for checkbox (multi-select) fields, whose answer is a List.
    final containsRegex = RegExp(
        r"^\s*([\w_]+)\s+(contains|does not contain)\s+('[^']+'|-?\d+(?:\.\d+)?|[\w_]+)\s*$",
        caseSensitive: false);
    final containsMatch = containsRegex.firstMatch(condition);
    if (containsMatch != null) {
      return _evaluateParsedCondition(
        fieldName: containsMatch.group(1)!.trim(),
        operator: containsMatch.group(2)!.trim().toLowerCase(),
        valueOrField: containsMatch.group(3)!.trim(),
        answers: answers,
      );
    }

    // Regex to capture: (field_name) (operator) (value)
    // The value can be a quoted string (with any characters), a numeric literal
    // (including negatives like -7 and decimals), or a field name.
    // Handles operators like =, <>, <=, >=, <, >
    final regex = RegExp(
        r"^\s*([\w_]+)\s*([<>=!]+)\s*('[^']+'|-?\d+(?:\.\d+)?|[\w_]+)\s*$");
    final match = regex.firstMatch(condition);

    if (match == null) {
      debugPrint(
          '[LogicService]   ERROR: Failed to parse condition: "$condition"');
      throw FormatException('Invalid condition format: "$condition"');
    }

    return _evaluateParsedCondition(
      fieldName: match.group(1)!.trim(),
      operator: match.group(2)!.trim(),
      valueOrField: match.group(3)!.trim(),
      answers: answers,
    );
  }

  /// Resolves [fieldName] and [valueOrField] against [answers] and evaluates
  /// the comparison. Shared by both the symbolic-operator path (=, <>, ...)
  /// and the contains/does not contain path -- they parse their operator and
  /// their right-hand side identically, and previously duplicated that
  /// resolution with a subtle difference: only the general path treated an
  /// unresolved field-vs-field comparison as automatically false. Both now
  /// do, since a check that cannot be evaluated should not block navigation
  /// either way.
  static bool _evaluateParsedCondition({
    required String fieldName,
    required String operator,
    required String valueOrField,
    required AnswerMap answers,
  }) {
    final dynamic leftRaw = answers[fieldName];

    final dynamic rightRaw;
    if (valueOrField.startsWith("'") && valueOrField.endsWith("'")) {
      // It's a literal string value (quoted) - could be a date or regular string
      rightRaw = valueOrField.substring(1, valueOrField.length - 1);
    } else if (int.tryParse(valueOrField) != null ||
        double.tryParse(valueOrField) != null) {
      // It's a numeric literal (not a field name)
      rightRaw = valueOrField;
    } else {
      // It's a dynamic value from another field
      rightRaw = answers[valueOrField];
    }

    debugPrint('[LogicService]   Parsed: $fieldName $operator $valueOrField');
    debugPrint(
        '[LogicService]   Values: leftValue="$leftRaw" (${leftRaw.runtimeType}), rightValue="$rightRaw" (${rightRaw.runtimeType})');

    // If either value is null, the condition cannot be met
    if (leftRaw == null || rightRaw == null) {
      debugPrint('[LogicService]   One value is null, returning false.');
      return false;
    }

    final result = FieldComparator.compare(
      FieldComparator.resolveText(leftRaw)!,
      operator,
      FieldComparator.resolveText(rightRaw)!,
    );
    debugPrint('[LogicService]   Result: $result');
    return result;
  }
}
