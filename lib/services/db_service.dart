import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import '../config/app_config.dart';
import '../models/question.dart';
import 'survey_loader.dart';

class DbService {
  // Map of surveyId -> Database
  static final Map<String, Database> _databases = {};

  // Keep track of initialized surveys to avoid re-initializing
  static final Set<String> _initializedSurveys = {};

  /// Call once at app start to initialize the environment and load available surveys
  static Future<void> init() async {
    try {
      // Initialize FFI for desktop platforms
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      _log('Initializing DbService...');
      await _initializeSurveyDatabases();
    } catch (e) {
      _logError('Failed to initialize database service: $e');
      rethrow;
    }
  }

  /// Scan assets/surveys and initialize databases for each found survey
  static Future<void> _initializeSurveyDatabases() async {
    try {
      // We need to find where the surveys are.
      // On Windows, we can try to look in the local assets folder relative to the executable
      // or rely on the known folders from SurveyConfigService if listing assets is not reliable via IO.

      // For this implementation, we will try to list directories in 'assets/surveys'
      // If that fails (e.g. in release mode where assets are bundled), we might need another strategy
      // but the user requirement implies runtime creation and folder scanning.

      _log('Current working directory: ${Directory.current.path}');
      final surveysDir = Directory('assets/surveys');
      _log('Looking for surveys in: ${surveysDir.absolute.path}');

      if (!await surveysDir.exists()) {
        _log(
            'Warning: assets/surveys directory not found at ${surveysDir.absolute.path}');
        // Fallback: try to use the hardcoded list from SurveyConfigService or just return
        // For now, let's assume we can access it or we use the known list.
        await _initKnownSurveys();
        return;
      }

      final List<FileSystemEntity> entities = await surveysDir.list().toList();
      _log('Found ${entities.length} entities in surveys directory');
      for (final entity in entities) {
        if (entity is Directory) {
          final surveyId = p.basename(entity.path);
          _log('Found survey directory: $surveyId');
          await _initDatabaseForSurvey(surveyId);
        }
      }
    } catch (e) {
      _logError('Error scanning survey directories: $e');
      // Fallback to known surveys
      await _initKnownSurveys();
    }
  }

  static Future<void> _initKnownSurveys() async {
    // This is a fallback if we can't list the directory
    // We should probably expose the list from SurveyConfigService, but for now hardcode or import
    const knownSurveys = ['fake_household_survey', 'fake_clinical_trial'];
    for (final surveyId in knownSurveys) {
      await _initDatabaseForSurvey(surveyId);
    }
  }

  /// Initialize the database for a specific survey
  static Future<void> _initDatabaseForSurvey(String surveyId) async {
    if (_initializedSurveys.contains(surveyId)) return;

    try {
      _log('Initializing database for survey: $surveyId');

      // 1. Read manifest
      final manifestPath = 'assets/surveys/$surveyId/survey_manifest.json';
      Map<String, dynamic> manifest;
      try {
        // Try loading from rootBundle first (standard Flutter asset)
        final manifestJson = await rootBundle.loadString(manifestPath);
        manifest = json.decode(manifestJson) as Map<String, dynamic>;
      } catch (e) {
        // Fallback to file IO if not in bundle (e.g. dynamically added)
        final file = File(manifestPath);
        if (await file.exists()) {
          final manifestJson = await file.readAsString();
          manifest = json.decode(manifestJson) as Map<String, dynamic>;
        } else {
          _logError('Manifest not found for $surveyId at $manifestPath');
          return;
        }
      }

      final dbName = manifest['databaseName'] as String?;
      if (dbName == null) {
        _logError('No databaseName in manifest for $surveyId');
        return;
      }

      // 2. Determine DB path
      // User requested: /assets/database folder
      // We'll create this folder if it doesn't exist
      final dbDir = Directory('assets/database');
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      // Use absolute path to ensure it goes exactly where we want,
      // avoiding sqflite_common_ffi's default sandbox in .dart_tool
      final dbPath = p.join(dbDir.absolute.path, dbName);
      _log('Database path for $surveyId: $dbPath');

      // 3. Open Database
      final db =
          await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
        _log('Creating new database for $surveyId');
        // We will handle table creation in _syncDatabaseSchema, but we can do initial setup here if needed
      });

