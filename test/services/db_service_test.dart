import 'package:flutter_test/flutter_test.dart';
// `DatabaseException` is declared by both sqflite_common and this project;
// this file wants the latter, which is what
// `SurveyTableSchema.quoteIdentifier` throws. It now lives in
// database_exception.dart and is re-exported by db_service.dart.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;
import 'package:datakollecta/services/auto_fields.dart';
import 'package:datakollecta/services/db_service.dart';
import 'package:datakollecta/services/survey_table_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit null update values overwrite old SQLite values', () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    await database.execute(
      'CREATE TABLE enrollee (uniqueid TEXT PRIMARY KEY, need_vac_cov TEXT)',
    );
    await database.insert('enrollee', {
      'uniqueid': 'record-1',
      'need_vac_cov': '1',
    });

    final updateValues = DbService.prepareUpdateRowData(
      {
        'uniqueid': 'record-1',
        'need_vac_cov': null,
      },
      {'uniqueid', 'need_vac_cov'},
    );

    expect(updateValues.containsKey('need_vac_cov'), isTrue);
    expect(updateValues['need_vac_cov'], isNull);

    await database.update(
      'enrollee',
      updateValues,
      where: 'uniqueid = ?',
      whereArgs: ['record-1'],
    );
    final rows = await database.query(
      'enrollee',
      where: 'uniqueid = ?',
      whereArgs: ['record-1'],
    );

    expect(rows.single['need_vac_cov'], isNull);
  });

  test('CSV import keeps quoted commas and escaped quotes intact', () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    // Trailing commas (unnamed column), an embedded comma, escaped quotes,
    // LF line endings, and a final row missing its trailing separator.
    await DbService.importCsvContent(
      database,
      'schools',
      'mrccode,schoolcode,schoolname,\n'
      '40,21090008,"St Mary\'s, Apac",\n'
      '40,21090009,"BUSAMBEKO ""A""",\n'
      '47,21070001,Atauso primary school',
    );

    final rows = await database.query('schools', orderBy: 'rowid');

    expect(rows.length, 3);
    expect(rows[0]['schoolname'], "St Mary's, Apac");
    expect(rows[0]['mrccode'], '40');
    expect(rows[0]['schoolcode'], '21090008');
    expect(rows[1]['schoolname'], 'BUSAMBEKO "A"');
    expect(rows[2]['schoolname'], 'Atauso primary school');
    expect(rows[2]['mrccode'], '47');

    // The unnamed trailing column must not become a SQL column.
    final columns = (await database.rawQuery('PRAGMA table_info(schools)'))
        .map((row) => row['name'])
        .toList();
    expect(columns, ['mrccode', 'schoolcode', 'schoolname']);
  });

  test('CSV import replaces previous contents', () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    await DbService.importCsvContent(
        database, 'villages', 'code,name\n1,Old Village\n');
    await DbService.importCsvContent(
        database, 'villages', 'code,name\n2,New Village\n');

    final rows = await database.query('villages');

    expect(rows.length, 1);
    expect(rows.single['name'], 'New Village');
  });

  test('CSV import preserves zero-padded codes', () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    await DbService.importCsvContent(
      database,
      'villages',
      'mrcid,villageid,village\n056,01,Namwiwa\n056,02,Kiganda\n',
    );

    final rows = await database.query('villages', orderBy: 'rowid');

    expect(rows[0]['mrcid'], '056');
    expect(rows[0]['villageid'], '01');
    expect(rows[1]['villageid'], '02');

    // A query written with the unpadded value still finds the row, because
    // SQLite compares the two numerically once cast.
    final matched = await database.rawQuery(
      'SELECT village FROM villages WHERE CAST(mrcid AS INTEGER) = CAST(? AS INTEGER)',
      ['56'],
    );
    expect(matched.length, 2);
  });

  test('formchanges is created with changeuniqueid/surveyor_id/synced_at',
      () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    await DbService.syncFormChangesTableForTesting('survey1', database);

    final columns = (await database.rawQuery('PRAGMA table_info(formchanges)'))
        .map((row) => row['name'])
        .toList();

    expect(columns, containsAll(['changeuniqueid', 'surveyor_id', 'synced_at']));

    final indexes =
        await database.rawQuery('PRAGMA index_list(formchanges)');
    expect(
      indexes.any((i) => i['name'] == 'idx_formchanges_changeuniqueid'),
      isTrue,
    );

    // The unique index must tolerate more than one legacy row with a NULL
    // changeuniqueid -- SQLite allows this, and it's how existing GiSTX
    // records stay excluded from HTTP sync without a backfill.
    await database.insert('formchanges', {
      'tablename': 't',
      'fieldname': 'f',
      'uniqueid': 'u1',
      'newvalue': 'a',
    });
    await database.insert('formchanges', {
      'tablename': 't',
      'fieldname': 'f',
      'uniqueid': 'u2',
      'newvalue': 'b',
    });
    final rows = await database.query('formchanges');
    expect(rows.length, 2);
  });

  test('a legacy formchanges table is migrated without losing existing rows',
      () async {
    sqfliteFfiInit();
    final database =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);

    // The pre-Phase-3 schema, created directly rather than through
    // DbService so this test pins the migration path regardless of future
    // changes to the "create" branch.
    await database.execute('''
      CREATE TABLE formchanges (
          changeid     INTEGER PRIMARY KEY AUTOINCREMENT,
          tablename    TEXT NOT NULL,
          fieldname    TEXT NOT NULL,
          uniqueid     TEXT NOT NULL,
          oldvalue     TEXT,
          newvalue     TEXT,
          changed_at   DATETIME DEFAULT (CURRENT_TIMESTAMP)
      )
    ''');
    await database.insert('formchanges', {
      'tablename': 'enrollee',
      'fieldname': 'age',
      'uniqueid': 'record-1',
      'oldvalue': '10',
      'newvalue': '11',
    });

    await DbService.syncFormChangesTableForTesting('survey1', database);

    final columns = (await database.rawQuery('PRAGMA table_info(formchanges)'))
        .map((row) => row['name'])
        .toList();
    expect(columns, containsAll(['changeuniqueid', 'surveyor_id', 'synced_at']));

    final rows = await database.query('formchanges');
    expect(rows.length, 1);
    expect(rows.single['uniqueid'], 'record-1');
    expect(rows.single['newvalue'], '11');
    expect(rows.single['changeuniqueid'], isNull);
  });

  test('prepareUpdateRowData clears synced_at only when the column exists',
      () {
    final withColumn = DbService.prepareUpdateRowData(
      {'uniqueid': 'record-1', 'need_vac_cov': '1'},
      {'uniqueid', 'need_vac_cov', 'synced_at'},
    );
    expect(withColumn.containsKey('synced_at'), isTrue);
    expect(withColumn['synced_at'], isNull);

    final withoutColumn = DbService.prepareUpdateRowData(
      {'uniqueid': 'record-1', 'need_vac_cov': '1'},
      {'uniqueid', 'need_vac_cov'},
    );
    expect(withoutColumn.containsKey('synced_at'), isFalse);
  });

  test(
      'collapseDuplicateUniqueIds keeps only the most-recent-lastmod row per uniqueid '
      '(the real subject 21040040057 scenario: 3 identical rows, only lastmod differs)',
      () {
    final result = DbService.collapseDuplicateUniqueIds([
      {
        'uniqueid': '08edc212-a666-4f46-95a3-45c59ac3d63c',
        'subjid': '21040040057',
        'lastmod': '2026-08-07T10:35:41.222238',
      },
      {
        'uniqueid': '08edc212-a666-4f46-95a3-45c59ac3d63c',
        'subjid': '21040040057',
        'lastmod': '2026-08-07T10:35:45.805192',
      },
      {
        'uniqueid': '08edc212-a666-4f46-95a3-45c59ac3d63c',
        'subjid': '21040040057',
        'lastmod': '2026-08-07T10:35:40.882014',
      },
    ]);

    expect(result.length, 1);
    expect(result.single['lastmod'], '2026-08-07T10:35:45.805192');
  });

  test(
      'collapseDuplicateUniqueIds only collapses the duplicated group and '
      'preserves first-seen order for the rest', () {
    final a1 = {'uniqueid': 'a', 'lastmod': 't1'};
    final b = {'uniqueid': 'b', 'lastmod': 't1'};
    final a2 = {'uniqueid': 'a', 'lastmod': 't2'};
    final c = {'uniqueid': 'c', 'lastmod': 't1'};

    final result = DbService.collapseDuplicateUniqueIds([a1, b, a2, c]);

    expect(result.length, 3);
    expect(result[0]['uniqueid'], 'a');
    expect(result[0]['lastmod'], 't2'); // the newer of the two "a" rows
    expect(result[1]['uniqueid'], 'b');
    expect(result[2]['uniqueid'], 'c');
  });

  test(
      'collapseDuplicateUniqueIds never merges different uniqueids, even when '
      'every other field (including lastmod) matches -- the safety-net property '
      'this function must never violate', () {
    final result = DbService.collapseDuplicateUniqueIds([
      {'uniqueid': 'person-a', 'subjid': '21040040057', 'lastmod': 't1'},
      {'uniqueid': 'person-b', 'subjid': '21040040057', 'lastmod': 't1'},
    ]);

    expect(result.length, 2);
    expect(result.map((r) => r['uniqueid']), containsAll(['person-a', 'person-b']));
  });

  test('collapseDuplicateUniqueIds resolves a tie on lastmod without crashing or '
      'double-counting', () {
    final result = DbService.collapseDuplicateUniqueIds([
      {'uniqueid': 'a', 'lastmod': 'same-time'},
      {'uniqueid': 'a', 'lastmod': 'same-time'},
    ]);

    expect(result.length, 1);
  });

  test('collapseDuplicateUniqueIds treats a missing lastmod as older than a real one',
      () {
    final withTimestamp = {'uniqueid': 'a', 'lastmod': '2026-01-01T00:00:00'};
    final result = DbService.collapseDuplicateUniqueIds([
      {'uniqueid': 'a', 'lastmod': null},
      withTimestamp,
    ]);

    expect(result.single, withTimestamp);
  });

  test('collapseDuplicateUniqueIds keeps rows with no uniqueid as separate entries',
      () {
    final result = DbService.collapseDuplicateUniqueIds([
      {'uniqueid': null, 'lastmod': 't1'},
      {'lastmod': 't1'}, // uniqueid key absent entirely
    ]);

    expect(result.length, 2);
  });

  group('crfs table sync', () {
    Future<Database> openDb() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      return db;
    }

    Map<String, dynamic> manifest() => {
          'crfs': [
            {
              'display_order': 1,
              'tablename': 'hh_info',
              'displayname': 'Household Information',
              'isbase': 1,
              'primarykey': 'hhid',
              'linkingfield': 'hhid',
              'idconfig': {
                'prefix': '',
                'fields': [
                  {'name': 'hhnum', 'length': 4}
                ],
                'incrementLength': 0,
              },
            },
            {
              'display_order': 3,
              'tablename': 'hh_members',
              'displayname': 'Household Members',
              'isbase': 0,
              'primarykey': 'hhid,linenum',
              'linkingfield': 'hhid',
              'parenttable': 'hh_info',
              'repeat_count_field': 'nmembers',
              'auto_start_repeat': 2,
              'repeat_enforce_count': 3,
            },
          ]
        };

    test('a fresh install creates the table and loads every form', () async {
      final db = await openDb();

      await DbService.syncCrfsTableForTesting('s1', db, manifest());

      final rows = await db.query('crfs', orderBy: 'display_order ASC');
      expect(rows, hasLength(2));
      expect(rows.first['tablename'], 'hh_info');
      expect(rows.last['repeat_enforce_count'], 3);
      // A nested idconfig object is stored as JSON text, not Dart's toString.
      expect(rows.first['idconfig'], startsWith('{"prefix"'));
    });

    test('a table from an older build gains the columns it is missing',
        () async {
      final db = await openDb();
      // The schema as an earlier release wrote it: no auto-repeat columns.
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
          display_fields TEXT
        )
      ''');
      await db.insert('crfs', {'tablename': 'hh_info'});

      await DbService.syncCrfsTableForTesting('s1', db, manifest());

      // The survey is still usable -- this is the case that used to empty the
      // table and leave the app with no questionnaires at all.
      final rows = await db.query('crfs', orderBy: 'display_order ASC');
      expect(rows, hasLength(2));
      expect(rows.last['repeat_count_field'], 'nmembers');
      expect(rows.last['repeat_enforce_count'], 3);
      expect(rows.last['entry_condition'], isNull);
    });

    test('a manifest naming a column this build does not know keeps the rest',
        () async {
      final db = await openDb();
      final withUnknown = manifest();
      (withUnknown['crfs'] as List)[1]['some_future_column'] = 'x';

      await DbService.syncCrfsTableForTesting('s1', db, withUnknown);

      final rows = await db.query('crfs', orderBy: 'display_order ASC');
      expect(rows, hasLength(2));
      expect(rows.last['tablename'], 'hh_members');
      expect(rows.last['repeat_enforce_count'], 3);
    });

    test('a failed repopulate keeps the previous configuration', () async {
      final db = await openDb();
      await DbService.syncCrfsTableForTesting('s1', db, manifest());
      expect(await db.query('crfs'), hasLength(2));

      // A row SQLite will refuse: display_order is INTEGER, and a nested list
      // is not a value sqflite can bind at all.
      final broken = manifest();
      (broken['crfs'] as List)[1]['display_order'] = ['not', 'a', 'number'];

      await DbService.syncCrfsTableForTesting('s1', db, broken);

      final rows = await db.query('crfs', orderBy: 'display_order ASC');
      expect(rows, hasLength(2), reason: 'the table must not be left empty');
      expect(rows.last['tablename'], 'hh_members');
    });

    test('a manifest with no crfs section leaves the table alone', () async {
      final db = await openDb();
      await DbService.syncCrfsTableForTesting('s1', db, manifest());

      await DbService.syncCrfsTableForTesting('s1', db, {'xmlFiles': []});

      expect(await db.query('crfs'), hasLength(2));
    });
  });

  group('a failed read is not an empty table', () {
    // The distinction IdGenerator depends on. An unregistered surveyId makes
    // the internal _getDbOrThrow throw, which is the same path a locked or
    // corrupt database takes.
    const unopened = 'survey-that-was-never-opened';

    test('tryGetExistingRecords reports a failed read as null', () async {
      expect(
        await DbService.tryGetExistingRecords(unopened, 'enrollee'),
        isNull,
      );
    });

    test('getExistingRecords still flattens a failure to no rows', () async {
      // Kept deliberately: the display call sites want this. It is only
      // unsafe for code deriving an identifier, which for the subject ID now
      // uses the method above -- reading increment 1 out of this empty list is
      // what handed a second subject an already-enrolled ID.
      //
      // Not "the five display call sites", which is what this said before and
      // is wrong: parent_id_selector_screen._getNextIncrementNumber derives a
      // child increment from getExistingRecords and so still takes the unsafe
      // path. See the doc comment on getExistingRecords -- it belongs to the
      // parent/child counter work, which has to decide which column groups a
      // household's children before either implementation can be the one.
      expect(await DbService.getExistingRecords(unopened, 'enrollee'), isEmpty);
    });

    test('tryGetMaxIdIncrement reports a failed read as null, not as 0',
        () async {
      // The same distinction one level down. 0 means "no record carries this
      // base ID yet" and yields increment 1; null means "unknown" and sends
      // IdGenerator down the sentinel path instead. Collapsing them is what
      // used to hand a second subject an already-enrolled ID.
      expect(
        await DbService.tryGetMaxIdIncrement(
          surveyId: unopened,
          tableName: 'enrollee',
          fieldName: 'subjid',
          baseId: '2105005',
          incrementLength: 4,
          sentinelFloor: 9990,
        ),
        isNull,
      );
    });
  });

  group('maxIdIncrementIn', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE enrollee (subjid TEXT)');
    });

    tearDown(() => db.close());

    Future<int> maxFor({String field = 'subjid'}) => DbService.maxIdIncrementIn(
          db,
          tableName: 'enrollee',
          fieldName: field,
          baseId: '2105005',
          incrementLength: 4,
          sentinelFloor: 9990,
        );

    test('is 0 for a table with no rows at all', () async {
      expect(await maxFor(), 0);
    });

    test('is 0 when no row carries this base ID', () async {
      await db.insert('enrollee', {'subjid': '21060060099'});

      expect(await maxFor(), 0);
    });

    test('reads a value stored as an integer rather than text', () async {
      // SQLite columns are dynamically typed, and a CSV import or a legacy
      // row can leave a numeric-looking ID stored as INTEGER. substr() and
      // length() coerce it to text, so it still counts -- as it did when the
      // old Dart scan called .toString() on it.
      await db.rawInsert('INSERT INTO enrollee (subjid) VALUES (?)', [21050050042]);

      expect(await maxFor(), 42);
    });

    test('refuses an identifier it cannot safely quote', () async {
      // Table and column names cannot be bound as parameters, so they are
      // interpolated; a name carrying a double quote stops rather than being
      // escaped and guessed at.
      expect(
        () => maxFor(field: 'subjid" --'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('nextIncrementValueIn', () {
    // The child counter (linenum/netnum). It had no test at all, which is how
    // it kept interpolating its three identifiers raw while the sibling
    // subject-ID query above was quoting them.
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE hh_members (hhid TEXT, linenum TEXT)');
    });

    tearDown(() => db.close());

    Future<int> nextFor({
      String table = 'hh_members',
      String field = 'linenum',
      String keyField = 'hhid',
      String key = 'HH001',
    }) =>
        DbService.nextIncrementValueIn(
          db,
          tableName: table,
          incrementField: field,
          linkingField: keyField,
          linkingValue: key,
        );

    test('is 1 for a parent with no children yet', () async {
      expect(await nextFor(), 1);
    });

    test('counts only this parent\'s children', () async {
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '1'});
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '2'});
      await db.insert('hh_members', {'hhid': 'HH002', 'linenum': '7'});

      expect(await nextFor(), 3);
    });

    test('reads a value stored as an integer rather than text', () async {
      await db.rawInsert(
          'INSERT INTO hh_members (hhid, linenum) VALUES (?, ?)',
          ['HH001', 4]);

      expect(await nextFor(), 5);
    });

    test('is 1 for a table this survey does not have', () async {
      expect(await nextFor(table: 'not_a_table'), 1);
    });

    test('refuses an increment column it cannot safely quote', () async {
      expect(
        () => nextFor(field: 'linenum" --'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('refuses a table name it cannot safely quote', () async {
      // _tableExists runs first and answers false for a name like this, so
      // the guard is reached only for a table that does exist. Create one
      // whose name carries a quote to prove the check is not skipped.
      await db.execute('CREATE TABLE "odd""name" (hhid TEXT, linenum TEXT)');

      expect(
        () => nextFor(table: 'odd"name'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('refuses a linking column it cannot safely quote', () async {
      expect(
        () => nextFor(keyField: 'hhid" --'),
        throwsA(isA<DatabaseException>()),
      );
    });

    // Decision 1 of the parent/child integrity work: children are grouped by
    // `crfs.linkingfield`, not by `crfs.primarykey`'s first field. The two
    // agree in every current dictionary, so a test has to construct a case
    // where they differ to pin the choice down at all.
    test('groups by the linking column, not by another key column', () async {
      await db.execute(
          'CREATE TABLE odd_child (linenum TEXT, hhid TEXT, other TEXT)');
      // Two households, each with children numbered from 1. Grouping by
      // `hhid` gives 3 for HH001; grouping by `linenum` (what a
      // `primarykey = 'linenum,hhid'` sheet would have handed the old code)
      // would instead scan rows sharing a linenum and answer nonsense.
      await db.insert('odd_child',
          {'hhid': 'HH001', 'linenum': '1', 'other': 'x'});
      await db.insert('odd_child',
          {'hhid': 'HH001', 'linenum': '2', 'other': 'x'});
      await db.insert('odd_child',
          {'hhid': 'HH002', 'linenum': '1', 'other': 'y'});

      expect(
        await DbService.nextIncrementValueIn(
          db,
          tableName: 'odd_child',
          incrementField: 'linenum',
          linkingField: 'hhid',
          linkingValue: 'HH001',
        ),
        3,
      );
      expect(
        await DbService.nextIncrementValueIn(
          db,
          tableName: 'odd_child',
          incrementField: 'linenum',
          linkingField: 'hhid',
          linkingValue: 'HH002',
        ),
        2,
      );
    });

    // The degraded value. `0` rather than `1` because a child counter starts
    // at 1, so `0` is a value no legitimate record holds -- where `1` was
    // indistinguishable from a legitimate first child and so left no trace.
    test('a failed read issues the degraded value, not 1', () async {
      const unopened = 'survey-that-was-never-opened';

      expect(
        await DbService.getNextIncrementValue(
          surveyId: unopened,
          tableName: 'hh_members',
          incrementField: 'linenum',
          linkingField: 'hhid',
          linkingValue: 'HH001',
        ),
        DbService.degradedIncrementValue,
      );
      expect(DbService.degradedIncrementValue, 0);
    });

    // The reason `0` was chosen over a top-of-range sentinel: it sits below
    // every legitimate value, so one failed read cannot poison the sequence.
    // A stored 999 would have pushed the next child to 1000, then 1001,
    // forever, unless the MAX query excluded it explicitly.
    test('a stored degraded value does not poison the counter', () async {
      for (final n in ['1', '2', '3', '4']) {
        await db.insert('hh_members', {'hhid': 'HH001', 'linenum': n});
      }
      await db.insert('hh_members', {
        'hhid': 'HH001',
        'linenum': DbService.degradedIncrementValue.toString(),
      });

      expect(await nextFor(), 5);
    });
  });

  group('nextIncrementValuesIn', () {
    // The grouped form, which the parent-ID selector uses to put a number
    // beside every parent in one query instead of a full-table read per
    // visible row per rebuild.
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE hh_members (hhid TEXT, linenum TEXT)');
    });

    tearDown(() => db.close());

    Future<Map<String, int>> valuesFor({String table = 'hh_members'}) =>
        DbService.nextIncrementValuesIn(
          db,
          tableName: table,
          incrementField: 'linenum',
          linkingField: 'hhid',
        );

    test('answers per parent in one query', () async {
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '1'});
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '2'});
      await db.insert('hh_members', {'hhid': 'HH002', 'linenum': '7'});

      expect(await valuesFor(), {'HH001': 3, 'HH002': 8});
    });

    test('omits a parent with no children, rather than reporting 1', () async {
      // Absent means "no children", which the caller reads as 1. Keeping it
      // absent is what lets a caller tell that apart from a failed read,
      // which surfaces as a null map from tryGetNextIncrementValues.
      expect(await valuesFor(), isEmpty);
    });

    test('is empty for a table this survey does not have', () async {
      expect(await valuesFor(table: 'not_a_table'), isEmpty);
    });

    test('refuses identifiers it cannot safely quote', () async {
      expect(
        () => DbService.nextIncrementValuesIn(
          db,
          tableName: 'hh_members',
          incrementField: 'linenum',
          linkingField: 'hhid" --',
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('survey table constraints', () {
    // The parent/child relationship the crfs worksheet declares used to exist
    // only as metadata the app remembered: every column was a bare TEXT with
    // no PRIMARY KEY, no UNIQUE and no FOREIGN KEY, and PRAGMA foreign_keys
    // was never set anywhere in the repo. These tests are the evidence the
    // constraints are real rather than decorative -- which is why they insert
    // rows instead of asserting that a CREATE TABLE string contains the word
    // REFERENCES.
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      // What DbService.init() does on desktop. Assigning the global factory
      // rather than calling databaseFactoryFfi directly is deliberate: it is
      // the production route, and the pragma has to hold on that route.
      databaseFactory = databaseFactoryFfi;
      db = await DbService.openSurveyDatabaseForTesting(inMemoryDatabasePath);
      // Production creates formchanges before any survey table
      // (_syncDatabaseSchema step 1b, ahead of step 2) precisely because the
      // cascade trigger writes into it. Mirrored here so the dependency is
      // exercised rather than assumed.
      await DbService.syncFormChangesTableForTesting('s1', db);
    });

    tearDown(() => db.close());

    Map<String, dynamic> parentCrf() => {
          'tablename': 'hh_info',
          'primarykey': 'hhid',
          'linkingfield': 'hhid',
        };

    Map<String, dynamic> childCrf() => {
          'tablename': 'hh_members',
          'primarykey': 'hhid,linenum',
          'linkingfield': 'hhid',
          'parenttable': 'hh_info',
          'incrementfield': 'linenum',
        };

    Future<void> createSchema({void Function(String)? onSkipped}) async {
      for (final statement in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'hh_info',
        columnNames: ['uniqueid', 'hhid', 'nmembers'],
        crf: parentCrf(),
        referencedColumnSets: const [['hhid']],
        onSkippedConstraint: onSkipped,
      )) {
        await db.execute(statement);
      }
      for (final statement in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'hh_members',
        columnNames: [
          'uniqueid',
          'hhid',
          'linenum',
          'membername',
          SurveyTableSchema.parentUniqueIdColumn,
        ],
        crf: childCrf(),
        parentCrf: parentCrf(),
        onSkippedConstraint: onSkipped,
      )) {
        await db.execute(statement);
      }
    }

    Future<void> addHousehold(String uniqueId, String hhid) =>
        db.insert('hh_info', {'uniqueid': uniqueId, 'hhid': hhid});

    /// [parentUniqueId] defaults to the household seeded by [addHousehold].
    Future<void> addMember(String uniqueId, String hhid, String linenum,
            {String? parentUniqueId = 'hh-1'}) =>
        db.insert('hh_members', {
          'uniqueid': uniqueId,
          'hhid': hhid,
          'linenum': linenum,
          SurveyTableSchema.parentUniqueIdColumn: parentUniqueId,
        });

    test('the production open path enforces foreign keys', () async {
      // PRAGMA foreign_keys defaults to off, is per-connection, and is not
      // persisted in the file -- so this is the single thing standing between
      // "we have foreign keys" and "we believe we have foreign keys".
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first.values.first, 1);
    });

    test('a child whose parent does not exist is refused', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');

      // Matching the message, not just "it threw": the point of the test is
      // that the foreign key is the thing refusing it.
      await expectLater(
        () => addMember('m-1', '999999999', '1'),
        throwsA(predicate(
            (e) => e.toString().contains('FOREIGN KEY constraint failed'))),
      );
    });

    test('a second household claiming the same hhid is refused', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');

      // Refusing here is deliberate. hh_info declares incrementLength: 0, so
      // hhid is a pure function of the interviewer's typed answers and there
      // is no spare digit to move -- a duplicate means a second copy of a
      // household that already exists, and saving it under a mangled id would
      // manufacture a phantom household rather than preserve a record.
      await expectLater(
        () => addHousehold('hh-2', '100120001'),
        throwsA(predicate((e) =>
            e.toString().contains('UNIQUE constraint failed: hh_info.hhid'))),
      );
    });

    test('two rows cannot share a uniqueid', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');

      await expectLater(
        () => addHousehold('hh-1', '100120002'),
        throwsA(predicate((e) => e
            .toString()
            .contains('UNIQUE constraint failed: hh_info.uniqueid'))),
      );
    });

    test('a duplicate (hhid, linenum) is accepted, deliberately', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');
      await addMember('m-1', '100120001', '1');

      // No UNIQUE on the sibling pair, on purpose: a duplicate linenum is a
      // counter bug the interviewer never typed, every row carries a uniqueid,
      // and saveInterview uses ConflictAlgorithm.abort -- so a constraint here
      // would turn a recoverable oddity into a lost interview. This test
      // exists so that adding one later breaks a test rather than an
      // interview.
      await addMember('m-2', '100120001', '1');

      final duplicates = await db.rawQuery(
          'SELECT hhid, linenum, COUNT(*) AS n FROM hh_members '
          'GROUP BY hhid, linenum HAVING COUNT(*) > 1');
      expect(duplicates, hasLength(1));
      expect(duplicates.first['n'], 2);
    });

    test('the same linenum under a different household is fine', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');
      await addHousehold('hh-2', '100120002');

      await addMember('m-1', '100120001', '1');
      await addMember('m-2', '100120002', '1', parentUniqueId: 'hh-2');

      expect(
        (await db.query('hh_members')).length,
        2,
      );
    });

    test('correcting a household id carries to its children', () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');
      for (final n in ['1', '2', '3']) {
        await addMember('m-$n', '100120001', n);
      }

      // The motivating scenario: hhnum is typed, so an interviewer correcting
      // a mistyped household number is ordinary work. Without the cascade the
      // three members keep the old hhid, the household is split across two
      // ids, and the next member added gets linenum 1 alongside members 1-3.
      await db.update('hh_info', {'hhid': '100120009'},
          where: 'uniqueid = ?', whereArgs: ['hh-1']);

      final members = await db.query('hh_members', orderBy: 'linenum ASC');
      expect(members, hasLength(3));
      expect(members.map((r) => r['hhid']), everyElement('100120009'));
      // Ordinals are untouched: the household moved, the members did not
      // renumber.
      expect(members.map((r) => r['linenum']), ['1', '2', '3']);
    });

    test('a cascade re-arms each child for upload and audits itself',
        () async {
      await createSchema();
      await addHousehold('hh-1', '100120001');
      for (final n in ['1', '2', '3']) {
        await addMember('m-$n', '100120001', n);
      }
      // Pretend all three have already reached the server.
      await db.update('hh_members', {'synced_at': '2026-09-01T00:00:00.000'});

      await db.update('hh_info', {'hhid': '100120009'},
          where: 'uniqueid = ?', whereArgs: ['hh-1']);

      // Without the trigger the device would be corrected while the server
      // kept the old key forever -- a silent desync, arguably worse than the
      // visible orphaning the cascade fixes.
      final pending = await db
          .query('hh_members', where: 'synced_at IS NULL');
      expect(pending, hasLength(3));

      final changes = await db.query('formchanges');
      expect(changes, hasLength(3));
      expect(changes.map((r) => r['tablename']),
          everyElement('hh_members'));
      expect(changes.map((r) => r['fieldname']), everyElement('hhid'));
      expect(changes.map((r) => r['oldvalue']), everyElement('100120001'));
      expect(changes.map((r) => r['newvalue']), everyElement('100120009'));
      expect(changes.map((r) => r['uniqueid']).toSet(),
          {'m-1', 'm-2', 'm-3'});
      // changeuniqueid must be non-null or the uploader's
      // `WHERE changeuniqueid IS NOT NULL` filter skips the row entirely.
      final changeIds =
          changes.map((r) => r['changeuniqueid']?.toString()).toSet();
      expect(changeIds, hasLength(3));
      expect(changeIds, everyElement(isA<String>()));
      expect(changeIds.every((id) => id!.length == 32), isTrue);
      // synced_at must be null on the audit row too, or it never uploads.
      expect(changes.map((r) => r['synced_at']), everyElement(isNull));
    });

    test('the cascade trigger survives recursive_triggers being on',
        () async {
      await createSchema();
      await db.execute('PRAGMA recursive_triggers = ON');
      await addHousehold('hh-1', '100120001');
      await addMember('m-1', '100120001', '1');

      // The trigger's own inner UPDATE touches synced_at, not the linking
      // column, and the WHEN guard requires the column to have changed -- so
      // it cannot re-enter itself.
      await db.update('hh_info', {'hhid': '100120009'},
          where: 'uniqueid = ?', whereArgs: ['hh-1']);

      expect((await db.query('formchanges')).length, 1);
    });

    test('a foreign key is skipped when the parent has no such column',
        () async {
      final skipped = <String>[];
      await createSchema(onSkipped: skipped.add);

      // A child naming a linking column its parent does not have. The
      // REFERENCES clause would name a column that carries no UNIQUE, and
      // SQLite would reject every insert with "foreign key mismatch" rather
      // than failing at CREATE -- so it is omitted and logged. SurveyGen and
      // the portal both reject this shape at authoring time.
      final statements = SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'member_visits',
        columnNames: ['uniqueid', 'hhid', 'visitnum'],
        crf: {
          'tablename': 'member_visits',
          'primarykey': 'hhid,visitnum',
          'linkingfield': 'hhid,linenum',
          'parenttable': 'hh_members',
        },
        parentCrf: childCrf(),
        onSkippedConstraint: skipped.add,
      );

      expect(statements.first, isNot(contains('REFERENCES "hh_members"')));
      expect(skipped, hasLength(1));
      expect(skipped.single, contains('does not have every one of those'));

      // It is still created, and still usable -- the relationship is just not
      // enforced.
      for (final statement in statements) {
        await db.execute(statement);
      }
      await db.insert('member_visits',
          {'uniqueid': 'v-1', 'hhid': 'no-such-parent', 'visitnum': '1'});
      expect((await db.query('member_visits')).length, 1);
    });

    test('a child may link on a column that is not the parent primary key',
        () async {
      // AVERT's real shape: vaccination_status links to enrollee on `barcode`
      // (a scanned physical label) while enrollee is keyed on `subjid`.
      // Keying the UNIQUE to the primary key would have left this child with
      // no foreign key at all.
      final enrolleeCrf = {
        'tablename': 'enrollee',
        'primarykey': 'subjid',
        'linkingfield': 'barcode',
      };
      final vaccinationCrf = {
        'tablename': 'vaccination_status',
        'primarykey': 'barcode',
        'linkingfield': 'barcode',
        'parenttable': 'enrollee',
      };
      final crfs = {'enrollee': enrolleeCrf, 'vaccination_status': vaccinationCrf};

      final parentSets =
          SurveyTableSchema.referencedColumnSetsFor('enrollee', crfs);
      expect(parentSets, containsAll([['barcode'], ['subjid']]));

      for (final s in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'enrollee',
        columnNames: ['uniqueid', 'subjid', 'barcode'],
        crf: enrolleeCrf,
        referencedColumnSets: parentSets,
      )) {
        await db.execute(s);
      }
      for (final s in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'vaccination_status',
        columnNames: ['uniqueid', 'barcode'],
        crf: vaccinationCrf,
        parentCrf: enrolleeCrf,
        referencedColumnSets:
            SurveyTableSchema.referencedColumnSetsFor('vaccination_status', crfs),
      )) {
        await db.execute(s);
      }

      await db.insert('enrollee',
          {'uniqueid': 'e-1', 'subjid': 'R21001', 'barcode': 'R21U-001-AB1C'});
      await db.insert('vaccination_status',
          {'uniqueid': 'v-1', 'barcode': 'R21U-001-AB1C'});

      // The key is real: an unknown barcode is refused.
      await expectLater(
        () => db.insert('vaccination_status',
            {'uniqueid': 'v-2', 'barcode': 'R21U-999-ZZ9Z'}),
        throwsA(predicate(
            (e) => e.toString().contains('FOREIGN KEY constraint failed'))),
      );

      // And correcting a mistyped barcode carries to the child.
      await db.update('enrollee', {'barcode': 'R21U-002-AB1C'},
          where: 'uniqueid = ?', whereArgs: ['e-1']);
      expect(
        (await db.query('vaccination_status')).single['barcode'],
        'R21U-002-AB1C',
      );
    });

    test('a leaf child carries no UNIQUE and no parent-side constraint',
        () async {
      final statements = SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'hh_members',
        columnNames: ['uniqueid', 'hhid', 'linenum'],
        crf: childCrf(),
        parentCrf: parentCrf(),
      );

      expect(statements.first, contains('REFERENCES'));
      expect(statements.first, contains('ON UPDATE CASCADE'));
      expect(statements.first, isNot(contains('UNIQUE(')));
      // The sibling index is plain, so it serves the counter's MAX query
      // without refusing a duplicate.
      final index = statements.firstWhere((s) => s.contains('CREATE INDEX'));
      expect(index, isNot(contains('UNIQUE')));
      // And a cascade trigger, so the rewrite it performs is not invisible.
      expect(statements.any((s) => s.contains('CREATE TRIGGER')), isTrue);
    });
  });

  group('orderByParentFirst', () {
    Map<String, Map<String, dynamic>> crfs() => {
          'hh_members': {'tablename': 'hh_members', 'parenttable': 'hh_info'},
          'hh_info': {'tablename': 'hh_info'},
          'visits': {'tablename': 'visits', 'parenttable': 'hh_members'},
        };

    test('creates a form after its parent', () {
      final ordered = SurveyTableSchema.orderByParentFirst(
        ['visits.xml', 'hh_members.xml', 'hh_info.xml'],
        crfs(),
      );

      expect(ordered.indexOf('hh_info.xml'),
          lessThan(ordered.indexOf('hh_members.xml')));
      expect(ordered.indexOf('hh_members.xml'),
          lessThan(ordered.indexOf('visits.xml')));
    });

    test('keeps a form whose parent is not in this survey', () {
      final ordered = SurveyTableSchema.orderByParentFirst(
        ['orphan.xml'],
        {
          'orphan': {'tablename': 'orphan', 'parenttable': 'not_here'}
        },
      );

      expect(ordered, ['orphan.xml']);
    });

    test('does not loop on a cycle', () {
      final ordered = SurveyTableSchema.orderByParentFirst(
        ['a.xml', 'b.xml'],
        {
          'a': {'tablename': 'a', 'parenttable': 'b'},
          'b': {'tablename': 'b', 'parenttable': 'a'},
        },
      );

      expect(ordered, hasLength(2));
    });
  });

  group('tryGetRecordCount and getPrimaryKeyFields', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DbService.registerDatabaseForTest('s-count', db);
      addTearDown(() => DbService.unregisterDatabaseForTest('s-count'));
    });

    tearDown(() => db.close());

    test('a failed read is null, not 0', () async {
      // RepeatCountService writes this number onto the parent, so a failure
      // arriving as 0 could set `nmembers = 0` on a household with five
      // members. Until this contract existed, the only thing preventing that
      // was the count question happening to declare minvalue='1'.
      const unopened = 'survey-that-was-never-opened';

      expect(
        await DbService.tryGetRecordCount(
            surveyId: unopened, tableName: 'hh_members'),
        isNull,
      );
      // The lossy wrapper still exists for callers that only display a count.
      expect(
        await DbService.getRecordCount(
            surveyId: unopened, tableName: 'hh_members'),
        0,
      );
    });

    test('a missing table is 0, not null', () async {
      // A table that does not exist genuinely holds no rows.
      expect(
        await DbService.tryGetRecordCount(
            surveyId: 's-count', tableName: 'not_a_table'),
        0,
      );
    });

    test('counts one parent\'s children', () async {
      await db.execute('CREATE TABLE hh_members (hhid TEXT, linenum TEXT)');
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '1'});
      await db.insert('hh_members', {'hhid': 'HH001', 'linenum': '2'});
      await db.insert('hh_members', {'hhid': 'HH002', 'linenum': '1'});

      expect(
        await DbService.tryGetRecordCount(
          surveyId: 's-count',
          tableName: 'hh_members',
          where: 'hhid = ?',
          whereArgs: ['HH001'],
        ),
        2,
      );
    });

    test('refuses a table name it cannot safely quote', () async {
      await db.execute('CREATE TABLE "odd""name" (hhid TEXT)');

      // The table name used to be interpolated raw here while only whereArgs
      // were bound.
      expect(
        await DbService.tryGetRecordCount(
            surveyId: 's-count', tableName: 'odd"name'),
        isNull,
      );
    });

    test('primary key fields are lowercased, whatever the worksheet said',
        () async {
      await DbService.syncCrfsTableForTesting('s-count', db, {
        'crfs': [
          {'tablename': 'hh_members', 'primarykey': 'HHID, LineNum'},
        ]
      });

      // The cell is typed by hand into a worksheet, while callers compare
      // these names against lowercased fieldnames and against the lowercased
      // keys getAllPrimaryKeys returns -- so mixed case used to make every
      // one of those comparisons miss in silence.
      expect(
        await DbService.getPrimaryKeyFields('s-count', 'hh_members'),
        ['hhid', 'linenum'],
      );
    });

    test('existing primary keys come back under lowercased column names',
        () async {
      await db.execute('CREATE TABLE hh_members (HHID TEXT, LineNum TEXT)');
      await db.insert('hh_members', {'HHID': 'HH001', 'LineNum': '1'});

      final rows = await DbService.getAllPrimaryKeys(
          's-count', 'hh_members', ['hhid', 'linenum']);

      // The caller joins these lookups into a duplicate-check signature. When
      // the keys came back as SQLite reported them, a lowercase lookup found
      // nothing and every record collapsed to the same empty signature.
      expect(rows, hasLength(1));
      expect(rows.single['hhid'], 'HH001');
      expect(rows.single['linenum'], '1');
    });
  });

  group('the parent_uniqueid join key', () {
    // hhid is built from typed answers, so an interviewer correcting a
    // mistyped household number changes it. parent_uniqueid carries the
    // parent's UUID instead: hhid stays the human-readable business key, and
    // the join key becomes one nothing can retype.
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await DbService.openSurveyDatabaseForTesting(inMemoryDatabasePath);
      await DbService.syncFormChangesTableForTesting('s1', db);
    });

    tearDown(() => db.close());

    Map<String, dynamic> parentCrf() => {
          'tablename': 'hh_info',
          'primarykey': 'hhid',
          'linkingfield': 'hhid',
        };

    Map<String, dynamic> childCrf() => {
          'tablename': 'hh_members',
          'primarykey': 'hhid,linenum',
          'linkingfield': 'hhid',
          'parenttable': 'hh_info',
          'incrementfield': 'linenum',
        };

    List<String> childStatements({List<String>? columns}) =>
        SurveyTableSchema.buildSurveyTableStatements(
          tableName: 'hh_members',
          columnNames: columns ??
              ['uniqueid', 'hhid', 'linenum', SurveyTableSchema.parentUniqueIdColumn],
          crf: childCrf(),
          parentCrf: parentCrf(),
        );

    test('the schema and answer layers agree on the column name', () {
      // Two constants rather than one import, so the schema layer does not
      // depend on the answer layer -- which makes this assertion the thing
      // keeping them in step.
      expect(SurveyTableSchema.parentUniqueIdColumn, AutoFields.parentUniqueIdField);
      expect(SurveyTableSchema.parentUniqueIdColumn, 'parent_uniqueid');
    });

    test('a child gets a second foreign key, on the immutable key', () {
      final create = childStatements().first;

      expect(create, contains('FOREIGN KEY ("parent_uniqueid")'));
      expect(create, contains('REFERENCES "hh_info" (uniqueid)'));
    });

    test('the parent-link key does not cascade, because it cannot change', () {
      // A UUID is not something an interviewer can retype, so there is
      // nothing for a cascade to carry. Only the business key needs one.
      final create = childStatements().first;
      final parentLinkClause = create
          .split(', ')
          .firstWhere((c) => c.contains('"parent_uniqueid"'));

      expect(parentLinkClause, isNot(contains('ON UPDATE CASCADE')));
      expect(create, contains('FOREIGN KEY ("hhid")'));
    });

    test('no parent-link key when the column is absent', () {
      // SurveyGen writes the column only onto a form with a parenttable, so
      // an older package will not have it and must still create cleanly.
      final create =
          childStatements(columns: ['uniqueid', 'hhid', 'linenum']).first;

      expect(create, isNot(contains('parent_uniqueid')));
      expect(create, contains('FOREIGN KEY ("hhid")'));
    });

    test('a child pointing at no real parent record is refused', () async {
      for (final s in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'hh_info',
        columnNames: ['uniqueid', 'hhid'],
        crf: parentCrf(),
        referencedColumnSets: const [['hhid']],
      )) {
        await db.execute(s);
      }
      for (final s in childStatements()) {
        await db.execute(s);
      }
      await db.insert('hh_info', {'uniqueid': 'hh-1', 'hhid': '100120001'});

      await expectLater(
        () => db.insert('hh_members', {
          'uniqueid': 'm-1',
          'hhid': '100120001',
          'linenum': '1',
          SurveyTableSchema.parentUniqueIdColumn: 'not-a-real-uuid',
        }),
        throwsA(predicate(
            (e) => e.toString().contains('FOREIGN KEY constraint failed'))),
      );
    });

    test('correcting the business key leaves the join key untouched',
        () async {
      for (final s in SurveyTableSchema.buildSurveyTableStatements(
        tableName: 'hh_info',
        columnNames: ['uniqueid', 'hhid'],
        crf: parentCrf(),
        referencedColumnSets: const [['hhid']],
      )) {
        await db.execute(s);
      }
      for (final s in childStatements()) {
        await db.execute(s);
      }
      await db.insert('hh_info', {'uniqueid': 'hh-1', 'hhid': '100120001'});
      await db.insert('hh_members', {
        'uniqueid': 'm-1',
        'hhid': '100120001',
        'linenum': '1',
        SurveyTableSchema.parentUniqueIdColumn: 'hh-1',
      });

      await db.update('hh_info', {'hhid': '100120009'},
          where: 'uniqueid = ?', whereArgs: ['hh-1']);

      // This is the point of the field: the business key moved, the join key
      // did not, so an analysis joining on parent_uniqueid never noticed.
      final member = (await db.query('hh_members')).single;
      expect(member['hhid'], '100120009');
      expect(member[SurveyTableSchema.parentUniqueIdColumn], 'hh-1');
    });
  });

  group('the identifier guard is on every statement this file builds', () {
    // Table and column names come from a data dictionary and cannot be bound
    // as parameters, so they are interpolated -- and quoteIdentifier is what
    // stands between that and an injected statement. These four sites built
    // their own SQL and bypassed it. Each test does both halves: a name that
    // needs quoting now works, and a name carrying a double quote is refused
    // rather than executed.

    Future<Database> openDb() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      return db;
    }

    test('CSV import quotes the table name and every header', () async {
      final db = await openDb();

      // A CSV filename and header row are the least controlled identifiers in
      // the app -- the only ones SurveyGen never sees. `select` is a reserved
      // word and `Region Name` contains a space; unquoted, both are syntax
      // errors, so this import used to be skipped with a logged failure.
      await DbService.importCsvContent(
        db,
        'region list',
        'Region Name,select\nNorth,1\n',
      );

      // Read back with raw SQL, not db.query -- sqflite's helpers interpolate
      // the table name they are given without quoting it, which is the same
      // trap the production code above had to stop relying on.
      final rows = await db.rawQuery('SELECT * FROM "region list"');
      expect(rows.single['Region Name'], 'North');
      expect(rows.single['select'], '1');
    });

    test('CSV import refuses a name carrying a double quote', () async {
      final db = await openDb();

      await expectLater(
        DbService.importCsvContent(db, 'ok', 'a,b"c\n1,2\n'),
        throwsA(isA<DatabaseException>()),
      );
      // Nothing was created: the guard throws before the CREATE runs.
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='ok'",
      );
      expect(tables, isEmpty);
    });

    test('isValueUnique quotes both the table and the column', () async {
      final db = await openDb();
      await db.execute('CREATE TABLE "order" ("group" TEXT)');
      await db.rawInsert('INSERT INTO "order" ("group") VALUES (?)', ['taken']);
      DbService.registerDatabaseForTest('guard_unique', db);
      addTearDown(() => DbService.unregisterDatabaseForTest('guard_unique'));

      // Both are SQL reserved words, so unquoted this was a syntax error --
      // which this method reports as "unique", the worst possible answer.
      expect(
        await DbService.isValueUnique('guard_unique', 'order', 'group', 'taken'),
        isFalse,
      );
      expect(
        await DbService.isValueUnique('guard_unique', 'order', 'group', 'free'),
        isTrue,
      );
    });

    test('isValueUnique still fails open when the guard refuses a name',
        () async {
      final db = await openDb();
      DbService.registerDatabaseForTest('guard_open', db);
      addTearDown(() => DbService.unregisterDatabaseForTest('guard_open'));

      // Pinned deliberately rather than fixed. Every error here reports "no
      // duplicate", which is the existing call-site policy -- a uniqueCheck
      // that cannot be evaluated must not block an interviewer mid-form. Worth
      // knowing that a refused name arrives as a silent pass, not an error.
      expect(
        await DbService.isValueUnique('guard_open', 'bad"name', 'col', 'v'),
        isTrue,
      );
    });

    test('the ALTER path quotes what the CREATE path already quoted',
        () async {
      final db = await openDb();
      // A table created by an older build, now gaining a column whose name
      // needs quoting. The CREATE branch of _syncSurveyTable goes through
      // SurveyTableSchema and was always quoted; this is the branch that
      // built its own SQL.
      await db.execute('CREATE TABLE "group" (uniqueid TEXT)');

      final table = SurveyTableSchema.quoteIdentifier('group');
      final column = SurveyTableSchema.quoteIdentifier('order');
      await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');

      await db.rawInsert(
          'INSERT INTO "group" (uniqueid, "order") VALUES (?, ?)', ['r-1', '2']);
      expect((await db.rawQuery('SELECT * FROM "group"')).single['order'], '2');
    });

    test('quoteIdentifier refuses rather than escaping', () async {
      // The guard's own contract, stated once here because four call sites
      // now depend on it: a name carrying a double quote is a broken
      // dictionary, and guessing what was meant is worse than stopping.
      expect(() => SurveyTableSchema.quoteIdentifier('a"b'),
          throwsA(isA<DatabaseException>()));
      expect(() => SurveyTableSchema.quoteIdentifier(''),
          throwsA(isA<DatabaseException>()));
      expect(SurveyTableSchema.quoteIdentifier('Region Name'),
          '"Region Name"');
    });
  });
}
