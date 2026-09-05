import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
// sqflite exports a `DatabaseException` of its own. While this project's was
// declared in this file it won by being local; now that it is imported, the two
// are ambiguous. Every `DatabaseException` raised here is deliberately ours --
// nothing catches sqflite's by that name -- so sqflite's is hidden, the same
// way `db_service_test.dart` has always hidden it.
import 'package:sqflite/sqflite.dart' hide DatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'app_paths.dart';
import '../models/question.dart';
import 'answer_equality.dart';
import 'csv_data_service.dart';
import 'database_exception.dart';
import 'db_backup.dart';
import 'settings_service.dart';
import 'survey_loader.dart';
import 'survey_table_schema.dart';

// `DatabaseException` used to be declared at the bottom of this file. It moved
// so `SurveyTableSchema` could throw it without importing `DbService`, and is
// re-exported here so every existing `import 'db_service.dart'` still sees it.
export 'database_exception.dart';

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

      final dbDir = await AppPaths.databasesDir();

      final dbPath = p.join(dbDir.path, dbName);
      _log('Database path for $surveyId: $dbPath');

      // 3. Open Database
      final db = await openDatabase(dbPath, options: surveyOpenOptions());

      _databases[surveyId] = db;
      _initializedSurveys.add(surveyId);

      // 4. Sync Schema (Create CRFS, Survey Tables)
      await _syncDatabaseSchema(surveyId, db, manifest);
    } catch (e) {
      _logError('Failed to initialize database for $surveyId: $e');
    }
  }

  /// The options every survey database is opened with.
  ///
  /// Factored out so a test can open a database exactly the way production
  /// does. Asserting that a `CREATE TABLE` string contains the word
  /// `REFERENCES` proves nothing about whether the constraint is *enforced*;
  /// the pragma below is the only thing that decides that, and it is easy to
  /// get right in one place and wrong in another.
  ///
  /// `PRAGMA foreign_keys` defaults to **off**, is **per-connection**, and is
  /// not persisted in the file -- so a connection that forgets it sees a
  /// schema that says the constraints exist while none of them do anything.
  ///
  /// It must be set in `onConfigure`, which runs before any transaction:
  /// `PRAGMA foreign_keys` is a silent no-op inside one, and
  /// [_syncCrfsTable] does its clear-and-repopulate in `db.transaction`.
  ///
  /// One hook covers both engines. [init] swaps
  /// `databaseFactory = databaseFactoryFfi` on desktop, so the same
  /// `openDatabase` call reaches native sqflite on mobile and
  /// `sqflite_common_ffi` on Windows/Linux/macOS.
  @visibleForTesting
  static OpenDatabaseOptions surveyOpenOptions() => OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );

  /// Opens a database at [path] the way production opens one.
  ///
  /// Exists so the pragma above can be verified on the real open path rather
  /// than on a hand-rolled one. Pass `inMemoryDatabasePath` from a test.
  @visibleForTesting
  static Future<Database> openSurveyDatabaseForTesting(String path) =>
      databaseFactory.openDatabase(path, options: surveyOpenOptions());

  static Future<void> _syncDatabaseSchema(
      String surveyId, Database db, Map<String, dynamic> manifest) async {
    try {
      // 1. Create and Populate CRFS Table
      await _syncCrfsTable(surveyId, db, manifest);

      // 1b. Create Form Changes Table
      await _syncFormChangesTable(surveyId, db);

      // 1c. Import CSV files as tables
      await _importCsvFiles(surveyId, db);

      // 2. Create Survey Tables from XMLs.
      //
      // The crfs rows are read first because they carry the constraints a
      // survey table is created with -- its primary key, which form is its
      // parent, and which column links the two. _syncCrfsTable has already
      // run, so the table is populated.
      final crfsByTable = await _readCrfsByTable(db);

      final xmlFiles = manifest['xmlFiles'] as List?;
      if (xmlFiles != null) {
        final ordered = SurveyTableSchema.orderByParentFirst(
          xmlFiles.map((f) => f.toString()).toList(),
          crfsByTable,
        );
        for (final xmlFile in ordered) {
          await _syncSurveyTable(surveyId, db, xmlFile,
              crfsByTable: crfsByTable);
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

    // Treat all columns as TEXT for simplicity and flexibility.
    //
    // The table name is a CSV *filename* and the columns are its header row --
    // the least controlled identifiers that reach SQL anywhere in the app, and
    // the only ones not written by SurveyGen. Both go through the guard, which
    // also means a header carrying a space now imports instead of failing the
    // CREATE with a syntax error.
    final table = SurveyTableSchema.quoteIdentifier(tableName);
    final columns =
        headers.map(SurveyTableSchema.quoteIdentifier).toList(growable: false);

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $table '
      '(${columns.map((c) => '$c TEXT').join(', ')})',
    );

    // Every statement below is built here rather than through sqflite's
    // `delete`/`insert` helpers, which interpolate the table and column names
    // they are given **raw**. Quoting only the CREATE was not enough: the
    // DELETE on the next line failed on the same name the CREATE had just
    // accepted, so the guard has to run the length of the method or it buys
    // nothing here.
    await db.execute('DELETE FROM $table');

    final placeholders = List.filled(columns.length, '?').join(', ');
    final insert =
        'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)';

    final batch = db.batch();
    for (final row in rows) {
      batch.rawInsert(insert, [
        for (final header in headers) row[header] ?? '',
      ]);
    }

    await batch.commit(noResult: true);
    _log('Imported ${rows.length} rows into $tableName');
  }

  /// The `crfs` schema, column by column, so that creating the table and
  /// migrating an older one cannot disagree about what it should contain.
  static const Map<String, String> _crfsColumns = {
    'display_order': 'INTEGER DEFAULT 0',
    'tablename': 'TEXT',
    'primarykey': 'TEXT',
    'displayname': 'TEXT',
    'isbase': 'INTEGER DEFAULT 0',
    'linkingfield': 'TEXT',
    'parenttable': 'TEXT',
    'incrementfield': 'TEXT',
    'requireslink': 'INTEGER DEFAULT 0',
    'idconfig': 'TEXT',
    'repeat_count_field': 'TEXT',
    'auto_start_repeat': 'INTEGER',
    'repeat_enforce_count': 'INTEGER',
    'display_fields': 'TEXT',
    'entry_condition': 'TEXT',
  };

  /// Public to allow the create-vs-migrate schema path to be verified
  /// without initializing the application's survey database registry.
  @visibleForTesting
  static Future<void> syncCrfsTableForTesting(
          String surveyId, Database db, Map<String, dynamic> manifest) =>
      _syncCrfsTable(surveyId, db, manifest);

  /// Brings the `crfs` form-configuration table in line with the manifest.
  ///
  /// The table is the app's list of questionnaires: if it ends up empty the
  /// survey has no forms and is unusable, so both halves of this are written
  /// to fail safe. Missing columns are added by `ALTER TABLE` before anything
  /// is written -- a device carrying a `crfs` table from an older build must
  /// not be bricked by a manifest that names a column it has never heard of --
  /// and the clear-and-repopulate runs in a transaction, so a row that will
  /// not insert rolls the whole thing back to the previous configuration
  /// rather than leaving no configuration at all.
  static Future<void> _syncCrfsTable(
      String surveyId, Database db, Map<String, dynamic> manifest) async {
    if (!await _tableExists(db, 'crfs')) {
      _log('Creating crfs table for $surveyId...');
      final colDefs =
          _crfsColumns.entries.map((e) => '${e.key} ${e.value}').join(', ');
      await db.execute('CREATE TABLE crfs ($colDefs)');
    } else {
      final existingColumns = await _getTableColumns(db, 'crfs');
      for (final entry in _crfsColumns.entries) {
        if (existingColumns.contains(entry.key)) continue;
        try {
          await db.execute(
              'ALTER TABLE crfs ADD COLUMN ${entry.key} ${entry.value}');
          _log('Added ${entry.key} column to crfs for $surveyId');
        } catch (e) {
          _logError('Failed to add ${entry.key} column to crfs: $e');
        }
      }
    }

    final crfsList = manifest['crfs'] as List?;
    if (crfsList == null) {
      _logError('No "crfs" section found in manifest for $surveyId');
      return;
    }

    final columns = (await _getTableColumns(db, 'crfs')).toSet();

    try {
      await db.transaction((txn) async {
        await txn.delete('crfs');

        for (final item in crfsList) {
          if (item is! Map<String, dynamic>) continue;

          final rowData = <String, dynamic>{};
          for (final entry in item.entries) {
            if (!columns.contains(entry.key.toLowerCase())) {
              // A manifest written for a newer app than this one. The column
              // cannot be stored and this build has no use for it, so the rest
              // of the row is kept rather than failing the whole survey.
              _logError('Ignoring unknown crfs column "${entry.key}" '
                  'for ${item['tablename']} in $surveyId');
              continue;
            }
            // idconfig arrives as a nested object and is stored as JSON text.
            rowData[entry.key] =
                entry.value is Map ? json.encode(entry.value) : entry.value;
          }

          await txn.insert('crfs', rowData);
        }
      });
    } catch (e) {
      _logError('Error populating crfs table from manifest for $surveyId -- '
          'the previous configuration has been kept: $e');
      return;
    }

    final rowCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM crfs')) ??
            0;
    if (rowCount == 0) {
      _logError('crfs table for $surveyId is empty after syncing '
          '${crfsList.length} manifest entries -- no questionnaires will be '
          'listed for this survey');
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

  /// Every `crfs` row, keyed by lowercased `tablename`, with lowercased keys.
  ///
  /// A row with no `tablename` is skipped rather than keyed under `''`, where
  /// it would masquerade as the parent of any form that left `parenttable`
  /// blank.
  static Future<Map<String, Map<String, dynamic>>> _readCrfsByTable(
      Database db) async {
    try {
      if (!await _tableExists(db, 'crfs')) return const {};
      final rows = await db.query('crfs');
      final byTable = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final normalized = row.map((k, v) => MapEntry(k.toLowerCase(), v));
        final name = normalized['tablename']?.toString().trim().toLowerCase();
        if (name == null || name.isEmpty) continue;
        byTable[name] = normalized;
      }
      return byTable;
    } catch (e) {
      _logError('Error reading crfs configuration: $e');
      return const {};
    }
  }

  static Future<void> _syncSurveyTable(
      String surveyId, Database db, String xmlFilename,
      {Map<String, Map<String, dynamic>> crfsByTable = const {}}) async {
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

        final crf = crfsByTable[tableName];
        final parentTable =
            crf?['parenttable']?.toString().trim().toLowerCase() ?? '';

        final statements = SurveyTableSchema.buildSurveyTableStatements(
          tableName: tableName,
          columnNames: dataQuestions.map((q) => q.fieldName).toList(),
          crf: crf,
          parentCrf: parentTable.isEmpty ? null : crfsByTable[parentTable],
          referencedColumnSets:
              SurveyTableSchema.referencedColumnSetsFor(tableName, crfsByTable),
          onSkippedConstraint: (message) => _logError('[$surveyId] $message'),
        );

        for (final statement in statements) {
          await db.execute(statement);
        }

        // The constraints above are declared only at CREATE. SQLite has no
        // `ALTER TABLE ... ADD CONSTRAINT`, so a table that already exists
        // keeps whatever it was created with -- see the else branch, which
        // adds columns and nothing else. That is acceptable only because no
        // survey has been deployed: clearing the databases/ folder is how a
        // development device picks up this schema. It is not a migration
        // path, and once a survey ships it cannot become one.
      } else {
        // Alter table logic.
        //
        // The CREATE branch above builds its SQL through SurveyTableSchema and
        // is quoted; this branch builds its own, so it quotes for itself. Same
        // dictionary-sourced names, same guard -- the two paths disagreeing was
        // the whole gap.
        final quotedTable = SurveyTableSchema.quoteIdentifier(tableName);
        final existingColumns = await _getTableColumns(db, tableName);
        for (final q in dataQuestions) {
          if (!existingColumns.contains(q.fieldName.toLowerCase())) {
            try {
              final column = SurveyTableSchema.quoteIdentifier(q.fieldName);
              await db
                  .execute('ALTER TABLE $quotedTable ADD COLUMN $column TEXT');
              _log('Added column ${q.fieldName} to $tableName');
            } catch (e) {
              _logError('Failed to add column ${q.fieldName}: $e');
            }
          }
        }
        if (!existingColumns.contains('synced_at')) {
          try {
            await db.execute(
                'ALTER TABLE $quotedTable ADD COLUMN synced_at DATETIME');
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

  /// Registers an already-open database under [surveyId] so the public API can
  /// be exercised against an in-memory database, without the survey folder,
  /// manifest and XML files a real initialization needs.
  @visibleForTesting
  static void registerDatabaseForTest(String surveyId, Database db) {
    _databases[surveyId] = db;
    _initializedSurveys.add(surveyId);
  }

  /// Undoes [registerDatabaseForTest]. Does not close the database -- the test
  /// that opened it owns its lifetime.
  @visibleForTesting
  static void unregisterDatabaseForTest(String surveyId) {
    _databases.remove(surveyId);
    _initializedSurveys.remove(surveyId);
  }

  /// Closes a survey's database and forgets it, so the next [init] reopens it.
  ///
  /// [init] is idempotent by design -- `_initializedSurveys` stops it reopening
  /// a database that is already open, which is what makes it safe to call from
  /// several screens. That guard also means a survey re-installed *within one
  /// process* keeps serving the previous version's connection, against a file
  /// that may since have been replaced.
  ///
  /// The field app never hits that: a device installs a package once and
  /// restarts to change it. DataKollecta-SurveyTest hits it constantly, because
  /// a designer regenerates a zip and re-runs without quitting.
  ///
  /// Unlike [unregisterDatabaseForTest] this actually closes the handle, which
  /// is what lets the file be deleted afterwards -- Windows refuses to unlink
  /// an open one. Returns normally when the survey was never opened.
  static Future<void> closeSurvey(String surveyId) async {
    final db = _databases.remove(surveyId);
    _initializedSurveys.remove(surveyId);
    if (db != null) {
      try {
        await db.close();
      } catch (e) {
        _logError('Failed to close database for $surveyId: $e');
      }
    }
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
        final values =
            rowData.values.map((v) => DbBackup.escapeSqlValue(v)).join(', ');
        final sql = 'INSERT INTO $tableName ($columns) VALUES ($values);';
        await DbBackup.write(surveyId, tableName, sql);
      } catch (e) {
        _logError('Failed to write backup for INSERT: $e');
      }
    } catch (e) {
      _logError('Failed to save interview: $e');
      throw DatabaseException('Failed to save interview: $e');
    }
  }

  /// Every row of [tableName], or `null` if the read **failed**.
  ///
  /// The distinction is what [getExistingRecords] throws away, and it matters
  /// for anything deriving a counter: an empty list means "this table holds no
  /// records", which is the normal first-record case, while `null` means "the
  /// contents are unknown". Treating a failed read as an empty table is what
  /// let `IdGenerator` restart a subject-ID counter at 1 and hand out an ID
  /// that was already enrolled -- silently, because the error never surfaced
  /// past this method.
  ///
  /// A **missing table** is deliberately reported as empty rather than `null`:
  /// a table that does not exist cannot hold a colliding ID, so starting a
  /// counter at 1 there is correct. Only an actual failure is `null`.
  ///
  /// The subject-ID counter no longer comes through here at all -- it uses
  /// [tryGetMaxIdIncrement], which carries the same `null` contract without
  /// materialising the table. This method stays because the record-list
  /// screens genuinely want every row.
  static Future<List<Map<String, dynamic>>?> tryGetExistingRecords(
      String surveyId, String tableName,
      {String? orderBy}) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return const [];

      final results = await db.query(tableName, orderBy: orderBy);

      // Normalize keys to lowercase to avoid case-sensitivity issues across platforms
      return results.map((row) {
        return row.map((key, value) => MapEntry(key.toLowerCase(), value));
      }).toList();
    } catch (e) {
      _logError('Error fetching records: $e');
      return null;
    }
  }

  /// Every row of [tableName], with a failed read reported as no rows.
  ///
  /// Callers that only display records are fine with this. Anything deriving
  /// an identifier must use [tryGetMaxIdIncrement] (or [tryGetExistingRecords]
  /// where whole rows are genuinely needed) and handle `null` -- reading
  /// increment 1 out of a failure's empty list is what handed a second subject
  /// an already-enrolled ID.
  ///
  /// The child-increment violation this comment used to describe is closed.
  /// `parent_id_selector_screen._getNextIncrementNumber` derived a child
  /// increment straight from this method, so a failed read there became an
  /// empty list, became increment 1, became a duplicate linenum inside one
  /// household. It was also a second, disagreeing implementation of
  /// [getNextIncrementValue]: the two grouped a household's children by
  /// different columns (`crfs.primarykey`'s first field versus
  /// `crfs.linkingfield`), so which answer an interviewer got depended only
  /// on which screen they came through. Both call sites now go through
  /// [getNextIncrementValue], which groups by `linkingfield` -- the column
  /// parentage and the foreign key are both defined on.
  static Future<List<Map<String, dynamic>>> getExistingRecords(
      String surveyId, String tableName,
      {String? orderBy}) async {
    return await tryGetExistingRecords(surveyId, tableName, orderBy: orderBy) ??
        const [];
  }

  /// The highest increment already issued under [baseId] in [fieldName], or
  /// `null` if the read **failed**.
  ///
  /// `0` means no record carries this base ID yet -- the ordinary first-record
  /// case. `null` carries the same meaning it does in [tryGetExistingRecords]
  /// and is what drives [IdGenerator]'s degraded-ID path, so the distinction
  /// between "empty" and "unknown" survives this method too.
  ///
  /// Replaces reading the entire table into Dart to compute one integer. On a
  /// 20,000-row survey table that read mapped and lowercased every key of every
  /// row while the interviewer waited; the work here is bounded by the number of
  /// rows sharing [baseId], which the increment width itself caps.
  static Future<int?> tryGetMaxIdIncrement({
    required String surveyId,
    required String tableName,
    required String fieldName,
    required String baseId,
    required int incrementLength,
    required int sentinelFloor,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      // A table that does not exist cannot hold a colliding ID, so a counter
      // starting at 1 there is correct -- the same reason
      // tryGetExistingRecords reports a missing table as empty, not as a
      // failure.
      if (!await _tableExists(db, tableName)) return 0;

      return await maxIdIncrementIn(
        db,
        tableName: tableName,
        fieldName: fieldName,
        baseId: baseId,
        incrementLength: incrementLength,
        sentinelFloor: sentinelFloor,
      );
    } catch (e) {
      _logError('Error reading the highest "$fieldName" under "$baseId" in '
          '"$tableName": $e');
      return null;
    }
  }

  /// The SQL half of [tryGetMaxIdIncrement], against an already-open database.
  ///
  /// Separated so the query can be tested against a real SQLite file without
  /// standing up the survey-database registry, following
  /// [syncCrfsTableForTesting].
  ///
  /// Three conditions between them accept exactly the values the old Dart scan
  /// accepted, which is what makes this a faithful replacement rather than a
  /// near-enough one:
  ///
  /// * `substr(<col>, 1, n) = <baseId>` is the case-sensitive prefix test
  ///   (`String.startsWith`). It is used in preference to `LIKE '<baseId>%'`
  ///   because `LIKE` is case-insensitive for ASCII in SQLite *and* would treat
  ///   `%` or `_` inside a dictionary-supplied prefix as a wildcard.
  /// * `length(<col>) = n + incrementLength` is the exact-suffix-width test.
  /// * `substr(<col>, n + 1) GLOB '[0-9][0-9]...'` is the numeric-suffix test.
  ///   `GLOB` rather than a bare `CAST`, because `CAST('12x' AS INTEGER)` is
  ///   `12` in SQLite while `int.tryParse('12x')` is null -- without this a
  ///   malformed value could advance the counter.
  ///
  /// The reserved sentinel band is excluded here rather than after the fact,
  /// for the reason [IdGenerator.nextIncrementAfter] documents: a degraded ID
  /// must not push `MAX` to the top of the range and exhaust it forever.
  @visibleForTesting
  static Future<int> maxIdIncrementIn(
    Database db, {
    required String tableName,
    required String fieldName,
    required String baseId,
    required int incrementLength,
    required int sentinelFloor,
  }) async {
    final table = SurveyTableSchema.quoteIdentifier(tableName);
    final column = SurveyTableSchema.quoteIdentifier(fieldName);
    final suffixStart = baseId.length + 1;
    final digitPattern = '[0-9]' * incrementLength;

    final rows = await db.rawQuery(
      'SELECT MAX(CAST(substr($column, ?) AS INTEGER)) AS max_increment '
      'FROM $table '
      'WHERE substr($column, 1, ?) = ? '
      'AND length($column) = ? '
      'AND substr($column, ?) GLOB ? '
      'AND CAST(substr($column, ?) AS INTEGER) < ?',
      [
        suffixStart,
        baseId.length,
        baseId,
        baseId.length + incrementLength,
        suffixStart,
        digitPattern,
        suffixStart,
        sentinelFloor,
      ],
    );

    // MAX over no rows is SQL NULL, which is the empty-table case.
    final value = rows.isEmpty ? null : rows.first['max_increment'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Collapses rows that share the same `uniqueid`, keeping only the one
  /// with the lexicographically-greatest `lastmod` (ISO-8601 timestamps sort
  /// correctly as strings -- every write goes through the one
  /// `DateTime.now().toIso8601String()` call site in auto_fields.dart, so the
  /// format is uniform). Mirrors avert_data's process_data.py `is_older()`,
  /// the server-side pipeline's own resolution of the same condition.
  ///
  /// A double-tap on Finish (fixed in 1.1.0+7 with a debounce guard) could
  /// save the same interview twice before that fix landed. `uniqueid` is not
  /// a real SQLite PRIMARY KEY on any survey where the generator writes it as
  /// a declared question (see `_syncSurveyTable`'s `hasUniqueId` branch,
  /// which every current survey takes), so duplicate-`uniqueid` rows are a
  /// structurally possible read-time condition, not just a closed historical
  /// bug. This never deletes anything -- it only decides which row the UI
  /// treats as "the" record.
  ///
  /// Rows with *different* `uniqueid`s are never merged, even if they share
  /// every other field (e.g. the same subjid) -- that would hide a genuine
  /// identity collision instead of a technical duplicate-save artifact.
  static List<Map<String, dynamic>> collapseDuplicateUniqueIds(
    List<Map<String, dynamic>> records,
  ) {
    final bestByKey = <String, Map<String, dynamic>>{};
    final order = <String>[];
    var unkeyedCount = 0;

    for (final record in records) {
      final uniqueId = record['uniqueid']?.toString();
      final key = (uniqueId == null || uniqueId.isEmpty)
          // No uniqueid to key on -- give it its own synthetic key so rows
          // without one never collide with each other or a real uniqueid.
          ? '\u0000${unkeyedCount++}'
          : uniqueId;

      final existing = bestByKey[key];
      if (existing == null) {
        order.add(key);
        bestByKey[key] = record;
        continue;
      }

      final candidateLastmod = record['lastmod']?.toString() ?? '';
      final existingLastmod = existing['lastmod']?.toString() ?? '';
      if (candidateLastmod.compareTo(existingLastmod) > 0) {
        bestByKey[key] = record;
      }
    }

    return [for (final key in order) bestByKey[key]!];
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

  /// The value written into an increment field when the counter could not be
  /// read.
  ///
  /// Zero, because a child counter starts at 1 -- so `0` is a value no
  /// legitimate record can hold, and `WHERE <incrementfield> = 0` finds every
  /// degraded row. The old fallback of `1` was indistinguishable from a
  /// legitimate first child, so a duplicate left no trace and nobody ever
  /// found out.
  ///
  /// Deliberately *not* a reserved band at the top of a range, the way
  /// [IdGenerator] does it for subject IDs. That band is derived from
  /// `idconfig.incrementLength`, which sizes a primary key's optional numeric
  /// suffix and says nothing about how many children a parent may have --
  /// nothing bounds that, so there is no width to derive a band from.
  ///
  /// Zero also needs no exclusion from the `MAX` in [nextIncrementValueIn]:
  /// `MAX(1,2,3,4,0)` is still 4, so one failed read cannot poison that
  /// parent's sequence. A top-of-range sentinel would have needed an extra
  /// `AND` to avoid pushing every subsequent child to 1000, 1001 and upward
  /// forever.
  ///
  /// It does not need to be collision-free. Every row carries a `uniqueid`
  /// and every child carries its parent's `parent_uniqueid`, so parentage no
  /// longer depends on this ordinal and several zeroes under one parent stay
  /// reconcilable after the fact.
  static const int degradedIncrementValue = 0;

  /// Get the next auto-increment value for a field (e.g., linenum, netnum).
  ///
  /// Children are grouped by the CRF's `linkingfield` -- the column that
  /// defines parentage, and the one the foreign key is declared on. This used
  /// to be `crfs.primarykey`'s *first* field here and `linkingfield` in
  /// `parent_id_selector_screen`, so which answer an interviewer got depended
  /// only on which screen they came through.
  static Future<int> getNextIncrementValue({
    required String surveyId,
    required String tableName,
    required String incrementField,
    required String linkingField,
    required String linkingValue,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      return await nextIncrementValueIn(
        db,
        tableName: tableName,
        incrementField: incrementField,
        linkingField: linkingField,
        linkingValue: linkingValue,
      );
    } catch (e) {
      // Same shape of hazard as the subject-ID counter (see
      // IdGenerator._getNextIncrement): a failed read here used to restart
      // this parent's child counter at 1 and produce a duplicate
      // linenum/netnum within the household -- with no trace, because `1` is
      // exactly what a legitimate first child gets.
      _logError('Error getting next $incrementField for $tableName '
          '($linkingField=$linkingValue) -- issuing '
          '$degradedIncrementValue so the record is still saved and the '
          'degraded value is identifiable: $e');
      return degradedIncrementValue;
    }
  }

  /// The next [incrementField] for one parent, run against an open [db].
  ///
  /// Split out for the same reason [maxIdIncrementIn] is: the query is the
  /// part worth testing, and resolving a surveyId to a database is not
  /// reachable from a test. Throws rather than returning a fallback -- the
  /// caller owns the failure policy, and today that policy is
  /// [getNextIncrementValue]'s logged [degradedIncrementValue].
  @visibleForTesting
  static Future<int> nextIncrementValueIn(
    Database db, {
    required String tableName,
    required String incrementField,
    required String linkingField,
    required String linkingValue,
  }) async {
    if (!await _tableExists(db, tableName)) return 1;

    // All three identifiers come from a data dictionary's crfs sheet and
    // cannot be bound as parameters, so they are quoted rather than
    // interpolated raw -- the same treatment [maxIdIncrementIn] already gives
    // the subject-ID query. This was the one place that bypassed the guard.
    final column = SurveyTableSchema.quoteIdentifier(incrementField);
    final table = SurveyTableSchema.quoteIdentifier(tableName);
    final keyColumn = SurveyTableSchema.quoteIdentifier(linkingField);

    final results = await db.rawQuery(
      'SELECT MAX(CAST($column AS INTEGER)) as maxValue '
      'FROM $table WHERE $keyColumn = ?',
      [linkingValue],
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
  }

  /// The next [incrementField] for **every** parent in [tableName], keyed by
  /// linking value. `null` means the read failed.
  ///
  /// One grouped query for the whole table, because the caller
  /// (`parent_id_selector_screen`) needs a number beside every parent in a
  /// list. Asking [getNextIncrementValue] once per parent would be a query per
  /// household; the screen it replaced was worse still -- a full-table read
  /// into Dart per visible row per rebuild.
  ///
  /// A parent with no children yet is simply absent from the map, which the
  /// caller reads as 1. That keeps "no children" and "read failed" distinct at
  /// this level, the same distinction [tryGetMaxIdIncrement] preserves.
  static Future<Map<String, int>?> tryGetNextIncrementValues({
    required String surveyId,
    required String tableName,
    required String incrementField,
    required String linkingField,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      return await nextIncrementValuesIn(
        db,
        tableName: tableName,
        incrementField: incrementField,
        linkingField: linkingField,
      );
    } catch (e) {
      _logError('Error getting next $incrementField values for $tableName '
          'grouped by $linkingField: $e');
      return null;
    }
  }

  /// The SQL half of [tryGetNextIncrementValues], against an open [db].
  @visibleForTesting
  static Future<Map<String, int>> nextIncrementValuesIn(
    Database db, {
    required String tableName,
    required String incrementField,
    required String linkingField,
  }) async {
    if (!await _tableExists(db, tableName)) return const {};

    // Identifiers come from a data dictionary's crfs sheet and cannot be
    // bound, so they are quoted -- same guard as [nextIncrementValueIn].
    final column = SurveyTableSchema.quoteIdentifier(incrementField);
    final table = SurveyTableSchema.quoteIdentifier(tableName);
    final keyColumn = SurveyTableSchema.quoteIdentifier(linkingField);

    final results = await db.rawQuery(
      'SELECT $keyColumn AS linkingValue, '
      'MAX(CAST($column AS INTEGER)) AS maxValue '
      'FROM $table WHERE $keyColumn IS NOT NULL GROUP BY $keyColumn',
    );

    final next = <String, int>{};
    for (final row in results) {
      final key = row['linkingValue']?.toString();
      if (key == null || key.isEmpty) continue;
      final maxValue = row['maxValue'];
      if (maxValue is int) {
        next[key] = maxValue + 1;
      } else if (maxValue is String) {
        next[key] = (int.tryParse(maxValue) ?? 0) + 1;
      }
    }
    return next;
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
            .map((e) => '${e.key} = ${DbBackup.escapeSqlValue(e.value)}')
            .join(', ');
        final sql =
            "UPDATE $tableName SET $setClause WHERE uniqueid = '${DbBackup.escapeSqlString(uniqueId)}';";
        await DbBackup.write(surveyId, tableName, sql);
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
        final oldValueStr = AnswerEquality.canonical(oldValue);
        final newValueStr = AnswerEquality.canonical(newValue);

        if (!AnswerEquality.sameAnswer(oldValueStr, newValueStr)) {
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

  /// Whether [value] does not already appear in [tableName].[columnName].
  ///
  /// **Fails open: any error reports "unique".** That is pre-existing and
  /// deliberate at the call site -- a uniqueCheck that cannot be evaluated
  /// must not block an interviewer mid-form -- but it is worth knowing that a
  /// name the identifier guard refuses arrives here as a silent pass rather
  /// than an error. Pinned by test.
  static Future<bool> isValueUnique(String surveyId, String tableName,
      String columnName, String value) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      // Both come from a data dictionary -- the table from the XML filename,
      // the column from a question's fieldName -- and neither can be bound.
      // This is on a hot path: it runs on every commit of a uniqueCheck field.
      final table = SurveyTableSchema.quoteIdentifier(tableName);
      final column = SurveyTableSchema.quoteIdentifier(columnName);
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE $column = ?',
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
      // Lowercased, like every other crfs consumer here. The cell is typed by
      // hand into a worksheet, and callers compare these names against
      // lowercased fieldnames and against the lowercased keys
      // [getAllPrimaryKeys] returns -- so a sheet saying `HHID` used to make
      // every one of those comparisons miss silently. SQLite matches column
      // names case-insensitively, so a query built from these still works
      // whatever case the column was created with.
      return pkString
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// This form's `crfs` row, or null when the sheet has no row for it.
  ///
  /// **Null means "no such row", never "the read failed"** -- that is the
  /// whole reason this exists alongside [getCrfConfig], which cannot tell the
  /// two apart. A caller that reports *why* it fell back needs the
  /// difference: `ChildIncrementService` used to land on its no-linkingfield
  /// branch when the database could not be read at all, and log a dictionary
  /// problem that did not exist.
  ///
  /// The strict-underneath / tolerant-wrapper pairing [getCrfConfig] uses, the
  /// same as [maxIdIncrementIn] under [tryGetMaxIdIncrement].
  static Future<Map<String, dynamic>?> getCrfConfigOrThrow(
      String surveyId, String tableName) async {
    final db = await _getDbOrThrow(surveyId);
    final results =
        await db.query('crfs', where: 'tablename = ?', whereArgs: [tableName]);
    return results.isNotEmpty ? results.first : null;
  }

  /// This form's `crfs` row, or null if there is none **or the read failed**.
  ///
  /// The tolerant reading, for callers that treat an unreadable database and
  /// an unconfigured form the same way -- both screens and
  /// `RepeatCountService` do, deliberately: a degraded read there costs a
  /// feature, not a crash. Anything that names the reason in a log or a
  /// message wants [getCrfConfigOrThrow] instead.
  static Future<Map<String, dynamic>?> getCrfConfig(
      String surveyId, String tableName) async {
    try {
      return await getCrfConfigOrThrow(surveyId, tableName);
    } catch (e) {
      return null;
    }
  }

  /// Every existing primary-key tuple in [tableName], keyed by lowercased
  /// column name.
  ///
  /// Lowercasing the keys matters. `pkFields` comes from `crfs.primarykey`
  /// verbatim -- a worksheet cell -- while the returned column names come from
  /// SQLite, so a sheet saying `HHID` against a column named `hhid` produced
  /// rows whose values all read as null. The caller builds a duplicate-check
  /// signature by joining those lookups, so every record collapsed to the
  /// same empty signature: either every new record looked like a duplicate,
  /// or (once one such row existed) none of them did.
  static Future<List<Map<String, dynamic>>> getAllPrimaryKeys(
      String surveyId, String tableName, List<String> pkFields) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      // Select only the primary key fields
      final rows = await db.query(tableName, columns: pkFields);
      return rows
          .map((row) => row.map((k, v) => MapEntry(k.toLowerCase(), v)))
          .toList();
    } catch (e) {
      _logError('Failed to get all primary keys: $e');
      return [];
    }
  }

  /// How many rows [tableName] holds, or `null` if the read **failed**.
  ///
  /// The same distinction [tryGetMaxIdIncrement] preserves, and for the same
  /// reason. [getRecordCount] reports a failure as `0`, and that zero used to
  /// reach `RepeatCountService`, which could then write `nmembers = 0` onto a
  /// household that has five members. The only thing preventing that was the
  /// count question happening to declare `minvalue='1'`; a dictionary that
  /// omits the `numeric_check` had no protection at all.
  ///
  /// A **missing table** is `0`, not `null`: a table that does not exist
  /// genuinely holds no rows.
  static Future<int?> tryGetRecordCount({
    required String surveyId,
    required String tableName,
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return 0;

      // `tableName` and `where` come from a data dictionary's crfs sheet and
      // cannot be bound, so the table goes through the identifier guard.
      // `where` is a fragment only the caller can build, so the caller quotes
      // the column in it -- see RepeatCountService, the only place that passes
      // one -- and its values are always bound via [whereArgs].
      final table = SurveyTableSchema.quoteIdentifier(tableName);

      final results = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $table'
        '${where != null ? ' WHERE $where' : ''}',
        whereArgs,
      );

      if (results.isEmpty) return 0;
      return (results.first['count'] as int?) ?? 0;
    } catch (e) {
      _logError('Error counting records in $tableName: $e');
      return null;
    }
  }

  /// How many rows [tableName] holds, with a failed read reported as `0`.
  ///
  /// Callers that only display a number are fine with this. Anything that
  /// *writes* the count back must use [tryGetRecordCount] and handle `null`.
  static Future<int> getRecordCount({
    required String surveyId,
    required String tableName,
    String? where,
    List<dynamic>? whereArgs,
  }) async =>
      await tryGetRecordCount(
        surveyId: surveyId,
        tableName: tableName,
        where: where,
        whereArgs: whereArgs,
      ) ??
      0;

  /// Reads a single column from the first row matching [where].
  ///
  /// The read-side counterpart to [updateField]; returns null when the table,
  /// the column or the row is missing, all of which are indistinguishable from
  /// a stored NULL to the caller by design -- callers that must tell a skipped
  /// question from an absent row check the row separately.
  static Future<dynamic> getFieldValue({
    required String surveyId,
    required String tableName,
    required String field,
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return null;

      final rows = await db.query(tableName,
          where: where, whereArgs: whereArgs, limit: 1);
      if (rows.isEmpty) return null;

      final normalized = rows.first.map((k, v) => MapEntry(k.toLowerCase(), v));
      return normalized[field.toLowerCase()];
    } catch (e) {
      _logError('Error reading field $field from $tableName: $e');
      return null;
    }
  }

  /// Writes a single column on every row matching [where].
  ///
  /// Goes through the same bookkeeping as a full save rather than writing the
  /// column alone: `synced_at` is cleared so an already-uploaded row is sent
  /// again with the corrected value, `lastmod` is refreshed so the row still
  /// wins in [collapseDuplicateUniqueIds], and a `formchanges` row is written
  /// so a value the app changed on the interviewer's behalf is as auditable as
  /// one they typed. A write that would not change the stored value is skipped
  /// entirely, so it never manufactures a spurious re-upload.
  static Future<void> updateField({
    required String surveyId,
    required String tableName,
    required String field,
    required dynamic value,
    required String where,
    required List<dynamic> whereArgs,
    bool recordChange = true,
  }) async {
    try {
      final db = await _getDbOrThrow(surveyId);
      if (!await _tableExists(db, tableName)) return;

      final columns = await _getTableColumns(db, tableName);
      if (!columns.contains(field.toLowerCase())) {
        _logError('Cannot update $tableName.$field: no such column');
        return;
      }

      final rows =
          await db.query(tableName, where: where, whereArgs: whereArgs);
      if (rows.isEmpty) return;

      final newValueStr = AnswerEquality.canonical(value);
      // The audit trail is a nice-to-have; the corrected value is not. A
      // settings read that fails must not cost us the write itself.
      String? surveyorId;
      if (recordChange) {
        try {
          surveyorId = await SettingsService().surveyorId;
        } catch (e) {
          _logError('Could not read surveyor id for change log: $e');
        }
      }
      final now = DateTime.now().toIso8601String();

      for (final row in rows) {
        final normalized = row.map((k, v) => MapEntry(k.toLowerCase(), v));
        final oldValueStr =
            AnswerEquality.canonical(normalized[field.toLowerCase()]);

        if (AnswerEquality.sameAnswer(oldValueStr, newValueStr)) continue;

        final rowData = <String, dynamic>{field: value};
        // Mirrors _prepareRowData: an edit has to re-upload even if an earlier
        // version of this row was already sent.
        if (columns.contains('synced_at')) rowData['synced_at'] = null;
        if (columns.contains('lastmod')) rowData['lastmod'] = now;

        final uniqueId = normalized['uniqueid']?.toString();
        if (uniqueId == null) {
          // No uniqueid to address rows individually (only legacy tables), so
          // the whole match is written in one statement and the loop is done.
          await db.update(tableName, rowData,
              where: where, whereArgs: whereArgs);
          _log('Updated $tableName.$field to $newValueStr where $where');
          return;
        }

        await db.update(tableName, rowData,
            where: 'uniqueid = ?', whereArgs: [uniqueId]);

        if (recordChange && await _tableExists(db, 'formchanges')) {
          await db.insert('formchanges', {
            'tablename': tableName,
            'fieldname': field,
            'uniqueid': uniqueId,
            'oldvalue': oldValueStr,
            'newvalue': newValueStr,
            'changed_at': now,
            'changeuniqueid': const Uuid().v4(),
            'surveyor_id': surveyorId,
          });
        }

        _log('Updated $tableName.$field from $oldValueStr to $newValueStr');
      }
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
      // Two of this method's callers pass a dictionary-sourced table name
      // (_syncSurveyTable and updateInterview); the rest pass literals. PRAGMA
      // is still SQL, so the name is quoted like any other.
      final table = SurveyTableSchema.quoteIdentifier(tableName);
      final result = await db.rawQuery('PRAGMA table_info($table)');

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

  static Future<Directory> _getSurveysDirectory() => AppPaths.surveysDir();

  static void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[DbService] $message');
    }
  }

  static void _logError(String message) {
    debugPrint('[DbService ERROR] $message');
  }
}
