import 'dart:io';
import 'package:csv/csv.dart';
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
    final rows = const CsvToListConverter().convert(csvString);

    if (rows.isEmpty) {
      _csvCache[filename] = [];
      return;
    }

    // First row is headers
    final headers = rows[0].map((h) => h.toString().trim()).toList();
    final data = <Map<String, String>>[];

    // Convert each row to a Map
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowMap = <String, String>{};

      for (var j = 0; j < headers.length && j < row.length; j++) {
        rowMap[headers[j]] = row[j].toString().trim();
      }

      data.add(rowMap);
    }

    _csvCache[filename] = data;
  }

  /// Load all CSV files referenced in questions
  Future<void> loadAllCsvFiles(String surveyDirectory, List<Question> questions) async {
    final csvFiles = <String>{};

    // Collect all unique CSV filenames
    for (final q in questions) {
      if (q.responseConfig?.source == ResponseSource.csv && q.responseConfig?.file != null) {
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

      data = data.where((row) {
        final cellValue = row[column] ?? '';
        return _applyOperator(cellValue, filterValue, filter.operator);
      }).toList();
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

    return options;
  }

  /// Apply comparison operator
  bool _applyOperator(String cellValue, String filterValue, String operator) {
    switch (operator) {
      case '=':
        return cellValue == filterValue;
      case '!=':
      case '<>':
        return cellValue != filterValue;
      case '>':
        final cell = num.tryParse(cellValue);
        final filter = num.tryParse(filterValue);
        if (cell != null && filter != null) {
          return cell > filter;
        }
        return cellValue.compareTo(filterValue) > 0;
      case '<':
        final cell = num.tryParse(cellValue);
        final filter = num.tryParse(filterValue);
        if (cell != null && filter != null) {
          return cell < filter;
        }
        return cellValue.compareTo(filterValue) < 0;
      case '>=':
        final cell = num.tryParse(cellValue);
        final filter = num.tryParse(filterValue);
        if (cell != null && filter != null) {
          return cell >= filter;
        }
        return cellValue.compareTo(filterValue) >= 0;
      case '<=':
        final cell = num.tryParse(cellValue);
        final filter = num.tryParse(filterValue);
        if (cell != null && filter != null) {
          return cell <= filter;
        }
        return cellValue.compareTo(filterValue) <= 0;
      default:
        return cellValue == filterValue;
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
