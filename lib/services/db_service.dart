import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../models/question.dart';
import 'survey_loader.dart';

class DbService {
  static Database? _db;

  /// Call once at app start
  static Future<void> init() async {
    try {
      // Initialize FFI for desktop platforms
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Determine the database path
      String dbPath;
      if (AppConfig.customDatabasePath != null) {
        // Use custom path (Windows)
        dbPath = AppConfig.customDatabasePath!;
      } else {
        // Use default internal path (Android/iOS)
        final dir = await getApplicationDocumentsDirectory();
        dbPath = p.join(dir.path, AppConfig.databaseFilename);
      }

      _log('Using database path: $dbPath');

      // Check if we need to copy from assets (Mobile only usually, or if custom path missing)
      // For Windows with custom path, we assume the file exists at that location as per user setup.
      // For Android, we must copy it from assets if it doesn't exist in app docs.
      if (AppConfig.customDatabasePath == null) {
        if (!await File(dbPath).exists()) {
          _log('Database not found at $dbPath. Copying from assets...');
          try {
            // Ensure parent directory exists
            await Directory(p.dirname(dbPath)).create(recursive: true);

            // Copy from assets
            final data =
                await rootBundle.load('assets/database/fake_survey.sqlite');
            final bytes =
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
            await File(dbPath).writeAsBytes(bytes, flush: true);
            _log('Database copied successfully.');
          } catch (e) {
            _logError('Failed to copy database from assets: $e');
            // Fallback: let openDatabase create an empty one if copying fails?
            // Or rethrow? Rethrowing is safer as we need the schema.
            rethrow;
          }
        }
      }

      // Open the database
      _db = await openDatabase(dbPath);

      // Sync database schema with XML definitions
      await _syncDatabaseSchema();
    } catch (e) {
      _logError('Failed to initialize database: $e');
      rethrow;
    }
  }

  /// Sync the database schema with the XML survey definitions
  static Future<void> _syncDatabaseSchema() async {
    try {
      _log('Starting database schema sync...');

      // Load AssetManifest to find all XML files in assets/surveys/
      // Load AssetManifest to find all XML files in assets/surveys/
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

      final surveyFiles = manifest
          .listAssets()
          .where((String key) =>
              key.startsWith('assets/surveys/') && key.endsWith('.xml'))
          .toList();

      _log('Found ${surveyFiles.length} survey files: $surveyFiles');

      for (final assetPath in surveyFiles) {
        final filename = p.basename(assetPath);
        final tableName = filename.toLowerCase().replaceAll('.xml', '');

        _log('Checking schema for $tableName ($filename)...');

        // Load questions
        final questions = await SurveyLoader.loadFromAsset(assetPath);

        // Filter data questions
        final dataQuestions =
            questions.where((q) => q.type != QuestionType.information).toList();
        _log('Loaded ${dataQuestions.length} data questions for $tableName');

        if (dataQuestions.isEmpty) continue;

        // Check if table exists
        final tableExists = await _tableExists(tableName);

        if (!tableExists) {
          _log('Table $tableName does not exist. Creating...');
          // Create table with data questions
          final buffer = StringBuffer();
          buffer.write('CREATE TABLE $tableName (');

          final colDefs = <String>[];
          for (final q in dataQuestions) {
            colDefs.add('${q.fieldName} ${_getSqlType(q)}');
          }

          buffer.write(colDefs.join(', '));
          buffer.write(')');

          await _db!.execute(buffer.toString());
          _log('Table $tableName created.');
        } else {
          // Table exists, check columns
          final existingColumns = await _getTableColumns(tableName);
          _log('Existing columns in $tableName: $existingColumns');

          for (final q in dataQuestions) {
            if (!existingColumns.contains(q.fieldName.toLowerCase())) {
              _log('Column ${q.fieldName} missing in $tableName. Adding...');
              final sqlType = _getSqlType(q);
              try {
                await _db!.execute(
                    'ALTER TABLE $tableName ADD COLUMN ${q.fieldName} $sqlType');
                _log('Successfully added column ${q.fieldName}');
              } catch (e) {
                _logError('Failed to add column ${q.fieldName}: $e');
              }
            }
          }
        }
      }
      _log('Database schema sync completed.');
    } catch (e) {
      _logError('Error syncing schema: $e');
    }
  }

