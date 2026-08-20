import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/db_service.dart';
import 'package:datakollecta/services/question_cache_service.dart';
import 'package:datakollecta/services/repeat_count_service.dart';

/// Mirrors the PRISM CSS shape: an `hh_info` parent whose `nmembers` question
/// is declared 1..30, and an `hh_members` child linked on `hhid`.
const String surveyId = 'prism_css_test';

Future<Database> buildSurvey({
  required int enforceMode,
  Object? declaredMembers = '6',
  int memberRows = 6,
  String? syncedAt,
}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

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
  await db.insert('crfs', {
    'display_order': 1,
    'tablename': 'hh_info',
    'displayname': 'Household Information',
    'isbase': 1,
    'primarykey': 'hhid',
    'linkingfield': 'hhid',
  });
  await db.insert('crfs', {
    'display_order': 3,
    'tablename': 'hh_members',
    'displayname': 'Household Members',
    'isbase': 0,
    'primarykey': 'hhid,linenum',
    'linkingfield': 'hhid',
    'parenttable': 'hh_info',
    'incrementfield': 'linenum',
    'requireslink': 1,
    'repeat_count_field': 'nmembers',
    'auto_start_repeat': 2,
    'repeat_enforce_count': enforceMode,
  });

  await db.execute(
    'CREATE TABLE hh_info (uniqueid TEXT PRIMARY KEY, hhid TEXT, '
    'nmembers TEXT, lastmod TEXT, synced_at DATETIME)',
  );
  await db.insert('hh_info', {
    'uniqueid': 'hh-1',
    'hhid': '1010001',
    'nmembers': declaredMembers,
    'lastmod': '2026-08-01T00:00:00.000',
    'synced_at': syncedAt,
  });

  await db.execute(
    'CREATE TABLE hh_members (uniqueid TEXT PRIMARY KEY, hhid TEXT, '
    'linenum TEXT, synced_at DATETIME)',
  );
  for (var i = 1; i <= memberRows; i++) {
    await db.insert('hh_members', {
      'uniqueid': 'mem-$i',
      'hhid': '1010001',
      'linenum': '$i',
    });
  }

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

  DbService.registerDatabaseForTest(surveyId, db);
  addTearDown(() async {
    DbService.unregisterDatabaseForTest(surveyId);
    await db.close();
  });
  return db;
}

void seedNmembersQuestion({num? minValue = 1, num? maxValue = 30}) {
  QuestionCacheService().seedForTest(surveyId, [
    Question(
      type: QuestionType.text,
      fieldName: 'nmembers',
      fieldType: 'text_integer',
      numericCheck: (minValue == null && maxValue == null)
          ? null
          : NumericCheck(minValue: minValue, maxValue: maxValue),
    ),
  ]);
}

