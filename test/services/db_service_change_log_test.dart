import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:datakollecta/services/db_service.dart';
import 'package:datakollecta/services/settings_service.dart';

/// What a `formchanges` write does when the surveyor id cannot be read.
///
/// `updateField` has always guarded that read: the audit trail is a
/// nice-to-have and the corrected value is not. `_recordChanges` did not, and
/// because it wraps its whole body in one `try`, a settings failure lost every
/// `formchanges` row for that save instead of blanking one column of them.
///
/// This file is separate from `db_service_test.dart` deliberately. The failure
/// being reproduced is `SharedPreferences.getInstance()` throwing
/// `MissingPluginException`, which happens only when nothing in the isolate has
/// called `setMockInitialValues` -- and that call is process-wide and sticky,
/// so it cannot coexist with the mocked groups in that file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // No SharedPreferences.setMockInitialValues: that absence *is* the test
  // fixture. Adding one anywhere in this file disarms every test in it.

  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE visit ('
        'uniqueid TEXT PRIMARY KEY, hhid TEXT, count TEXT, '
        'lastmod TEXT, synced_at TEXT)');
    await db.execute('CREATE TABLE formchanges ('
        'tablename TEXT, fieldname TEXT, uniqueid TEXT, oldvalue TEXT, '
        'newvalue TEXT, changed_at TEXT, changeuniqueid TEXT, '
        'surveyor_id TEXT, synced_at DATETIME)');
    DbService.registerDatabaseForTest('log', db);
    addTearDown(() => DbService.unregisterDatabaseForTest('log'));
  });

  Future<void> seed(String column, String value) => db.insert('visit', {
        'uniqueid': 'v-1',
        'hhid': '100',
        column: value,
      });

  test('the settings read really does fail here', () async {
    // A guard against this whole file quietly passing for the wrong reason: if
    // some future dependency makes the read succeed, the two tests below stop
    // exercising the failure they were written for and nothing would say so.
    await expectLater(
      SettingsService().surveyorId,
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('updateInterview still records the full audit trail, minus the id',
      () async {
    // The regression. _recordChanges used to lose both rows, not just the
    // surveyor_id column, because the read sat inside its method-wide try.
    await seed('count', '3');

    await DbService.updateInterview(
      surveyId: 'log',
      surveyFilename: 'visit.xml',
      answers: {'uniqueid': 'v-1', 'hhid': '101', 'count': '4'},
      uniqueId: 'v-1',
      originalAnswers: {'uniqueid': 'v-1', 'hhid': '100', 'count': '3'},
    );

    final changes = await db.query('formchanges', orderBy: 'fieldname');
    expect(changes.map((c) => c['fieldname']), ['count', 'hhid']);
    expect(changes.map((c) => c['newvalue']), ['4', '101']);
    expect(changes.every((c) => c['surveyor_id'] == null), isTrue);

    // The write itself was never at risk, but it is the thing the audit trail
    // must not be allowed to take down with it.
    final row = (await db.query('visit')).single;
    expect(row['count'], '4');
    expect(row['hhid'], '101');
  });

  test('updateField behaves the same way, as it always has', () async {
    await seed('count', '3');

    await DbService.updateField(
      surveyId: 'log',
      tableName: 'visit',
      field: 'count',
      value: '4',
      where: 'uniqueid = ?',
      whereArgs: ['v-1'],
    );

    final change = (await db.query('formchanges')).single;
    expect(change['fieldname'], 'count');
    expect(change['oldvalue'], '3');
    expect(change['newvalue'], '4');
    expect(change['surveyor_id'], isNull);
    expect((await db.query('visit')).single['count'], '4');
  });
}
