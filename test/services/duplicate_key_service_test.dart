import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;

import 'package:datakollecta/services/db_service.dart';
import 'package:datakollecta/services/duplicate_key_service.dart';

/// The real-time duplicate-key check, previously untestable inside
/// `SurveyScreen`.
///
/// The behaviour worth pinning is mostly about what does *not* count as a
/// duplicate: a half-typed key, a key with no snapshot behind it, a table with
/// no declared primary key. Each of those returning `true` would block an
/// interviewer from saving a legitimate record, which is the worse failure --
/// a duplicate is recoverable through `uniqueid`, a refused interview is not.
const String surveyId = 'duplicate_key_test';

Future<Database> buildSurvey({
  String primaryKey = 'hhid,linenum',
  List<Map<String, Object?>> rows = const [],
  String columnCase = 'lower',
}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute('CREATE TABLE crfs (tablename TEXT, primarykey TEXT)');
  await db.insert('crfs', {
    'tablename': 'hh_members',
    'primarykey': primaryKey,
  });

  // The XML's own case for the columns. `getPrimaryKeyFields` lowercases the
  // worksheet value and `getAllPrimaryKeys` lowercases what SQLite returns, so
  // a sheet saying HHID must still line up.
  final hhid = columnCase == 'upper' ? 'HHID' : 'hhid';
  await db.execute(
    'CREATE TABLE hh_members (uniqueid TEXT PRIMARY KEY, $hhid TEXT, '
    'linenum TEXT)',
  );
  for (var i = 0; i < rows.length; i++) {
    await db.insert('hh_members', {'uniqueid': 'mem-$i', ...rows[i]});
  }

  DbService.registerDatabaseForTest(surveyId, db);
  addTearDown(() => DbService.unregisterDatabaseForTest(surveyId));
  addTearDown(db.close);
  return db;
}

Future<DuplicateKeySnapshot> snapshot() =>
    DuplicateKeySnapshot.load(surveyId: surveyId, tableName: 'hh_members');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading the snapshot', () {
    test('reads one signature per existing record', () async {
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
        {'hhid': '1010001', 'linenum': '2'},
      ]);

      final snap = await snapshot();

      expect(snap.keyFields, ['hhid', 'linenum']);
      expect(snap.existingKeys, {'1010001|1', '1010001|2'});
    });

    test('is empty when the table declares no primary key', () async {
      await buildSurvey(primaryKey: '', rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);

      final snap = await snapshot();

      expect(snap.keyFields, isEmpty);
      expect(snap.existingKeys, isEmpty);
    });

    test('lowercases both sides, so worksheet case cannot break it', () async {
      // A sheet saying HHID used to make every comparison miss, collapsing
      // every record to the same empty signature.
      await buildSurvey(
        primaryKey: 'HHID,linenum',
        columnCase: 'upper',
        rows: [
          {'HHID': '1010001', 'linenum': '1'},
        ],
      );

      final snap = await snapshot();

      expect(snap.keyFields, ['hhid', 'linenum']);
      expect(snap.existingKeys, {'1010001|1'});
    });
  });

  group('isDuplicate', () {
    test('reports a key that already exists', () async {
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);
      final snap = await snapshot();

      expect(snap.isDuplicate({'hhid': '1010001', 'linenum': '1'}), isTrue);
    });

    test('does not report a key that differs in any part', () async {
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);
      final snap = await snapshot();

      expect(snap.isDuplicate({'hhid': '1010001', 'linenum': '2'}), isFalse);
      expect(snap.isDuplicate({'hhid': '9990009', 'linenum': '1'}), isFalse);
    });

    test('a half-typed key is never a duplicate', () async {
      // The interviewer has entered the household but not the member number.
      // Every record would otherwise collide on the same half-empty
      // signature, and the dialog would fire on a legitimate new record.
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);
      final snap = await snapshot();

      expect(snap.isDuplicate({'hhid': '1010001'}), isFalse);
      expect(snap.isDuplicate({'hhid': '1010001', 'linenum': ''}), isFalse);
      expect(snap.isDuplicate({}), isFalse);
    });

    test('an empty snapshot never reports a duplicate', () async {
      await buildSurvey();
      final snap = await snapshot();

      expect(snap.existingKeys, isEmpty);
      expect(snap.isDuplicate({'hhid': '1010001', 'linenum': '1'}), isFalse);
    });

    test('the empty constant never reports a duplicate', () {
      // What edit mode holds: no snapshot is loaded at all.
      expect(
        DuplicateKeySnapshot.empty.isDuplicate({'hhid': '1', 'linenum': '1'}),
        isFalse,
      );
    });

    test('matches an answer whose key differs in case from the worksheet',
        () async {
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);
      final snap = await snapshot();

      // Answers are keyed by the XML's fieldname, which need not match the
      // worksheet's case.
      expect(snap.isDuplicate({'HHID': '1010001', 'LineNum': '1'}), isTrue);
    });

    test('compares as text, so 01 and 1 are different keys', () async {
      await buildSurvey(rows: [
        {'hhid': '1010001', 'linenum': '1'},
      ]);
      final snap = await snapshot();

      expect(snap.isDuplicate({'hhid': '1010001', 'linenum': '01'}), isFalse);
    });
  });

  group('isKeyField', () {
    test('is case-insensitive in both directions', () async {
      await buildSurvey();
      final snap = await snapshot();

      expect(snap.isKeyField('hhid'), isTrue);
      expect(snap.isKeyField('HHID'), isTrue);
      expect(snap.isKeyField('LineNum'), isTrue);
      expect(snap.isKeyField('nmembers'), isFalse);
    });
  });

  group('answerFor', () {
    test('prefers an exact key before falling back to case-insensitive', () {
      final answers = {'hhid': 'exact', 'HHID': 'other'};

      expect(DuplicateKeySnapshot.answerFor(answers, 'hhid'), 'exact');
    });

    test('finds a differently-cased key', () {
      expect(
        DuplicateKeySnapshot.answerFor({'HhId': '1010001'}, 'hhid'),
        '1010001',
      );
    });

    test('returns null when nothing matches', () {
      expect(DuplicateKeySnapshot.answerFor({'hhid': '1'}, 'uniqueid'), isNull);
    });
  });
}