Future<String?> storedNmembers(Database db) async {
  final rows = await db.query('hh_info', where: 'hhid = ?', whereArgs: ['1010001']);
  return rows.single['nmembers'] as String?;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'surveyor_id': 'SUR-01'});
    QuestionCacheService().clearCache();
  });

  group('parseEnforceMode', () {
    test('reads the INTEGER column, a stringly-typed value, and blank', () {
      expect(RepeatCountService.parseEnforceMode(3), 3);
      expect(RepeatCountService.parseEnforceMode('3'), 3);
      expect(RepeatCountService.parseEnforceMode(' 0 '), 0);
      // Blank means warn, the documented data-dictionary default.
      expect(RepeatCountService.parseEnforceMode(null), 1);
      expect(RepeatCountService.parseEnforceMode('not a number'), 1);
    });
  });

  group('evaluate', () {
    test('a form with no repeat_count_field is not a counted child', () async {
      await buildSurvey(enforceMode: 3);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_info',
        linkingValue: '1010001',
      );

      expect(result, isNull);
    });

    test('matching counts need no reconciliation', () async {
      await buildSurvey(enforceMode: 3, memberRows: 6);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.inSync);
      expect(result.declaredCount, 6);
      expect(result.actualCount, 6);
    });

    test('mode 3 auto-syncs a shortfall that is still within range', () async {
      await buildSurvey(enforceMode: 3, memberRows: 5);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.updateSilently);
      expect(result.actualCount, 5);
    });

    test('mode 3 auto-syncs an extra child added after the loop', () async {
      await buildSurvey(enforceMode: 3, memberRows: 7);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.updateSilently);
      expect(result.actualCount, 7);
    });

    test('mode 1 asks rather than writing', () async {
      await buildSurvey(enforceMode: 1, memberRows: 5);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.askToUpdate);
    });

    test('mode 0 leaves any number of children alone', () async {
      await buildSurvey(enforceMode: 0, memberRows: 2);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.noEnforcement);
    });

    test('mode 2 is settled inside the loop, not here', () async {
      await buildSurvey(enforceMode: 2, memberRows: 5);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.forceModeHandledInLoop);
    });

    test('zero children never auto-syncs a count declared as at least 1',
        () async {
      await buildSurvey(enforceMode: 3, memberRows: 0);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.belowMinimum);
      expect(result.minimum, 1);
    });

    test('the floor outranks even the warn mode prompt', () async {
      await buildSurvey(enforceMode: 1, memberRows: 0);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.belowMinimum);
    });

    test('more children than UpperRange allows is reported, not written',
        () async {
      await buildSurvey(enforceMode: 3, memberRows: 31);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.aboveMaximum);
      expect(result.maximum, 30);
    });

    test('a count question with no declared range keeps the old behaviour',
        () async {
      await buildSurvey(enforceMode: 3, memberRows: 0);
      seedNmembersQuestion(minValue: null, maxValue: null);

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.updateSilently);
    });

    test('a skipped count question stays NULL however many children exist',
        () async {
      await buildSurvey(enforceMode: 3, declaredMembers: null, memberRows: 3);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );

      expect(result!.outcome, RepeatCountOutcome.countNotDeclared);
      expect(result.declaredCount, isNull);
    });
  });

  group('applyCount', () {
    test('writes the actual count onto the parent record', () async {
      final db = await buildSurvey(enforceMode: 3, memberRows: 5);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );
      await RepeatCountService.applyCount(
          surveyId: surveyId, reconciliation: result!);

      expect(await storedNmembers(db), '5');
    });

    test('an already-uploaded parent is queued for re-upload', () async {
      final db = await buildSurvey(
        enforceMode: 3,
        memberRows: 5,
        syncedAt: '2026-08-19T10:00:00.000',
      );
      seedNmembersQuestion();

      final before = await db.query('hh_info');
      expect(before.single['synced_at'], isNotNull);

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );
      await RepeatCountService.applyCount(
          surveyId: surveyId, reconciliation: result!);

      final after = await db.query('hh_info');
      expect(after.single['synced_at'], isNull);
      expect(after.single['lastmod'], isNot('2026-08-01T00:00:00.000'));
    });

    test('the correction is auditable in formchanges', () async {
      final db = await buildSurvey(enforceMode: 3, memberRows: 5);
      seedNmembersQuestion();

      final result = await RepeatCountService.evaluate(
        surveyId: surveyId,
        childTableName: 'hh_members',
        linkingValue: '1010001',
      );
      await RepeatCountService.applyCount(
          surveyId: surveyId, reconciliation: result!);

      final changes = await db.query('formchanges');
      expect(changes, hasLength(1));
      expect(changes.single['tablename'], 'hh_info');
      expect(changes.single['fieldname'], 'nmembers');
      expect(changes.single['uniqueid'], 'hh-1');
      expect(changes.single['oldvalue'], '6');
      expect(changes.single['newvalue'], '5');
      expect(changes.single['surveyor_id'], 'SUR-01');
    });

    test('a write that changes nothing does not force a re-upload', () async {
      final db = await buildSurvey(
        enforceMode: 3,
        memberRows: 6,
        syncedAt: '2026-08-19T10:00:00.000',
      );

      await DbService.updateField(
        surveyId: surveyId,
        tableName: 'hh_info',
        field: 'nmembers',
        value: 6, // stored as the string '6'
        where: 'hhid = ?',
        whereArgs: ['1010001'],
      );

      final after = await db.query('hh_info');
      expect(after.single['synced_at'], '2026-08-19T10:00:00.000');
      expect(await db.query('formchanges'), isEmpty);
    });
  });
}
