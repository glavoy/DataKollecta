import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/automatic_field_service.dart';
import 'package:datakollecta/services/db_service.dart';

const String _surveyId = 'auto_field_test';
const String _idConfig =
    '{"prefix":"","fields":[{"name":"country","length":1},'
    '{"name":"site","length":2}],"incrementLength":3}';

Question automatic(String name, {CalculationConfig? calculation}) => Question(
      type: QuestionType.automatic,
      fieldName: name,
      fieldType: 'text',
      calculation: calculation,
    );

Future<Database> openEnrollee() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
      'CREATE TABLE enrollee (uniqueid TEXT PRIMARY KEY, subjid TEXT, '
      'country TEXT, site TEXT)');
  DbService.registerDatabaseForTest(_surveyId, db);
  addTearDown(() => DbService.unregisterDatabaseForTest(_surveyId));
  addTearDown(db.close);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'gistx',
      packageName: 'com.gistx.gistx',
      version: '1.3.6',
      buildNumber: '17',
      buildSignature: '',
    );
  });

  group('a field with an idconfig', () {
    test('generates an ID from its component answers', () async {
      await openEnrollee();
      final answers = <String, dynamic>{'country': '1', 'site': '07'};

      final result = await AutomaticFieldService.compute(
        question: automatic('subjid'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: _idConfig,
        isEditMode: false,
      );

      expect(result.value, '107001');
      expect(answers['subjid'], '107001');
      expect(result.generationFailed, isFalse);
    });

    test('falls back to -9 when a component answer is missing', () async {
      await openEnrollee();
      final answers = <String, dynamic>{'country': '1'}; // no site

      final result = await AutomaticFieldService.compute(
        question: automatic('subjid'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: _idConfig,
        isEditMode: false,
      );

      // A value no legitimate ID can be, so the affected rows are findable --
      // rather than null, which would lose the interview.
      expect(result.value, AutomaticFieldService.idGenerationFallback);
      expect(result.generationFailed, isTrue);
      expect(answers['subjid'], '-9');
    });

    test('preserves an existing ID in edit mode while components agree',
        () async {
      await openEnrollee();
      final answers = <String, dynamic>{
        'country': '1',
        'site': '07',
        'subjid': '107042',
      };

      final result = await AutomaticFieldService.compute(
        question: automatic('subjid'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: _idConfig,
        isEditMode: true,
      );

      expect(result.wasPreserved, isTrue);
      expect(answers['subjid'], '107042',
          reason: 'editing a record must not renumber it');
    });

    test('regenerates in edit mode once a component answer changes', () async {
      await openEnrollee();
      final answers = <String, dynamic>{
        'country': '2', // was 1 when 107042 was issued
        'site': '07',
        'subjid': '107042',
      };

      final result = await AutomaticFieldService.compute(
        question: automatic('subjid'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: _idConfig,
        isEditMode: true,
      );

      expect(result.wasPreserved, isFalse);
      expect(answers['subjid'], startsWith('207'));
    });

    test('a linking or increment field is never treated as an ID to generate',
        () async {
      await openEnrollee();
      final answers = <String, dynamic>{'country': '1', 'site': '07'};

      // The predicate that guards this lives in SurveyNavigationService; the
      // point here is that this service honours it, because passing the wrong
      // field through would overwrite a correct value with a generated one.
      final result = await AutomaticFieldService.compute(
        question: automatic('linenum'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: _idConfig,
        incrementField: 'linenum',
        isEditMode: false,
      );

      expect(result.value, isNot('107001'));
    });
  });

  group('a field with no idconfig', () {
    test('goes through AutoFields and writes into the map', () async {
      final answers = <String, dynamic>{};

      final result = await AutomaticFieldService.compute(
        question: automatic('swver'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        isEditMode: false,
      );

      // Built from AppConfig rather than written out: `appName` is a
      // compile-time constant, so a literal here passes on the GiSTX axis and
      // fails on the DataKollecta one.
      expect(result.value, '${AppConfig.appName} 1.3.6+17');
      expect(answers['swver'], '${AppConfig.appName} 1.3.6+17');
    });

    test('an ID-shaped field with no idconfig is not generated', () async {
      final answers = <String, dynamic>{'country': '1', 'site': '07'};

      final result = await AutomaticFieldService.compute(
        question: automatic('subjid'),
        answers: answers,
        surveyId: _surveyId,
        tableName: 'enrollee',
        idConfig: null,
        isEditMode: false,
      );

      expect(result.generationFailed, isFalse);
      expect(result.value, isNot('107001'));
    });
  });
}
