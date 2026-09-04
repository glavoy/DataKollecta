import 'package:flutter_test/flutter_test.dart';
// `DatabaseException` is declared by both sqflite_common and db_service.dart;
// this file wants the latter, which is what _quoteIdentifier throws.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;
import 'package:datakollecta/services/db_service.dart';

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
}