  static String _getSqlType(Question q) {
    final ft = q.fieldType.toLowerCase();
    if (ft == 'integer' || ft == 'text_integer') {
      return 'INTEGER';
    } else if (ft == 'text_decimal' || ft == 'real') {
      return 'REAL';
    } else {
      return 'TEXT';
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

  /// Get the next linenum for a specific primary key value
  /// Returns 1 if no records exist, otherwise returns max(linenum) + 1
  /// primaryKeyField: the name of the primary key field (e.g., 'hhid')
  /// primaryKeyValue: the value to filter by (e.g., 'SP01001')
  static Future<int> getNextLineNum({
    required String tableName,
    required String primaryKeyField,
    required String primaryKeyValue,
  }) async {
    if (_db == null) {
      _logError('Database not initialized');
      return 1;
    }

    try {
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        _logError('Table $tableName does not exist');
        return 1;
      }

      // Query for the maximum linenum where primary key matches
      final results = await _db!.rawQuery(
        'SELECT MAX(linenum) as maxLineNum FROM $tableName WHERE $primaryKeyField = ?',
        [primaryKeyValue],
      );

      if (results.isEmpty || results.first['maxLineNum'] == null) {
        _log('No existing records for $primaryKeyField=$primaryKeyValue, returning linenum=1');
        return 1;
      }

      final maxLineNum = results.first['maxLineNum'] as int;
      final nextLineNum = maxLineNum + 1;
      _log('Found max linenum=$maxLineNum for $primaryKeyField=$primaryKeyValue, returning $nextLineNum');
      return nextLineNum;
    } catch (e) {
      _logError('Error getting next linenum for $tableName: $e');
      return 1;
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

      _log(
          'Updated $updateCount record(s) in $tableName with uniqueid=$uniqueId');
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
        _logError(
            'formchanges table does not exist - skipping change tracking');
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
          _log(
              'Recorded change: $fieldName from "$oldValueStr" to "$newValueStr"');
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

  /// Check if a value is unique in the given table and column
  static Future<bool> isValueUnique(
      String tableName, String columnName, String value) async {
    if (_db == null) await init();
    try {
      final count = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $tableName WHERE $columnName = ?',
        [value],
      ));
      return (count ?? 0) == 0;
    } catch (e) {
      _logError('Error checking uniqueness: $e');
      return true;
    }
  }

  /// Get all column names for a table
  static Future<List<String>> _getTableColumns(String tableName) async {
    if (_db == null) return [];

    try {
      final result = await _db!.rawQuery('PRAGMA table_info($tableName)');
      final columns =
          result.map((row) => (row['name'] as String).toLowerCase()).toList();
      return columns;
    } catch (e) {
      _logError('Error getting table columns: $e');
      return [];
    }
  }

  /// Get CRF configuration for a specific table
  /// Returns the CRF record with all metadata or null if not found
  static Future<Map<String, dynamic>?> getCrfConfig(String tableName) async {
    if (_db == null) {
      _logError('Database not initialized');
      return null;
    }

    try {
      final results = await _db!.query(
        'crfs',
        where: 'tablename = ?',
        whereArgs: [tableName],
      );

      if (results.isEmpty) {
        return null;
      }

      return results.first;
    } catch (e) {
      _logError('Error fetching CRF config for $tableName: $e');
      return null;
    }
  }

  /// Count records in a table matching a where clause
  /// Returns the count of matching records
  static Future<int> getRecordCount({
    required String tableName,
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    if (_db == null) {
      _logError('Database not initialized');
      return 0;
    }

    try {
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        _logError('Table $tableName does not exist');
        return 0;
      }

      final results = await _db!.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName${where != null ? ' WHERE $where' : ''}',
        whereArgs,
      );

      if (results.isEmpty) {
        return 0;
      }

      return (results.first['count'] as int?) ?? 0;
    } catch (e) {
      _logError('Error counting records in $tableName: $e');
      return 0;
    }
  }

  /// Update a specific field in a record
  /// Used for auto-syncing counts
  static Future<void> updateField({
    required String tableName,
    required String field,
    required dynamic value,
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    if (_db == null) {
      _logError('Database not initialized');
      return;
    }

    try {
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        _logError('Table $tableName does not exist');
        return;
      }

      await _db!.update(
        tableName,
        {field: value},
        where: where,
        whereArgs: whereArgs,
      );

      _log('Updated $tableName.$field to $value where $where');
    } catch (e) {
      _logError('Error updating field $field in $tableName: $e');
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
