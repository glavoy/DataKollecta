// lib/services/db_service.dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/question.dart';
import '../config/app_config.dart';

class DbService {
  static Database? _db;

  /// Call once at app start
  static Future<void> init() async {
    try {
      // Initialize FFI for desktop platforms
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      // Set database path
      final dbPath = AppConfig.customDatabasePath ??
          p.join((await getApplicationSupportDirectory()).path,
              AppConfig.databaseFilename);
      _log('Using database path: $dbPath');

      // Open the database (will fail if file doesn't exist)
      _db = await openDatabase(dbPath);
    } catch (e) {
      _logError('Failed to initialize database: $e');
      rethrow;
    }
  }

  /// Get the current database path
  static String? get databasePath => _db?.path;

  /// Save one completed interview's answers to the survey-specific table.
  /// The table name is derived from the survey XML filename (without .xml extension).
  ///
  /// - `surveyFilename`: the XML filename (e.g., 'survey.xml')
  /// - `answers`: in-memory AnswerMap (fieldname -> value)
  static Future<void> saveInterview({
    required String surveyFilename,
    required AnswerMap answers,
  }) async {
    final db = _db!;

    // Derive table name from filename: remove .xml extension
    final tableName = surveyFilename.toLowerCase().replaceAll('.xml', '');

    try {
      // Check if table exists first
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        final errorMsg =
            'Table "$tableName" does not exist in database.\n\nExpected table name: $tableName\nDatabase path: ${databasePath}\n\nPlease create this table using your external application before conducting surveys.';
        _logError(errorMsg);
        throw DatabaseException(errorMsg);
      }

      // Build the column:value map from answers
      // Convert special types to database-friendly formats
      final Map<String, dynamic> rowData = {};

      for (final entry in answers.entries) {
        final key = entry.key;
        final val = entry.value;
        if (val == null) continue;

        // Store the value based on its runtime type
        if (val is List) {
          // Checkbox values - store as comma-separated
          rowData[key] = val.map((e) => e.toString()).join(',');
        } else if (val is DateTime) {
          // DateTime values - store as ISO8601 string
          rowData[key] = val.toIso8601String();
        } else {
          // Everything else (String, int, etc.) - store as-is
          rowData[key] = val;
        }
      }

      // Insert or replace the row
      await db.insert(
        tableName,
        rowData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      final errorMsg =
          'Failed to save interview to table "$tableName": $e\n\nDatabase: ${databasePath}';
      _logError(errorMsg);
      throw DatabaseException(errorMsg);
    }
  }

  /// Check if a table exists in the database
  static Future<bool> _tableExists(String tableName) async {
    if (_db == null) return false;

    try {
      final result = await _db!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      return result.isNotEmpty;
    } catch (e) {
      _logError('Error checking if table exists: $e');
      return false;
    }
  }

  /// Get the primary key field(s) for a survey from the CRFs table
  /// Returns a list of field names (empty list if not found or error)
  static Future<List<String>> getPrimaryKeyFields(String tableName) async {
    if (_db == null) {
      _logError('Database not initialized');
      return [];
    }

    try {
      final result = await _db!.query(
        'crfs',
        columns: ['primarykey'],
        where: 'tablename = ?',
        whereArgs: [tableName],
      );

      if (result.isEmpty) {
        _logError('No primary key definition found for table: $tableName');
        return [];
      }

      // Primary key can be comma-separated for composite keys (e.g., "subjid,date")
      final pkString = result.first['primarykey'] as String;
      return pkString.split(',').map((s) => s.trim()).toList();
    } catch (e) {
      _logError('Error fetching primary key for $tableName: $e');
      return [];
    }
  }

