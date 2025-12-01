import '../models/question.dart';
import 'db_service.dart';

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
      throw Exception('display and value columns must be specified for database source');
    }

    // Build WHERE clause from filters
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    for (final filter in config.filters) {
      var filterValue = filter.value;

      // Expand placeholders in filter value (e.g., [[region]])
      filterValue = _expandPlaceholders(filterValue, answers);

      whereClauses.add('${filter.column} ${filter.operator} ?');
      whereArgs.add(filterValue);
    }

    final whereClause = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

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

  /// Expand placeholders like [[region]] with actual values
  static String _expandPlaceholders(String template, Map<String, dynamic> answers) {
    return template.replaceAllMapped(RegExp(r'\[\[(.+?)\]\]'), (m) {
      final key = m.group(1)!;
      final val = answers[key];
      if (val == null) return '';
      if (val is List) return val.join(', ');
      return val.toString();
    });
  }
}
