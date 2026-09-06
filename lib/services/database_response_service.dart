import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'db_service.dart';
import 'survey_table_schema.dart';

/// A SQL WHERE fragment built from a question's response filters.
class ResponseFilterSql {
  /// The WHERE clause without the `WHERE` keyword, or null when unfiltered.
  final String? whereClause;
  final List<dynamic> whereArgs;

  const ResponseFilterSql(this.whereClause, this.whereArgs);
}

class DatabaseResponseService {
  /// Get filtered response options from a database table
  static Future<List<QuestionOption>> getResponseOptions(
    String surveyId,
    ResponseConfig config,
    Map<String, dynamic> answers,
  ) async {
    if (config.source != ResponseSource.database || config.table == null) {
      return [];
    }

    final db = await DbService.getDatabaseForQueries(surveyId);

    final table = config.table!;
    final displayColumn = config.displayColumn ?? config.valueColumn ?? '';
    final valueColumn = config.valueColumn ?? config.displayColumn ?? '';

    if (displayColumn.isEmpty || valueColumn.isEmpty) {
      throw Exception(
          'display and value columns must be specified for database source');
    }

    // These three came from <responses table>, <display column> and
    // <value column>, and SurveyLoader has already held them to
    // SurveyTableSchema.validateIdentifier. They are quoted anyway: this is
    // the largest hand-written SELECT in the app and the only one whose
    // identifiers are attributes rather than a schema the app controls, so it
    // should not be the one place that depends on a check made elsewhere.
    final quotedTable = SurveyTableSchema.quoteIdentifier(table);
    final quotedDisplay = SurveyTableSchema.quoteIdentifier(displayColumn);
    final quotedValue = SurveyTableSchema.quoteIdentifier(valueColumn);

    // Build WHERE clause from filters
    final filterSql = buildWhere(config.filters, answers);
    final whereClause = filterSql.whereClause;
    final whereArgs = filterSql.whereArgs;

    // Build query with DISTINCT if needed
    final select = config.distinct ? 'SELECT DISTINCT' : 'SELECT';
    var query = '$select $quotedDisplay, $quotedValue FROM $quotedTable';
    if (whereClause != null) {
      query += ' WHERE $whereClause';
    }

    final results = await db.rawQuery(query, whereArgs);

    // Bare names, not the quoted ones: quoting is SQL syntax, and sqflite
    // keys the returned row by the column's actual name.
    final options = results.map((row) {
      final display = row[displayColumn]?.toString() ?? '';
      final value = row[valueColumn]?.toString() ?? '';
      return QuestionOption(value: value, label: display);
    }).toList();

    // Add optional special options
    if (config.dontKnowValue != null && config.dontKnowLabel != null) {
      options.add(QuestionOption(
        value: config.dontKnowValue!,
        label: config.dontKnowLabel!,
      ));
    }

    if (config.notInListValue != null && config.notInListLabel != null) {
      options.add(QuestionOption(
        value: config.notInListValue!,
        label: config.notInListLabel!,
      ));
    }

    return options;
  }

  /// Builds the WHERE clause and bound arguments for a set of response filters.
  ///
  /// Besides the simple comparison operators, `in` and `not in` treat the
  /// filter value as a comma-separated list, so a field holding something like
  /// `2,3,4` can include or exclude several rows at once.
  ///
  /// Public to allow filter SQL to be verified without opening a survey
  /// database.
  /// Every comparison a `<filter>` may ask for, and nothing else.
  ///
  /// The operator is the one part of a filter that cannot be a bound parameter
  /// and cannot be an identifier either, so neither `?` nor
  /// [SurveyTableSchema.quoteIdentifier] can protect it -- it was interpolated
  /// into the WHERE clause verbatim. An allowlist is the only thing that can:
  /// the value is not sanitized, it is *replaced* by the matching entry here
  /// or refused.
  static const Map<String, String> _operators = {
    '=': '=',
    '==': '=',
    '!=': '!=',
    '<>': '<>',
    '<': '<',
    '>': '>',
    '<=': '<=',
    '>=': '>=',
    'in': 'in',
    'not in': 'not in',
  };

  /// [operator] as SQL, or a throw.
  ///
  /// Spelling differences are absorbed the same way `FieldComparator` absorbs
  /// them, so a dictionary that writes `&gt;=` or `NOT  IN` keeps working: XML
  /// entity decoding first (an attribute value may arrive still encoded),
  /// then trim, lowercase and collapse runs of whitespace.
  static String _sqlOperator(String operator) {
    final normalized = operator
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final sql = _operators[normalized];
    if (sql == null) {
      throw ArgumentError.value(operator, 'operator',
          'Unsupported <filter> operator. Use one of: ${_operators.keys.join(', ')}');
    }
    return sql;
  }

  @visibleForTesting
  static ResponseFilterSql buildWhere(
    List<ResponseFilter> filters,
    Map<String, dynamic> answers,
  ) {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    for (final filter in filters) {
      // Expand placeholders in filter value (e.g., [[region]])
      final filterValue = _expandPlaceholders(filter.value, answers);

      // Normalize "NOT  IN" and similar spellings before matching
      final operator = _sqlOperator(filter.operator);
      final column = SurveyTableSchema.quoteIdentifier(filter.column);

      if (operator == 'in' || operator == 'not in') {
        final items = filterValue
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();

        // An empty list is the normal case for the first record of a repeating
        // section, before anything has been selected. Handle it here rather
        // than emitting `IN ()`, which is a SQLite extension other engines
        // reject. The meaning is unambiguous: "in nothing" matches no rows,
        // "not in nothing" excludes nothing, so no clause is needed.
        if (items.isEmpty) {
          if (operator == 'in') {
            whereClauses.add('1 = 0');
          }
          continue;
        }

        final sqlOperator = operator == 'in' ? 'IN' : 'NOT IN';

        // Compare numerically where possible, matching the '=' handling below,
        // so padding differences (e.g. '04' matching '4') don't cause misses.
        if (items.every((item) => num.tryParse(item) != null)) {
          final placeholders =
              List.filled(items.length, 'CAST(? AS INTEGER)').join(', ');
          whereClauses.add(
              'CAST($column AS INTEGER) $sqlOperator ($placeholders)');
        } else {
          final placeholders = List.filled(items.length, '?').join(', ');
          whereClauses.add('$column $sqlOperator ($placeholders)');
        }
        whereArgs.addAll(items);
        continue;
      }

      // Use CAST for numeric comparison if the filter value looks like a number
      // this handles padding differences (e.g., '04' matching '4')
      if (num.tryParse(filterValue) != null &&
          (operator == '=' || operator == '!=' || operator == '<>')) {
        whereClauses.add(
            'CAST($column AS INTEGER) $operator CAST(? AS INTEGER)');
      } else {
        whereClauses.add('$column $operator ?');
      }
      whereArgs.add(filterValue);
    }

    return ResponseFilterSql(
      whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
      whereArgs,
    );
  }

  /// Expand placeholders like [[region]] with actual values
  static String _expandPlaceholders(
      String template, Map<String, dynamic> answers) {
    return template.replaceAllMapped(RegExp(r'\[\[(.+?)\]\]'), (m) {
      final key = m.group(1)!;
      final val = answers[key];
      if (val == null) return '';
      if (val is List) return val.join(', ');
      return val.toString();
    });
  }
}