  /// Get all existing records from a survey table
  /// Returns a list of maps, each containing the full record data
  static Future<List<Map<String, dynamic>>> getExistingRecords(
      String tableName) async {
    if (_db == null) {
      _logError('Database not initialized');
      return [];
    }

    try {
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        _logError('Table $tableName does not exist');
        return [];
      }

      final results = await _db!.query(tableName);
      _log('Found ${results.length} records in $tableName');
      return results;
    } catch (e) {
      _logError('Error fetching records from $tableName: $e');
      return [];
    }
  }

  /// Get a specific record by uniqueid
  /// Returns the record data or null if not found
  static Future<Map<String, dynamic>?> getRecordByUniqueId(
      String tableName, String uniqueId) async {
    if (_db == null) {
      _logError('Database not initialized');
      return null;
    }

    try {
      final results = await _db!.query(
        tableName,
        where: 'uniqueid = ?',
        whereArgs: [uniqueId],
      );

      if (results.isEmpty) {
        _log('No record found with uniqueid: $uniqueId');
        return null;
      }

      return results.first;
    } catch (e) {
      _logError('Error fetching record by uniqueid: $e');
      return null;
    }
  }

  /// Update an existing interview record
  /// Uses uniqueid to identify the record to update
  /// Also records all changes in the formchanges table
  static Future<void> updateInterview({
    required String surveyFilename,
    required AnswerMap answers,
    required String uniqueId,
    required Map<String, dynamic>? originalAnswers,
  }) async {
    final db = _db!;
    final tableName = surveyFilename.toLowerCase().replaceAll('.xml', '');

    try {
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        throw DatabaseException(
            'Table "$tableName" does not exist in database.');
      }

      // Get existing columns in the table
      final existingColumns = await _getTableColumns(tableName);
      _log('Table $tableName has columns: ${existingColumns.join(", ")}');

      // Build the column:value map from answers
      final Map<String, dynamic> rowData = {};

      for (final entry in answers.entries) {
        final key = entry.key;
        final val = entry.value;

        // Only include columns that exist in the table
        if (!existingColumns.contains(key.toLowerCase())) {
          _log('Skipping field "$key" - not found in table');
          continue;
        }

        // Handle null values (for clearing skipped questions)
        if (val == null) {
          rowData[key] = null;
          continue;
        }

        if (val is List) {
          rowData[key] = val.map((e) => e.toString()).join(',');
        } else if (val is DateTime) {
          rowData[key] = val.toIso8601String();
        } else {
          rowData[key] = val;
        }
      }

      if (rowData.isEmpty) {
        throw DatabaseException('No valid fields to update');
      }

      _log('Updating record with fields: ${rowData.keys.join(", ")}');

      // Record changes in formchanges table
      if (originalAnswers != null) {
        await _recordChanges(
          tableName: tableName,
          uniqueId: uniqueId,
          originalAnswers: originalAnswers,
          newAnswers: answers,
          existingColumns: existingColumns,
        );
      }

      // Update the record by uniqueid
      final updateCount = await db.update(
        tableName,
        rowData,
        where: 'uniqueid = ?',
        whereArgs: [uniqueId],
      );

      if (updateCount == 0) {
        throw DatabaseException(
            'Failed to update record: no record found with uniqueid=$uniqueId');
      }

      _log('Updated $updateCount record(s) in $tableName with uniqueid=$uniqueId');
    } catch (e) {
      final errorMsg = 'Failed to update interview in "$tableName": $e';
      _logError(errorMsg);
      throw DatabaseException(errorMsg);
    }
  }

  /// Record field changes in the formchanges table
  /// Compares original and new answers and inserts one record per changed field
  static Future<void> _recordChanges({
    required String tableName,
    required String uniqueId,
    required Map<String, dynamic> originalAnswers,
    required AnswerMap newAnswers,
    required List<String> existingColumns,
  }) async {
    final db = _db!;
    int changeCount = 0;

    try {
      // Check if formchanges table exists
      final formChangesExists = await _tableExists('formchanges');
      if (!formChangesExists) {
        _logError('formchanges table does not exist - skipping change tracking');
        return;
      }

      for (final entry in newAnswers.entries) {
        final fieldName = entry.key;
        final newValue = entry.value;

        // Skip fields that don't exist in the table
        if (!existingColumns.contains(fieldName.toLowerCase())) {
          continue;
        }

        // Get old value
        final oldValue = originalAnswers[fieldName];

        // Convert values to string for comparison and storage
        final oldValueStr = _valueToString(oldValue);
        final newValueStr = _valueToString(newValue);

        // Only record if values are different
        if (oldValueStr != newValueStr) {
          await db.insert('formchanges', {
            'tablename': tableName,
            'fieldname': fieldName,
            'uniqueid': uniqueId,
            'oldvalue': oldValueStr,
            'newvalue': newValueStr,
            'changed_at': DateTime.now().toIso8601String(),
          });
          changeCount++;
          _log('Recorded change: $fieldName from "$oldValueStr" to "$newValueStr"');
        }
      }

      _log('Recorded $changeCount field changes in formchanges table');
    } catch (e) {
      _logError('Error recording changes: $e');
      // Don't throw - we don't want change tracking failure to prevent the update
    }
  }

  /// Convert a value to string for comparison and storage
  static String? _valueToString(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).join(',');
    } else if (value is DateTime) {
      return value.toIso8601String();
    } else {
      return value.toString();
    }
  }

  /// Get all column names for a table
  static Future<List<String>> _getTableColumns(String tableName) async {
    if (_db == null) return [];

    try {
      final result = await _db!.rawQuery('PRAGMA table_info($tableName)');
      final columns = result.map((row) => (row['name'] as String).toLowerCase()).toList();
      return columns;
    } catch (e) {
      _logError('Error getting table columns: $e');
      return [];
    }
  }

  // Logging helpers
  static void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[DbService] $message');
    }
  }

  static void _logError(String message) {
    debugPrint('[DbService ERROR] $message');
  }
}

/// Custom exception for database errors
class DatabaseException implements Exception {
  final String message;

  DatabaseException(this.message);

  @override
  String toString() => message;
}
