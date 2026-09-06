import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/database_response_service.dart';
import 'package:datakollecta/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ResponseFilterSql build(
    List<ResponseFilter> filters, [
    Map<String, dynamic> answers = const {},
  ]) {
    return DatabaseResponseService.buildWhere(filters, answers);
  }

  group('in / not in filters', () {
    test('excludes every value in the list', () {
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'not in', value: '2,3'),
      ]);

      expect(
        sql.whereClause,
        'CAST("linenum" AS INTEGER) NOT IN (CAST(? AS INTEGER), CAST(? AS INTEGER))',
      );
      expect(sql.whereArgs, ['2', '3']);
    });

    test('includes only the values in the list', () {
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'in', value: '4'),
      ]);

      expect(
        sql.whereClause,
        'CAST("linenum" AS INTEGER) IN (CAST(? AS INTEGER))',
      );
      expect(sql.whereArgs, ['4']);
    });

    test('an empty "not in" list adds no clause', () {
      // The first record of a repeating section has nothing selected yet,
      // and excluding nothing means no filter at all.
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'not in', value: ''),
      ]);

      expect(sql.whereClause, isNull);
      expect(sql.whereArgs, isEmpty);
    });

    test('an empty "in" list matches no rows', () {
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'in', value: ''),
      ]);

      expect(sql.whereClause, '1 = 0');
      expect(sql.whereArgs, isEmpty);
    });

    test('an empty "not in" list still applies the other filters', () {
      final sql = build([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'not in', value: ''),
      ]);

      expect(
        sql.whereClause,
        'CAST("hhid" AS INTEGER) = CAST(? AS INTEGER)',
      );
      expect(sql.whereArgs, ['17']);
    });

    test('ignores blank entries and surrounding whitespace', () {
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'not in', value: ' 2, ,3, '),
      ]);

      expect(sql.whereArgs, ['2', '3']);
    });

    test('accepts uppercase and irregular spacing', () {
      final sql = build([
        ResponseFilter(column: 'linenum', operator: 'NOT  IN', value: '2'),
      ]);

      expect(
        sql.whereClause,
        'CAST("linenum" AS INTEGER) NOT IN (CAST(? AS INTEGER))',
      );
    });

    test('compares as text when the list is not numeric', () {
      final sql = build([
        ResponseFilter(column: 'code', operator: 'not in', value: 'A1,B2'),
      ]);

      expect(sql.whereClause, '"code" NOT IN (?, ?)');
      expect(sql.whereArgs, ['A1', 'B2']);
    });

    test('expands placeholders before splitting the list', () {
      final sql = build(
        [
          ResponseFilter(
              column: 'linenum', operator: 'not in', value: '[[usedlines]]'),
        ],
        {'usedlines': '2,3'},
      );

      expect(sql.whereArgs, ['2', '3']);
    });

    test('combines with other filters using AND', () {
      final sql = build([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'not in', value: '2'),
      ]);

      expect(
        sql.whereClause,
        'CAST("hhid" AS INTEGER) = CAST(? AS INTEGER) AND '
        'CAST("linenum" AS INTEGER) NOT IN (CAST(? AS INTEGER))',
      );
      expect(sql.whereArgs, ['17', '2']);
    });
  });

  group('existing filter behavior', () {
    test('numeric equality still casts both sides', () {
      final sql = build([
        ResponseFilter(column: 'hhid', operator: '=', value: '04'),
      ]);

      expect(sql.whereClause, 'CAST("hhid" AS INTEGER) = CAST(? AS INTEGER)');
      expect(sql.whereArgs, ['04']);
    });

    test('non-numeric comparison is left as-is', () {
      final sql = build([
        ResponseFilter(column: 'region', operator: '=', value: 'Central'),
      ]);

      expect(sql.whereClause, '"region" = ?');
      expect(sql.whereArgs, ['Central']);
    });

    test('no filters produces no clause', () {
      final sql = build([]);

      expect(sql.whereClause, isNull);
      expect(sql.whereArgs, isEmpty);
    });
  });

  group('generated SQL runs against SQLite', () {
    late Database database;

    setUp(() async {
      sqfliteFfiInit();
      database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await database.execute(
        'CREATE TABLE hh_members (hhid TEXT, linenum TEXT, participantsname TEXT)',
      );
      for (var i = 1; i <= 4; i++) {
        await database.insert('hh_members', {
          'hhid': '17',
          'linenum': '$i',
          'participantsname': 'Member $i',
        });
      }
      // A second household that must never leak into the results.
      await database.insert('hh_members', {
        'hhid': '18',
        'linenum': '1',
        'participantsname': 'Other household',
      });
    });

    tearDown(() async => database.close());

    Future<List<String>> selectLines(List<ResponseFilter> filters) async {
      final sql = build(filters);
      var query = 'SELECT linenum FROM hh_members';
      if (sql.whereClause != null) {
        query += ' WHERE ${sql.whereClause}';
      }
      final rows = await database.rawQuery(query, sql.whereArgs);
      return rows.map((row) => row['linenum'].toString()).toList();
    }

    test('first net: nobody selected yet, so everyone is offered', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'not in', value: ''),
      ]);

      expect(lines, ['1', '2', '3', '4']);
    });

    test('later net: already-selected members are excluded', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'not in', value: '2,3'),
      ]);

      expect(lines, ['1', '4']);
    });

    test('zero-padded values still match', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'not in', value: '02,03'),
      ]);

      expect(lines, ['1', '4']);
    });

    test('every member already used leaves nothing to offer', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(
            column: 'linenum', operator: 'not in', value: '1,2,3,4'),
      ]);

      expect(lines, isEmpty);
    });

    test('an empty "in" list returns no rows', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'linenum', operator: 'in', value: ''),
      ]);

      expect(lines, isEmpty);
    });

    test('"in" restricts to the listed members', () async {
      final lines = await selectLines([
        ResponseFilter(column: 'hhid', operator: '=', value: '17'),
        ResponseFilter(column: 'linenum', operator: 'in', value: '2,4'),
      ]);

      expect(lines, ['2', '4']);
    });
  });

  group('the operator allowlist', () {
    // The operator is the one part of a filter that can be neither a bound
    // parameter nor a quoted identifier, so it was the one part interpolated
    // into the WHERE clause verbatim -- and the one thing validating
    // identifiers at the door cannot reach. It is now replaced by a table
    // entry rather than sanitized.

    test('every supported spelling still produces its SQL', () {
      String clause(String op) =>
          build([ResponseFilter(column: 'age', operator: op, value: 'x')])
              .whereClause!;

      expect(clause('='), '"age" = ?');
      expect(clause('=='), '"age" = ?');
      expect(clause('!='), '"age" != ?');
      expect(clause('<>'), '"age" <> ?');
      expect(clause('<'), '"age" < ?');
      expect(clause('>='), '"age" >= ?');
      // A dictionary may still carry an entity-encoded operator, and irregular
      // spacing and case were always accepted -- absorbed the same way
      // FieldComparator absorbs them.
      expect(clause('&gt;'), '"age" > ?');
      expect(clause('&lt;='), '"age" <= ?');
      expect(clause('  >=  '), '"age" >= ?');
    });

    test('anything else is refused, not passed through', () {
      for (final op in [
        'LIKE',
        '= 1 OR 1',
        ';DROP TABLE hh_info;--',
        '',
      ]) {
        expect(
          () => build([ResponseFilter(column: 'age', operator: op, value: '1')]),
          throwsA(isA<ArgumentError>()),
          reason: 'should refuse "$op"',
        );
      }
    });
  });

  group('getResponseOptions end to end', () {
    // buildWhere is unit-tested above; this is the whole SELECT, run against
    // real SQLite. The read-back is the part worth pinning: the query names
    // its columns quoted, but sqflite keys the returned row by the column's
    // actual name, so quoting the wrong one silently yields empty labels
    // rather than an error.

    late Database database;

    setUp(() async {
      sqfliteFfiInit();
      database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(database.close);
      // `order` and `group` are SQLite keywords, so this table can only be
      // read at all if every identifier in the statement is quoted.
      await database.execute(
          'CREATE TABLE "order" ("group" TEXT, code TEXT, district TEXT)');
      await database.insert('order', {
        'group': 'North',
        'code': '1',
        'district': 'A',
      });
      await database.insert('order', {
        'group': 'South',
        'code': '2',
        'district': 'B',
      });
      DbService.registerDatabaseForTest('drs', database);
      addTearDown(() => DbService.unregisterDatabaseForTest('drs'));
    });

    test('a keyword table and column are queried and read back', () async {
      final options = await DatabaseResponseService.getResponseOptions(
        'drs',
        ResponseConfig(
          source: ResponseSource.database,
          table: 'order',
          displayColumn: 'group',
          valueColumn: 'code',
          filters: const [],
        ),
        const {},
      );

      expect(options.map((o) => o.label), ['North', 'South']);
      expect(options.map((o) => o.value), ['1', '2']);
    });

    test('a filter narrows it, with the placeholder expanded', () async {
      final options = await DatabaseResponseService.getResponseOptions(
        'drs',
        ResponseConfig(
          source: ResponseSource.database,
          table: 'order',
          displayColumn: 'group',
          valueColumn: 'code',
          filters: [
            ResponseFilter(
                column: 'district', operator: '=', value: '[[chosen]]'),
          ],
        ),
        const {'chosen': 'B'},
      );

      expect(options.single.label, 'South');
    });
  });
}
