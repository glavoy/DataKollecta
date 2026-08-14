import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/question.dart';
import 'csv_data_service.dart';
import 'settings_service.dart';
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

      final surveysDir = await _getSurveysDirectory();

      _log('Looking for surveys in: ${surveysDir.path}');

      if (!await surveysDir.exists()) {
        _log(
            'Warning: surveys directory not found at ${surveysDir.path}. Surveys might not be extracted yet.');
        // Fallback: try to use the hardcoded list from SurveyConfigService or just return
        // For now, let's assume we can access it or we use the known list.
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
    }
  }

  /// Initialize the database for a specific survey
  static Future<void> _initDatabaseForSurvey(String surveyId) async {
    if (_initializedSurveys.contains(surveyId)) return;

    try {
      _log('Initializing database for survey: $surveyId');

      // 1. Read manifest
      // We need to find the manifest file. Since we moved to dynamic loading,
      // we should ask SurveyConfigService for the path or scan for it.
      // However, DbService shouldn't depend on SurveyConfigService if possible to avoid circular deps.
      // But SurveyConfigService depends on SettingsService, not DbService.
      // So we can use SurveyConfigService here if we want, or replicate the logic.
      // Replicating logic for now to keep it self-contained but using the known path structure.

      // Replicating logic for now to keep it self-contained but using the known path structure.

      final surveysDir = await _getSurveysDirectory();

      // We need to find the folder for this surveyId
      File? manifestFile;
      if (await surveysDir.exists()) {
        final entities = await surveysDir.list().toList();
        for (final entity in entities) {
          if (entity is Directory) {
            final mFile = File(p.join(entity.path, 'survey_manifest.gistx'));
            if (await mFile.exists()) {
              try {
                final content = await mFile.readAsString();
                final jsonMap = json.decode(content);
                if (jsonMap['surveyId'] == surveyId) {
                  manifestFile = mFile;
                  break;
                }
              } catch (e) {
                // ignore
              }
            }
          }
        }
      }

      Map<String, dynamic> manifest;
      if (manifestFile != null) {
        final manifestJson = await manifestFile.readAsString();
        manifest = json.decode(manifestJson) as Map<String, dynamic>;
      } else {
        _logError('Manifest not found for surveyId: $surveyId');
        return;
      }

      final dbName = manifest['databaseName'] as String?;
      if (dbName == null) {
        _logError('No databaseName in manifest for $surveyId');
        return;
      }

      // 2. Determine DB path
      // Windows: %LOCALAPPDATA%/<AppConfig.storageFolder>/databases/
      // Android: External Files Dir (accessible)

      Directory baseDbDir;
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir == null) {
          // Fallback to internal if external not available
          baseDbDir = await getApplicationSupportDirectory();
        } else {
          baseDbDir = extDir;
        }
      } else if (Platform.isWindows) {
        // Windows: Use LOCALAPPDATA for AppData\Local
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null) {
          baseDbDir = Directory(localAppData);
        } else {
          // Fallback if LOCALAPPDATA not set (unlikely)
          baseDbDir = await getApplicationSupportDirectory();
        }
      } else {
        // Linux/Mac: Use standard application support directory
        baseDbDir = await getApplicationSupportDirectory();
      }

      final dbDir = Directory(p.join(baseDbDir.path, AppConfig.storageFolder, 'databases'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      final dbPath = p.join(dbDir.path, dbName);
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

      // 1b. Create Form Changes Table
      await _syncFormChangesTable(surveyId, db);

      // 1c. Import CSV files as tables
      await _importCsvFiles(surveyId, db);

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

  static Future<void> _importCsvFiles(String surveyId, Database db) async {
    try {
      final surveysDir = await _getSurveysDirectory();
      final surveyDir = Directory(p.join(surveysDir.path, surveyId));

      if (!await surveyDir.exists()) return;

      final entities = await surveyDir.list().toList();
      final csvFiles =
          entities.where((e) => e.path.toLowerCase().endsWith('.csv')).toList();

      for (final entity in csvFiles) {
        if (entity is File) {
          await _importSingleCsv(db, entity);
        }
      }
    } catch (e) {
      _logError('Error importing CSV files for $surveyId: $e');
    }
  }

  static Future<void> _importSingleCsv(Database db, File csvFile) async {
    try {
      final tableName = p.basenameWithoutExtension(csvFile.path).toLowerCase();
      final content = await csvFile.readAsString();
      await importCsvContent(db, tableName, content);
    } catch (e) {
      _logError('Failed to import CSV ${csvFile.path}: $e');
    }
  }

  /// Mirrors CSV content into [tableName], replacing whatever was there.
  ///
  /// Parsing is delegated to [CsvDataService.parseCsv] so that a file read
  /// here behaves exactly as it does when a question reads it directly:
  /// quoted values, embedded commas and any line ending are handled the same
  /// way. Splitting on commas by hand would shift every column after a quoted
  /// comma and leave escaped quotes in the stored value.
  ///
  /// Public to allow the import to be verified without the file system.
  @visibleForTesting
  static Future<void> importCsvContent(
      Database db, String tableName, String content) async {
    _log('Importing CSV: $tableName...');

    if (content.trim().isEmpty) return;

    final rows = CsvDataService.parseCsv(content);
    if (rows.isEmpty) return;

    // A trailing comma in the header line produces an unnamed column, which
    // cannot become a SQL column; every row carries every header, so the
    // first row is enough to establish the column set.
    final headers = rows.first.keys.where((h) => h.isNotEmpty).toList();
    if (headers.isEmpty) return;

    // Treat all columns as TEXT for simplicity and flexibility
    final buffer = StringBuffer();
    buffer.write('CREATE TABLE IF NOT EXISTS $tableName (');
    buffer.write(headers.map((h) => '$h TEXT').join(', '));
    buffer.write(')');

    await db.execute(buffer.toString());

    // Clear existing data (full refresh from CSV)
    await db.delete(tableName);

    final batch = db.batch();
    for (final row in rows) {
      batch.insert(tableName, {
        for (final header in headers) header: row[header] ?? '',
      });
    }

    await batch.commit(noResult: true);
    _log('Imported ${rows.length} rows into $tableName');
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
          auto_start_repeat INTEGER, 
          repeat_enforce_count INTEGER,
          display_fields TEXT,
          entry_condition TEXT
        )
      ''');
    }

    // Populate from Manifest JSON
    // We always try to sync/update the metadata
    final crfsList = manifest['crfs'] as List?;
    if (crfsList != null) {
      try {
        // Clear existing data to ensure fresh sync
        await db.delete('crfs');

        for (final item in crfsList) {
          if (item is Map<String, dynamic>) {
            final Map<String, dynamic> rowData = Map.from(item);

            // Handle idconfig: if it's a Map, convert to JSON string
            if (rowData['idconfig'] is Map) {
              rowData['idconfig'] = json.encode(rowData['idconfig']);
            }

            await db.insert('crfs', rowData);
          }
        }
      } catch (e) {
        _logError('Error populating crfs table from manifest: $e');
      }
    } else {
      _logError('No "crfs" section found in manifest for $surveyId');
    }
  }

  /// Public to allow the create-vs-migrate schema path to be verified
  /// without initializing the application's survey database registry.
  @visibleForTesting
  static Future<void> syncFormChangesTableForTesting(
          String surveyId, Database db) =>
      _syncFormChangesTable(surveyId, db);

  static Future<void> _syncFormChangesTable(
      String surveyId, Database db) async {
    final tableExists = await _tableExists(db, 'formchanges');
    if (!tableExists) {
      _log('Creating formchanges table for $surveyId...');
      await db.execute('''
        CREATE TABLE formchanges (
            changeid       INTEGER PRIMARY KEY AUTOINCREMENT,
            tablename      TEXT NOT NULL,
            fieldname      TEXT NOT NULL,
            uniqueid       TEXT NOT NULL,
            oldvalue       TEXT,
            newvalue       TEXT,
            changed_at     DATETIME DEFAULT (CURRENT_TIMESTAMP),
            changeuniqueid TEXT,
            surveyor_id    TEXT,
            synced_at      DATETIME
        )
      ''');
    } else {
      final existingColumns = await _getTableColumns(db, 'formchanges');
      for (final column in const [
        'changeuniqueid',
        'surveyor_id',
        'synced_at',
      ]) {
        if (!existingColumns.contains(column)) {
          final type = column == 'synced_at' ? 'DATETIME' : 'TEXT';
          try {
            await db
                .execute('ALTER TABLE formchanges ADD COLUMN $column $type');
            _log('Added $column column to formchanges for $surveyId');
          } catch (e) {
            _logError('Failed to add $column column to formchanges: $e');
          }
        }
      }
    }

    // SQLite permits unlimited NULLs in a unique index, so legacy rows
    // (created before changeuniqueid existed) need no backfill -- HTTP sync
    // simply excludes them with a `WHERE changeuniqueid IS NOT NULL` filter.
    try {
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_formchanges_changeuniqueid '
          'ON formchanges(changeuniqueid)');
    } catch (e) {
      _logError('Failed to create formchanges changeuniqueid index: $e');
    }
  }

  static Future<void> _syncSurveyTable(
      String surveyId, Database db, String xmlFilename) async {
    // Construct path to local file
    final surveysDir = await _getSurveysDirectory();
    final surveyDir = Directory(p.join(surveysDir.path, surveyId));
    final xmlFile = File(p.join(surveyDir.path, xmlFilename));
    final tableName =
        p.basename(xmlFilename).toLowerCase().replaceAll('.xml', '');

    try {
      List<Question> questions;
      if (await xmlFile.exists()) {
        questions = await SurveyLoader.loadFromFile(xmlFile);
      } else {
        // Fallback to assets if local file missing (e.g. for bundled surveys if extraction failed?)
        // But we expect extraction to have happened.
        _logError('XML file not found at ${xmlFile.path}');
        return;
      }
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
        bool hasSyncedAt = false;

        for (final q in dataQuestions) {
          colDefs.add('${q.fieldName} TEXT');
          if (q.fieldName.toLowerCase() == 'uniqueid') hasUniqueId = true;
          if (q.fieldName.toLowerCase() == 'synced_at') hasSyncedAt = true;
        }

        if (!hasUniqueId) {
          colDefs.add('uniqueid TEXT PRIMARY KEY');
        }
        if (!hasSyncedAt) {
          colDefs.add('synced_at DATETIME');
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
                  'ALTER TABLE $tableName ADD COLUMN ${q.fieldName} TEXT');
              _log('Added column ${q.fieldName} to $tableName');
            } catch (e) {
              _logError('Failed to add column ${q.fieldName}: $e');
            }
          }
        }
        if (!existingColumns.contains('synced_at')) {
          try {
            await db
                .execute('ALTER TABLE $tableName ADD COLUMN synced_at DATETIME');
            _log('Added synced_at column to $tableName');
          } catch (e) {
            _logError('Failed to add synced_at column to $tableName: $e');
          }
        }
      }
    } catch (e) {
      _logError('Error syncing table $tableName: $e');
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

  /// Public method to get database for queries (used by DatabaseResponseService)
  static Future<Database> getDatabaseForQueries(String surveyId) async {
    return await _getDbOrThrow(surveyId);
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
          conflictAlgorithm: ConflictAlgorithm.abort);

      // Backup: Log INSERT statement
      try {
        final columns = rowData.keys.join(', ');
        final values = rowData.values.map((v) => _escapeSqlValue(v)).join(', ');
        final sql = 'INSERT INTO $tableName ($columns) VALUES ($values);';
        await _writeBackup(surveyId, tableName, sql);
      } catch (e) {
        _logError('Failed to write backup for INSERT: $e');
      }
    } catch (e) {
      _logError('Failed to save interview: $e');
      throw DatabaseException('Failed to save interview: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getExistingRecords(
      String surveyId, String tableName,
      {String? orderBy}) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return [];

      final results = await db.query(tableName, orderBy: orderBy);

      // Normalize keys to lowercase to avoid case-sensitivity issues across platforms
      return results.map((row) {
        return row.map((key, value) => MapEntry(key.toLowerCase(), value));
      }).toList();
    } catch (e) {
      _logError('Error fetching records: $e');
      return [];
    }
  }

  static Future<DateTime?> getLastBackupTime(String surveyId) async {
    try {
      final backupsDir = await _getBackupsDirectory();
      final surveyBackupDir = Directory(p.join(backupsDir.path, surveyId));
      if (!await surveyBackupDir.exists()) return null;

      final files = await surveyBackupDir.list().toList();
      if (files.isEmpty) return null;

      DateTime? lastModified;
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (lastModified == null || stat.modified.isAfter(lastModified)) {
            lastModified = stat.modified;
          }
        }
      }
      return lastModified;
    } catch (e) {
      _logError('Error getting last backup time: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getRecordByUniqueId(
      String surveyId, String tableName, String uniqueId) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      final results = await db
          .query(tableName, where: 'uniqueid = ?', whereArgs: [uniqueId]);

      if (results.isEmpty) return null;

      // Normalize keys to lowercase
      return results.first
          .map((key, value) => MapEntry(key.toLowerCase(), value));
    } catch (e) {
      return null;
    }
  }

  /// Get the next auto-increment value for a field (e.g., linenum, netnum)
  static Future<int> getNextIncrementValue({
    required String surveyId,
    required String tableName,
    required String incrementField,
    required String primaryKeyField,
    required String primaryKeyValue,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return 1;

      final results = await db.rawQuery(
        'SELECT MAX(CAST($incrementField AS INTEGER)) as maxValue FROM $tableName WHERE $primaryKeyField = ?',
        [primaryKeyValue],
      );

      if (results.isEmpty || results.first['maxValue'] == null) return 1;
      final maxValue = results.first['maxValue'];
      // Handle both int and string results
      if (maxValue is int) {
        return maxValue + 1;
      } else if (maxValue is String) {
        return (int.tryParse(maxValue) ?? 0) + 1;
      }
      return 1;
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
      final rowData = prepareUpdateRowData(answers, existingColumns);

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

      // Backup: Log UPDATE statement
      try {
        final setClause = rowData.entries
            .map((e) => '${e.key} = ${_escapeSqlValue(e.value)}')
            .join(', ');
        final sql =
            "UPDATE $tableName SET $setClause WHERE uniqueid = '${_escapeSqlString(uniqueId)}';";
        await _writeBackup(surveyId, tableName, sql);
      } catch (e) {
        _logError('Failed to write backup for UPDATE: $e');
      }
    } catch (e) {
      throw DatabaseException('Failed to update interview: $e');
    }
  }

  /// Converts answers to SQLite update values while retaining explicit nulls.
  ///
  /// Public to allow persistence behavior to be verified without initializing
  /// the application's survey database registry.
  @visibleForTesting
  static Map<String, dynamic> prepareUpdateRowData(
    AnswerMap answers,
    Iterable<String> existingColumns,
  ) {
    final rowData = <String, dynamic>{};
    final normalizedColumns =
        existingColumns.map((column) => column.toLowerCase()).toSet();

    for (final entry in answers.entries) {
      final key = entry.key;
      if (key.trim().isEmpty ||
          !normalizedColumns.contains(key.toLowerCase())) {
        continue;
      }

      final value = entry.value;
      if (value == null) {
        rowData[key] = null;
      } else if (value is List) {
        rowData[key] = value.map((item) => item.toString()).join(',');
      } else if (value is DateTime) {
        rowData[key] = value.toIso8601String();
      } else {
        rowData[key] = value;
      }
    }

    // An edit must re-upload even if the HTTP-sync product already sent an
    // earlier version of this row; clearing it here (rather than at each
    // call site) covers every update path uniformly. GiSTX rows -- no
    // synced_at column -- are unaffected.
    if (normalizedColumns.contains('synced_at')) {
      rowData['synced_at'] = null;
    }

    return rowData;
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

      // Looked up once per call, not per field.
      final surveyorId = await SettingsService().surveyorId;

      for (final entry in newAnswers.entries) {
        final fieldName = entry.key;
        if (!existingColumns.contains(fieldName.toLowerCase())) continue;

        final oldValue = originalAnswers[fieldName];
        final newValue = entry.value;
        final oldValueStr = _valueToString(oldValue);
        final newValueStr = _valueToString(newValue);

        if (oldValueStr != newValueStr) {
          // Check for numeric equality (e.g. "4" vs "04")
          if (oldValueStr != null && newValueStr != null) {
            final n1 = num.tryParse(oldValueStr);
            final n2 = num.tryParse(newValueStr);
            if (n1 != null && n2 != null && n1 == n2) {
              continue; // Logically the same numeric value
            }
          }

          await db.insert('formchanges', {
            'tablename': tableName,
            'fieldname': fieldName,
            'uniqueid': uniqueId,
            'oldvalue': oldValueStr,
            'newvalue': newValueStr,
            'changed_at': DateTime.now().toIso8601String(),
            'changeuniqueid': const Uuid().v4(),
            'surveyor_id': surveyorId,
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

  static Future<List<Map<String, dynamic>>> getAllPrimaryKeys(
      String surveyId, String tableName, List<String> pkFields) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      // Select only the primary key fields
      return await db.query(tableName, columns: pkFields);
    } catch (e) {
      _logError('Failed to get all primary keys: $e');
      return [];
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

      final columns = result.map((row) {
        // Handle case-insensitive key lookup for 'name'
        // sqflite on Android might return uppercase keys
        final normalizedRow = row.map((k, v) => MapEntry(k.toLowerCase(), v));
        return (normalizedRow['name'] as String).toLowerCase();
      }).toList();

      return columns;
    } catch (e) {
      return [];
    }
  }

  static Future<void> _writeBackup(
      String surveyId, String tableName, String sql) async {
    try {
      final backupsDir = await _getBackupsDirectory();
      final surveyBackupDir = Directory(p.join(backupsDir.path, surveyId));
      if (!await surveyBackupDir.exists()) {
        await surveyBackupDir.create(recursive: true);
      }

      final backupFile = File(p.join(surveyBackupDir.path, '${tableName}_bak'));

      // Append mode
      await backupFile.writeAsString('$sql\n', mode: FileMode.append);
    } catch (e) {
      _logError('Failed to write backup: $e');
    }
  }

  static String _escapeSqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is DateTime) return "'${value.toIso8601String()}'";
    return "'${_escapeSqlString(value.toString())}'";
  }

  static String _escapeSqlString(String str) {
    return str.replaceAll("'", "''");
  }

  static Future<Directory> _getBackupsDirectory() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      // Windows: Use LOCALAPPDATA for AppData\Local
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        baseDir = Directory(localAppData);
      } else {
        baseDir = await getApplicationSupportDirectory();
      }
    } else {
      // Linux/Mac
      baseDir = await getApplicationSupportDirectory();
    }
    return Directory(p.join(baseDir.path, AppConfig.storageFolder, 'backups'));
  }

  static Future<Directory> _getSurveysDirectory() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      // Windows: Use LOCALAPPDATA for AppData\Local
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        baseDir = Directory(localAppData);
      } else {
        baseDir = await getApplicationSupportDirectory();
      }
    } else {
      // Linux/Mac
      baseDir = await getApplicationSupportDirectory();
    }
    return Directory(p.join(baseDir.path, AppConfig.storageFolder, 'surveys'));
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