      _databases[surveyId] = db;
      _initializedSurveys.add(surveyId);

      // 4. Sync Schema (Create CRFS, Survey Tables)
      await _syncDatabaseSchema(surveyId, db, manifest);
    } catch (e) {
      _logError('Failed to initialize database for $surveyId: $e');
    }
  }

  static Future<void> _syncDatabaseSchema(
      String surveyId, Database db, Map<String, dynamic> manifest) async {
    try {
      // 1. Create and Populate CRFS Table
      await _syncCrfsTable(surveyId, db, manifest);

      // 2. Create Survey Tables from XMLs
      final xmlFiles = manifest['xmlFiles'] as List?;
      if (xmlFiles != null) {
        for (final xmlFile in xmlFiles) {
          await _syncSurveyTable(surveyId, db, xmlFile.toString());
        }
      }
    } catch (e) {
      _logError('Error syncing schema for $surveyId: $e');
    }
  }

  static Future<void> _syncCrfsTable(
      String surveyId, Database db, Map<String, dynamic> manifest) async {
    // Check if table exists
    final tableExists = await _tableExists(db, 'crfs');

    if (!tableExists) {
      _log('Creating crfs table for $surveyId...');
      // User specified schema
      await db.execute('''
        CREATE TABLE crfs (
          display_order INTEGER DEFAULT 0, 
          tablename TEXT,
          primarykey TEXT,
          displayname TEXT,
          isbase INTEGER DEFAULT 0,
          linkingfield TEXT,
          parenttable TEXT,
          incrementfield TEXT,
          requireslink INTEGER DEFAULT 0,
          idconfig TEXT,
          repeat_count_field TEXT, 
          repeat_count_source TEXT, 
          auto_start_repeat INTEGER, 
          repeat_enforce_count INTEGER,
          display_fields TEXT
        )
      ''');
    }

    // Populate from CSV
    // We always try to sync/update the metadata
    final crfsMetadataFile = manifest['crfsMetadataFile'] as String?;
    if (crfsMetadataFile != null) {
      await _populateCrfsTable(surveyId, db, crfsMetadataFile);
    }
  }

  static Future<void> _populateCrfsTable(
      String surveyId, Database db, String csvFilename) async {
    try {
      final csvPath = 'assets/surveys/$surveyId/$csvFilename';
      String csvContent;

      try {
        csvContent = await rootBundle.loadString(csvPath);
      } catch (e) {
        final file = File(csvPath);
        if (await file.exists()) {
          csvContent = await file.readAsString();
        } else {
          _logError('CRFS metadata file not found: $csvPath');
          return;
        }
      }

      final List<List<dynamic>> csvData =
          const CsvToListConverter().convert(csvContent);
      if (csvData.isEmpty) return;

      // Headers are in the first row
      final headers = csvData[0].map((h) => h.toString().trim()).toList();

      // Clear existing data to ensure fresh sync
      await db.delete('crfs');

      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.isEmpty) continue;

        final Map<String, dynamic> rowData = {};
        for (int j = 0; j < headers.length && j < row.length; j++) {
          final header = headers[j];
          final value = row[j];

          // Handle boolean/integer conversion if needed based on schema defaults
          // The schema uses INTEGER for flags like isbase, requireslink
          // We assume the CSV contains appropriate values (0/1) or we might need conversion
          rowData[header] = value;
        }

        await db.insert('crfs', rowData);
      }
      _log(
          'Populated crfs table for $surveyId with ${csvData.length - 1} rows');
    } catch (e) {
      _logError('Error populating crfs table: $e');
    }
  }

  static Future<void> _syncSurveyTable(
      String surveyId, Database db, String xmlFilename) async {
    final assetPath = 'assets/surveys/$surveyId/$xmlFilename';
    final tableName =
        p.basename(xmlFilename).toLowerCase().replaceAll('.xml', '');

    try {
      final questions = await SurveyLoader.loadFromAsset(assetPath);
      final dataQuestions =
          questions.where((q) => q.type != QuestionType.information).toList();

      if (dataQuestions.isEmpty) return;

      final tableExists = await _tableExists(db, tableName);

      if (!tableExists) {
        _log('Creating table $tableName for $surveyId...');
        final buffer = StringBuffer();
        buffer.write('CREATE TABLE $tableName (');

        // Add uniqueid as a standard field if not present in questions?
        // The previous implementation didn't explicitly add it, implying it might be in the XML or handled otherwise.
        // However, `updateInterview` uses `uniqueid`. Let's assume it's part of the schema or needs to be added.
        // Checking previous code: it didn't add `uniqueid` explicitly in `onCreate`.
        // But `updateInterview` queries `where: 'uniqueid = ?'`.
        // This implies `uniqueid` MUST be a column.
        // I will add it as a standard column if it's not in the questions.

        final colDefs = <String>[];
        bool hasUniqueId = false;

        for (final q in dataQuestions) {
          colDefs.add('${q.fieldName} ${_getSqlType(q)}');
          if (q.fieldName.toLowerCase() == 'uniqueid') hasUniqueId = true;
        }

        if (!hasUniqueId) {
          colDefs.add('uniqueid TEXT PRIMARY KEY');
        }

        buffer.write(colDefs.join(', '));
        buffer.write(')');

        await db.execute(buffer.toString());
      } else {
        // Alter table logic
        final existingColumns = await _getTableColumns(db, tableName);
        for (final q in dataQuestions) {
          if (!existingColumns.contains(q.fieldName.toLowerCase())) {
            try {
              await db.execute(
                  'ALTER TABLE $tableName ADD COLUMN ${q.fieldName} ${_getSqlType(q)}');
              _log('Added column ${q.fieldName} to $tableName');
            } catch (e) {
              _logError('Failed to add column ${q.fieldName}: $e');
            }
          }
        }
      }
    } catch (e) {
      _logError('Error syncing table $tableName: $e');
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

  // --- Public API methods ---

  static Future<Database> _getDbOrThrow(String surveyId) async {
    if (!_databases.containsKey(surveyId)) {
      // Try to init if missing
      await _initDatabaseForSurvey(surveyId);
    }
    final db = _databases[surveyId];
    if (db == null) {
      throw DatabaseException('Database not initialized for survey: $surveyId');
    }
    return db;
  }

  static Future<void> saveInterview({
    required String surveyId,
    required String surveyFilename,
    required AnswerMap answers,
  }) async {
    final db = await _getDbOrThrow(surveyId);
    final tableName = surveyFilename.toLowerCase().replaceAll('.xml', '');

    try {
      if (!await _tableExists(db, tableName)) {
        throw DatabaseException('Table "$tableName" does not exist.');
      }

      final Map<String, dynamic> rowData = {};
      for (final entry in answers.entries) {
        final key = entry.key;
        if (key.trim().isEmpty) continue; // Skip empty keys

        final val = entry.value;
        if (val == null) continue;

        if (val is List) {
          rowData[key] = val.map((e) => e.toString()).join(',');
        } else if (val is DateTime) {
          rowData[key] = val.toIso8601String();
        } else {
          rowData[key] = val;
        }
      }

      await db.insert(tableName, rowData,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      _logError('Failed to save interview: $e');
      throw DatabaseException('Failed to save interview: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getExistingRecords(
      String surveyId, String tableName) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return [];
      return await db.query(tableName);
    } catch (e) {
      _logError('Error fetching records: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getRecordByUniqueId(
      String surveyId, String tableName, String uniqueId) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      final results = await db
          .query(tableName, where: 'uniqueid = ?', whereArgs: [uniqueId]);
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      return null;
    }
  }

  static Future<int> getNextLineNum({
    required String surveyId,
    required String tableName,
    required String primaryKeyField,
    required String primaryKeyValue,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return 1;

      final results = await db.rawQuery(
        'SELECT MAX(linenum) as maxLineNum FROM $tableName WHERE $primaryKeyField = ?',
        [primaryKeyValue],
      );

      if (results.isEmpty || results.first['maxLineNum'] == null) return 1;
      return (results.first['maxLineNum'] as int) + 1;
    } catch (e) {
      return 1;
    }
  }

  static Future<void> updateInterview({
    required String surveyId,
    required String surveyFilename,
    required AnswerMap answers,
    required String uniqueId,
    required Map<String, dynamic>? originalAnswers,
  }) async {
    final db = await _getDbOrThrow(surveyId);
    final tableName = surveyFilename.toLowerCase().replaceAll('.xml', '');

    try {
      final existingColumns = await _getTableColumns(db, tableName);
      final Map<String, dynamic> rowData = {};

      for (final entry in answers.entries) {
        final key = entry.key;
        if (key.trim().isEmpty) continue; // Skip empty keys

        final val = entry.value;

        if (!existingColumns.contains(key.toLowerCase())) continue;

        if (val == null) {
          rowData[key] = null;
        } else if (val is List) {
          rowData[key] = val.map((e) => e.toString()).join(',');
        } else if (val is DateTime) {
          rowData[key] = val.toIso8601String();
        } else {
          rowData[key] = val;
        }
      }

      if (rowData.isEmpty) throw DatabaseException('No valid fields to update');

      if (originalAnswers != null) {
        await _recordChanges(
          db: db,
          tableName: tableName,
          uniqueId: uniqueId,
          originalAnswers: originalAnswers,
          newAnswers: answers,
          existingColumns: existingColumns,
        );
      }

      await db.update(tableName, rowData,
          where: 'uniqueid = ?', whereArgs: [uniqueId]);
    } catch (e) {
      throw DatabaseException('Failed to update interview: $e');
    }
  }

  static Future<void> _recordChanges({
    required Database db,
    required String tableName,
    required String uniqueId,
    required Map<String, dynamic> originalAnswers,
    required AnswerMap newAnswers,
    required List<String> existingColumns,
  }) async {
    try {
      if (!await _tableExists(db, 'formchanges')) return;

      for (final entry in newAnswers.entries) {
        final fieldName = entry.key;
        if (!existingColumns.contains(fieldName.toLowerCase())) continue;

        final oldValue = originalAnswers[fieldName];
        final newValue = entry.value;
        final oldValueStr = _valueToString(oldValue);
        final newValueStr = _valueToString(newValue);

        if (oldValueStr != newValueStr) {
          await db.insert('formchanges', {
            'tablename': tableName,
            'fieldname': fieldName,
            'uniqueid': uniqueId,
            'oldvalue': oldValueStr,
            'newvalue': newValueStr,
            'changed_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (e) {
      _logError('Error recording changes: $e');
    }
  }

  static String? _valueToString(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).join(',');
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }

  static Future<bool> isValueUnique(String surveyId, String tableName,
      String columnName, String value) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $tableName WHERE $columnName = ?',
        [value],
      ));
      return (count ?? 0) == 0;
    } catch (e) {
      return true;
    }
  }

  static Future<List<String>> getPrimaryKeyFields(
      String surveyId, String tableName) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      final result = await db.query('crfs',
          columns: ['primarykey'],
          where: 'tablename = ?',
          whereArgs: [tableName]);
      if (result.isEmpty) return [];
      final pkString = result.first['primarykey'] as String;
      return pkString.split(',').map((s) => s.trim()).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getCrfConfig(
      String surveyId, String tableName) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      final results = await db
          .query('crfs', where: 'tablename = ?', whereArgs: [tableName]);
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      return null;
    }
  }

  static Future<int> getRecordCount({
    required String surveyId,
    required String tableName,
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return 0;

      final results = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName${where != null ? ' WHERE $where' : ''}',
        whereArgs,
      );

      if (results.isEmpty) return 0;
      return (results.first['count'] as int?) ?? 0;
    } catch (e) {
      _logError('Error counting records in $tableName: $e');
      return 0;
    }
  }

  static Future<void> updateField({
    required String surveyId,
    required String tableName,
    required String field,
    required dynamic value,
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return;

      await db.update(
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

  // --- Helpers ---

  static Future<bool> _tableExists(Database db, String tableName) async {
    try {
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<List<String>> _getTableColumns(
      Database db, String tableName) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info($tableName)');
      return result
          .map((row) => (row['name'] as String).toLowerCase())
          .toList();
    } catch (e) {
      return [];
    }
  }

  static void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[DbService] $message');
    }
  }

  static void _logError(String message) {
    debugPrint('[DbService ERROR] $message');
  }
}

class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);
  @override
  String toString() => message;
}
