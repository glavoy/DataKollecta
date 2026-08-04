import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:GiSTX/services/db_service.dart';

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
}
