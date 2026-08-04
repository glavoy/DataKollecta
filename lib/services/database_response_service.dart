import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'db_service.dart';

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

    // Build WHERE clause from filters
    final filterSql = buildWhere(config.filters, answers);
    final whereClause = filterSql.whereClause;
    final whereArgs = filterSql.whereArgs;

    // Build query with DISTINCT if needed
    String query;
    if (config.distinct) {
      query = 'SELECT DISTINCT $displayColumn, $valueColumn FROM $table';
      if (whereClause != null) {
        query += ' WHERE $whereClause';
      }
    } else {
      query = 'SELECT $displayColumn, $valueColumn FROM $table';
      if (whereClause != null) {
        query += ' WHERE $whereClause';
      }
    }

    final results = await db.rawQuery(query, whereArgs);

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
      final operator =
          filter.operator.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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
              'CAST(${filter.column} AS INTEGER) $sqlOperator ($placeholders)');
        } else {
          final placeholders = List.filled(items.length, '?').join(', ');
          whereClauses.add('${filter.column} $sqlOperator ($placeholders)');
        }
        whereArgs.addAll(items);
        continue;
      }

      // Use CAST for numeric comparison if the filter value looks like a number
      // this handles padding differences (e.g., '04' matching '4')
      if (num.tryParse(filterValue) != null &&
          (filter.operator == '=' ||
              filter.operator == '!=' ||
              filter.operator == '<>')) {
        whereClauses.add(
            'CAST(${filter.column} AS INTEGER) ${filter.operator} CAST(? AS INTEGER)');
      } else {
        whereClauses.add('${filter.column} ${filter.operator} ?');
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
