import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;

import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/child_increment_service.dart';
import 'package:datakollecta/services/db_service.dart';

/// The sibling ordinal a new child record gets.
///
/// `SurveyScreen` has no test coverage at all -- no test file references it --
/// so this suite is the proof that pulling `_calculateLineNum` out of it
/// changed nothing. It pins the behaviour the counter actually has, including
/// all three of its degraded paths, which is the part most likely to be
/// "tidied" by someone who assumes a failed read should just start at 1.
///
/// Mirrors the PRISM CSS shape: an `hh_info` parent and an `hh_members` child
/// linked on `hhid`, incrementing `linenum`.
const String surveyId = 'child_increment_test';

Future<Database> buildSurvey({
  String? linkingField = 'hhid',
  int memberRows = 0,
  List<String>? explicitLinenums,
}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE crfs (
      tablename TEXT,
      primarykey TEXT,
      linkingfield TEXT,
      parenttable TEXT,
      incrementfield TEXT
    )
  ''');
  await db.insert('crfs', {
    'tablename': 'hh_members',
    'primarykey': 'hhid,linenum',
    'linkingfield': linkingField,
    'parenttable': 'hh_info',
    'incrementfield': 'linenum',
  });

  await db.execute(
    'CREATE TABLE hh_members (uniqueid TEXT PRIMARY KEY, hhid TEXT, '
    'linenum TEXT)',
  );
  final linenums =
      explicitLinenums ?? [for (var i = 1; i <= memberRows; i++) '$i'];
  for (var i = 0; i < linenums.length; i++) {
    await db.insert('hh_members', {
      'uniqueid': 'mem-$i',
      'hhid': '1010001',
      'linenum': linenums[i],
    });
  }

  DbService.registerDatabaseForTest(surveyId, db);
  addTearDown(() => DbService.unregisterDatabaseForTest(surveyId));
  addTearDown(db.close);
  return db;
}

Question textQuestion(String fieldName) => Question(
      fieldName: fieldName,
      type: QuestionType.text,
      fieldType: 'text',
      text: fieldName,
    );

/// The questions a child form declares, including its increment field.
final childQuestions = [
  textQuestion('hhid'),
  textQuestion('linenum'),
];

Future<AnswerMap> assign({
  required AnswerMap answers,
  List<Question>? questions,
  String? incrementField = 'linenum',
  String? fallbackLinkingField,
}) async {
  await ChildIncrementService.assign(
    questions: questions ?? childQuestions,
    answers: answers,
    surveyId: surveyId,
    tableName: 'hh_members',
    incrementField: incrementField,
    fallbackLinkingField: fallbackLinkingField,
  );
  return answers;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the ordinary path', () {
    test('the first child of a parent gets 1', () async {
      await buildSurvey();

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], '1');
    });

    test('the next child is one past the highest already issued', () async {
      await buildSurvey(memberRows: 5);

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], '6');
    });

    test('siblings are counted per parent, not per table', () async {
      await buildSurvey(memberRows: 5);

      // A different household, with no members yet.
      final answers = await assign(answers: {'hhid': '9990009'});

      expect(answers['linenum'], '1');
    });

    test('a gap in the sequence does not reuse the missing number', () async {
      // Member 2 was deleted. The counter is MAX + 1, not a free-slot search:
      // reusing 2 would collide with a row that may already have synced.
      await buildSurvey(explicitLinenums: ['1', '3', '4']);

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], '5');
    });
  });

  group('nothing to do', () {
    test('writes nothing when the form declares no increment field', () async {
      await buildSurvey(memberRows: 3);

      final answers = await assign(
        answers: {'hhid': '1010001'},
        incrementField: null,
      );

      expect(answers.containsKey('linenum'), isFalse);
    });

    test('writes nothing when the increment field is empty', () async {
      await buildSurvey(memberRows: 3);

      final answers = await assign(
        answers: {'hhid': '1010001'},
        incrementField: '',
      );

      expect(answers.containsKey('linenum'), isFalse);
    });

    test('writes nothing when the survey has no such question', () async {
      // The crfs worksheet names an incrementfield the XML never declares.
      await buildSurvey(memberRows: 3);

      final answers = await assign(
        answers: {'hhid': '1010001'},
        questions: [textQuestion('hhid')],
      );

      expect(answers.containsKey('linenum'), isFalse);
    });
  });

  group('the degraded value, not 1', () {
    // The counter starts at 1, so 0 is a value no legitimate record holds and
    // `WHERE linenum = 0` finds every degraded row. Returning 1 instead would
    // be indistinguishable from a legitimate first child and leave no trace.

    test('when the crfs row declares no linking field', () async {
      await buildSurvey(linkingField: null, memberRows: 3);

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], DbService.degradedIncrementValue.toString());
      expect(answers['linenum'], '0');
    });

    test('when the linking field is declared empty', () async {
      await buildSurvey(linkingField: '', memberRows: 3);

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], '0');
    });

    test('when the parent key is absent from the answers', () async {
      await buildSurvey(memberRows: 3);

      final answers = await assign(answers: {});

      expect(answers['linenum'], '0');
    });

    test('when the parent key is present but empty', () async {
      await buildSurvey(memberRows: 3);

      final answers = await assign(answers: {'hhid': ''});

      expect(answers['linenum'], '0');
    });

    test('when the database cannot be read at all', () async {
      final db = await buildSurvey(memberRows: 3);
      // A closed database is the shape a real read failure takes.
      await db.close();

      final answers = await assign(answers: {'hhid': '1010001'});

      expect(answers['linenum'], '0');

      // Note for anyone debugging a real occurrence: the first read to fail is
      // `getCrfConfig`, which swallows its error and returns null, so this
      // lands on the no-linkingfield branch and logs "No linkingfield
      // configured for hh_members". The value written is right; the sentence
      // is misleading, and it predates this service.
    });

    test('a null answer for the parent key degrades rather than counting all',
        () async {
      await buildSurvey(memberRows: 3);

      final answers = await assign(answers: {'hhid': null});

      expect(answers['linenum'], '0');
    });
  });

  group('a missing table is an absence, not a failure', () {
    test('a table that does not exist yet yields 1, not the sentinel',
        () async {
      final db = await buildSurvey(memberRows: 3);
      await db.execute('DROP TABLE hh_members');

      final answers = await assign(answers: {'hhid': '1010001'});

      // Deliberate, and the distinction matters: a table that does not exist
      // cannot hold siblings, so the first child legitimately gets 1. Only a
      // read that *fails* degrades -- the same split `tryGetExistingRecords`
      // draws between a missing table (empty) and an unreadable one (null).
      // Collapsing the two would either lose a real first child to the
      // sentinel or hide a genuine failure behind a plausible 1.
      expect(answers['linenum'], '1');
    });
  });

  group('the crfs worksheet is authoritative', () {
    test('crfs linkingfield wins over the value passed in', () async {
      await buildSurvey(memberRows: 4);

      // The screen passes a fallback, but crfs says `hhid` -- and crfs is what
      // the foreign key is declared on, so it decides.
      final answers = await assign(
        answers: {'hhid': '1010001', 'barcode': 'B-1'},
        fallbackLinkingField: 'barcode',
      );

      expect(answers['linenum'], '5');
    });

    test('the fallback is used only when crfs declares nothing', () async {
      await buildSurvey(linkingField: null, memberRows: 4);

      final answers = await assign(
        answers: {'hhid': '1010001'},
        fallbackLinkingField: 'hhid',
      );

      expect(answers['linenum'], '5');
    });
  });
}
