import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import '../models/question.dart';

class CsvDataService {
  // Cache loaded CSV files: filename -> List of rows (each row is a Map<String, String>)
  final Map<String, List<Map<String, String>>> _csvCache = {};

  /// Load a CSV file from the survey directory and cache it
  Future<void> loadCsvFile(String surveyDirectory, String filename) async {
    if (_csvCache.containsKey(filename)) {
      return; // Already loaded
    }

    final filePath = '$surveyDirectory/$filename';
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('CSV file not found: $filePath');
    }

    final csvString = await file.readAsString();
    _csvCache[filename] = parseCsv(csvString);
  }

  /// Parses CSV text into one map per row, keyed by the header names.
  ///
  /// Line endings are normalized before parsing. `CsvToListConverter` does not
  /// detect them on its own, so a file saved on Linux or macOS (LF only) would
  /// otherwise be read as a single row; after the header was removed no data
  /// would remain, and every question backed by that file would silently show
  /// its empty message.
  ///
  /// Every row carries a key for every header, so callers can rely on the
  /// column set without inspecting each row; a value missing from the end of a
  /// short row reads as an empty string.
  ///
  /// This is the single CSV reader for the app: [DbService] uses it when
  /// mirroring CSV files into SQLite, so a file behaves identically whether a
  /// question reads it directly or through a database-backed response list.
  static List<Map<String, String>> parseCsv(String csvString) {
    final normalized =
        csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(normalized);

    if (rows.isEmpty) {
      return [];
    }

    // First row is headers
    final headers = rows[0].map((h) => h.toString().trim()).toList();
    final data = <Map<String, String>>[];

    // Convert each row to a Map
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowMap = <String, String>{};

      for (var j = 0; j < headers.length; j++) {
        rowMap[headers[j]] = j < row.length ? row[j].toString().trim() : '';
      }

      // A trailing newline yields a blank final row; it is not a real record.
      if (rowMap.values.every((value) => value.isEmpty)) {
        continue;
      }

      data.add(rowMap);
    }

    return data;
  }

  /// Load all CSV files referenced in questions
  Future<void> loadAllCsvFiles(
      String surveyDirectory, List<Question> questions) async {
    final csvFiles = <String>{};

    // Collect all unique CSV filenames
    for (final q in questions) {
      if (q.responseConfig?.source == ResponseSource.csv &&
          q.responseConfig?.file != null) {
        csvFiles.add(q.responseConfig!.file!);
      }
    }

    // Load each file
    for (final filename in csvFiles) {
      await loadCsvFile(surveyDirectory, filename);
    }
  }

  /// Get filtered response options from a CSV file
  Future<List<QuestionOption>> getResponseOptions(
    ResponseConfig config,
    Map<String, dynamic> answers,
  ) async {
    if (config.source != ResponseSource.csv || config.file == null) {
      return [];
    }

    final filename = config.file!;
    if (!_csvCache.containsKey(filename)) {
      throw Exception('CSV file not loaded: $filename');
    }

    var data = _csvCache[filename]!;

    // Apply filters
    for (final filter in config.filters) {
      final column = filter.column;
      var filterValue = filter.value;

      // Expand placeholders in filter value (e.g., [[region]])
      filterValue = _expandPlaceholders(filterValue, answers);

      debugPrint(
          '[CsvDataService]   Headers: ${data.isNotEmpty ? data.first.keys.toList() : "empty"}');
      if (data.isNotEmpty) {
        final sampleValues = data.take(5).map((r) => r[column]).toList();
        debugPrint(
            '[CsvDataService]   Sample values for "$column": $sampleValues');
      }

      data = data.where((row) {
        final cellValue = row[column] ?? '';
        return _applyOperator(cellValue, filterValue, filter.operator);
      }).toList();

      debugPrint('[CsvDataService]   After filter: ${data.length} rows');
    }

    // Extract display and value columns
    final displayColumn = config.displayColumn ?? config.valueColumn ?? '';
    final valueColumn = config.valueColumn ?? config.displayColumn ?? '';

    var options = data.map((row) {
      final display = row[displayColumn] ?? '';
      final value = row[valueColumn] ?? '';
      return QuestionOption(value: value, label: display);
    }).toList();

    // Apply distinct if needed
    if (config.distinct) {
      final seen = <String>{};
      options = options.where((opt) {
        final key = '${opt.value}|${opt.label}';
        if (seen.contains(key)) {
          return false;
        }
        seen.add(key);
        return true;
      }).toList();
    }

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

    debugPrint(
        '[CsvDataService] Returning ${options.length} options from ${config.file}');
    if (options.isNotEmpty) {
      debugPrint(
          '[CsvDataService]   Sample: ${options.take(3).map((o) => '${o.value}:${o.label}').join(', ')}${options.length > 3 ? '...' : ''}');
    }

    return options;
  }

  /// Apply comparison operator
  bool _applyOperator(String cellValue, String filterValue, String operator) {
    // Try numeric comparison first
    final cellNum = num.tryParse(cellValue);
    final filterNum = num.tryParse(filterValue);
    if (cellNum != null && filterNum != null) {
      switch (operator) {
        case '=':
          return cellNum == filterNum;
        case '!=':
        case '<>':
          return cellNum != filterNum;
        case '>':
          return cellNum > filterNum;
        case '<':
          return cellNum < filterNum;
        case '>=':
          return cellNum >= filterNum;
        case '<=':
          return cellNum <= filterNum;
      }
    }

    // Try date comparison
    final cellDate = DateTime.tryParse(cellValue);
    final filterDate = DateTime.tryParse(filterValue);
    if (cellDate != null && filterDate != null) {
      switch (operator) {
        case '=':
          return cellDate.isAtSameMomentAs(filterDate);
        case '!=':
        case '<>':
          return !cellDate.isAtSameMomentAs(filterDate);
        case '>':
          return cellDate.isAfter(filterDate);
        case '<':
          return cellDate.isBefore(filterDate);
        case '>=':
          return cellDate.isAfter(filterDate) ||
              cellDate.isAtSameMomentAs(filterDate);
        case '<=':
          return cellDate.isBefore(filterDate) ||
              cellDate.isAtSameMomentAs(filterDate);
      }
    }

    // Default to string comparison
    switch (operator) {
      case '=':
        return cellValue == filterValue;
      case '!=':
      case '<>':
        return cellValue != filterValue;
      case '>':
        return cellValue.compareTo(filterValue) > 0;
      case '<':
        return cellValue.compareTo(filterValue) < 0;
      case '>=':
        return cellValue.compareTo(filterValue) >= 0;
      case '<=':
        return cellValue.compareTo(filterValue) <= 0;
      default:
        return false;
    }
  }

  /// Expand placeholders like [[region]] with actual values
  String _expandPlaceholders(String template, Map<String, dynamic> answers) {
    return template.replaceAllMapped(RegExp(r'\[\[(.+?)\]\]'), (m) {
      final key = m.group(1)!;
      final val = answers[key];
      if (val == null) return '';
      if (val is List) return val.join(', ');
      return val.toString();
    });
  }

  /// Clear the cache
  void clearCache() {
    _csvCache.clear();
  }
}
