import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:datakollecta/services/db_service.dart';
import 'package:datakollecta/services/id_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mirrors the AVERT survey config: country(1) + deviceid(3) + mrc(3),
  // with a 4-digit auto-increment suffix.
  const baseId = '2105005';
  const incrementLength = 4;

  /// The counter as production computes it: the MAX query against a real
  /// SQLite table, then the arithmetic.
  ///
  /// These cases used to drive a pure Dart scan over a list of row maps, which
  /// was a faithful test of a function that no longer exists -- the counter is
  /// now derived by SQL (M2), so the SQL is what has to be tested. Every case
  /// below is the same assertion it always was, restated against a database.
  Future<int> nextFor(
    List<Map<String, Object?>> rows, {
    String field = 'subjid',
    List<String> columns = const ['subjid'],
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute(
      'CREATE TABLE enrollee (${columns.map((c) => '$c TEXT').join(', ')})',
    );
    for (final row in rows) {
      await db.insert('enrollee', row);
    }

    final maxIncrement = await DbService.maxIdIncrementIn(
      db,
      tableName: 'enrollee',
      fieldName: field,
      baseId: baseId,
      incrementLength: incrementLength,
      sentinelFloor: IdGenerator.sentinelFloorFor(incrementLength),
    );

    return IdGenerator.nextIncrementAfter(
      maxIncrement: maxIncrement,
      fieldName: field,
      baseId: baseId,
      incrementLength: incrementLength,
    );
  }

  test('increments past the highest existing ID', () async {
    expect(
      await nextFor([
        {'subjid': '21050050001'},
        {'subjid': '21050050002'},
        {'subjid': '21050050003'},
      ]),
      4,
    );
  });

  test('starts at 1 when the table is empty', () async {
    expect(await nextFor([]), 1);
  });

  test('ignores other columns that share the base ID prefix', () async {
    // A value in a non-ID column that matches the base ID prefix and the
    // increment suffix length would previously inflate the counter, skipping
    // IDs. Only the ID column itself may drive the counter -- which the query
    // now guarantees structurally, by naming that one column.
    expect(
      await nextFor(
        [
          {'subjid': '21050050001', 'villagecode': '21050059999'},
          {'subjid': '21050050002', 'villagecode': '21050058888'},
        ],
        columns: ['subjid', 'villagecode'],
      ),
      3,
    );
  });

  test('ignores barcodes and other unrelated identifiers', () async {
    expect(
      await nextFor(
        [
          {'subjid': '21050050001', 'barcode': 'R21B-005-YHSU'},
          {'subjid': '21050050002', 'barcode': 'R21B-005-HGU5'},
        ],
        columns: ['subjid', 'barcode'],
      ),
      3,
    );
  });

  test('only counts the named field when several ID columns exist', () async {
    // Composite primary keys (e.g. "subjid,visitnum") still generate into a
    // single field; sibling ID columns must not contribute.
    expect(
      await nextFor(
        [
          {'subjid': '21050050001', 'parentid': '21050050050'},
          {'subjid': '21050050002', 'parentid': '21050050051'},
        ],
        columns: ['subjid', 'parentid'],
      ),
      3,
    );
  });

  test('matches the field name as the dictionary spelled it', () async {
    // SQLite column names are case-insensitive, so an XML fieldname of
    // "SubjID" still resolves to the "subjid" column. The old Dart scan had to
    // lowercase the key itself to achieve this.
    expect(
      await nextFor(
        [
          {'subjid': '21050050007'},
        ],
        field: 'SubjID',
      ),
      8,
    );
  });

  test('ignores values whose suffix is the wrong length', () async {
    expect(
      await nextFor([
        {'subjid': '21050050002'},
        {'subjid': '2105005123456'},
        {'subjid': '210500599'},
      ]),
      3,
    );
  });

  test('ignores values whose suffix is not numeric', () async {
    // The reason the query tests the suffix with GLOB rather than relying on
    // CAST: `CAST('ABCD' AS INTEGER)` is 0, but `CAST('12x' AS INTEGER)` is
    // 12, so a CAST alone would let a malformed value advance the counter.
    expect(
      await nextFor([
        {'subjid': '21050050002'},
        {'subjid': '2105005ABCD'},
        {'subjid': '210500512x9'},
      ]),
      3,
    );
  });

  test('ignores records from other base IDs', () async {
    expect(
      await nextFor([
        {'subjid': '21050050002'},
        {'subjid': '21060060099'},
      ]),
      3,
    );
  });

  test('tolerates null and missing ID values', () async {
    expect(
      await nextFor(
        [
          {'subjid': null},
          {'barcode': 'R21B-005-YHSU'},
          {'subjid': '21050050004'},
        ],
        columns: ['subjid', 'barcode'],
      ),
      5,
    );
  });

  test('matches the base ID case-sensitively', () async {
    // `LIKE '<baseId>%'` would have matched both of these, because SQLite's
    // LIKE is ASCII-case-insensitive by default. `substr(...) = ?` does not,
    // which is what String.startsWith did.
    expect(
      await nextFor(
        [
          {'subjid': 'gx570001'},
        ],
        columns: ['subjid'],
      ),
      1,
    );
  });

  group('a prefix carrying SQL wildcard characters', () {
    // The other reason the prefix test is substr-based: a dictionary prefix
    // containing % or _ would be a wildcard inside LIKE, so `A_1` would have
    // matched `AB1` and counted another base ID's records as its own.
    Future<int> nextForPrefix(String prefix, List<String> ids) async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE enrollee (subjid TEXT)');
      for (final id in ids) {
        await db.insert('enrollee', {'subjid': id});
      }
      final max = await DbService.maxIdIncrementIn(
        db,
        tableName: 'enrollee',
        fieldName: 'subjid',
        baseId: prefix,
        incrementLength: 3,
        sentinelFloor: IdGenerator.sentinelFloorFor(3),
      );
      return max;
    }

    test('does not treat _ as a single-character wildcard', () async {
      expect(await nextForPrefix('A_1', ['AB1007', 'A_1002']), 2);
    });

    test('does not treat % as a multi-character wildcard', () async {
      expect(await nextForPrefix('A%1', ['ABC1007', 'A%1002']), 2);
    });
  });

  group('the reserved sentinel band', () {
    test('sits at the top of the range', () {
      expect(IdGenerator.maxIncrementFor(4), 9999);
      expect(IdGenerator.sentinelBandSizeFor(4), 10);
      expect(IdGenerator.sentinelFloorFor(4), 9990);
    });

    test('shrinks to one value where the range cannot spare ten', () {
      // Reserving ten of a two-digit range would cost a tenth of the study's
      // capacity.
      expect(IdGenerator.sentinelBandSizeFor(2), 1);
      expect(IdGenerator.sentinelFloorFor(2), 99);
      expect(IdGenerator.sentinelBandSizeFor(1), 1);
      expect(IdGenerator.sentinelFloorFor(1), 9);
      // Three digits is where ten becomes affordable.
      expect(IdGenerator.sentinelBandSizeFor(3), 10);
      expect(IdGenerator.sentinelFloorFor(3), 990);
    });

    test('does not poison the counter after a degraded ID was issued',
        () async {
      // The whole reason the band is excluded from MAX -- now excluded in the
      // WHERE clause rather than in a Dart loop. Records 1-3 plus one
      // sentinel: the next ordinary ID is 4, not 10000 (which would not fit
      // four digits and would then fail the capacity check forever).
      expect(
        await nextFor([
          {'subjid': '21050050001'},
          {'subjid': '21050050002'},
          {'subjid': '21050050003'},
          {'subjid': '21050059999'},
        ]),
        4,
      );
    });

    test('ignores every value in the band, not just the top one', () async {
      expect(
        await nextFor([
          {'subjid': '21050050007'},
          {'subjid': '21050059990'},
          {'subjid': '21050059995'},
          {'subjid': '21050059999'},
        ]),
        8,
      );
    });
  });

  group('degradedIncrement', () {
    test('starts at the top of the range', () {
      expect(
        IdGenerator.degradedIncrement(incrementLength: 4, priorFailures: 0),
        9999,
      );
      expect(
        IdGenerator.degradedIncrement(incrementLength: 3, priorFailures: 0),
        999,
      );
    });

    test('counts down so repeated failures on one device differ', () {
      final issued = [
        for (var i = 0; i < 4; i++)
          IdGenerator.degradedIncrement(incrementLength: 4, priorFailures: i),
      ];

      expect(issued, [9999, 9998, 9997, 9996]);
    });

    test('wraps within the band rather than escaping it', () {
      // Eleventh failure comes back around to the top; it never descends into
      // the range ordinary IDs are drawn from.
      expect(
        IdGenerator.degradedIncrement(incrementLength: 4, priorFailures: 10),
        9999,
      );
      for (var i = 0; i < 25; i++) {
        final value =
            IdGenerator.degradedIncrement(incrementLength: 4, priorFailures: i);
        expect(value, greaterThanOrEqualTo(IdGenerator.sentinelFloorFor(4)));
        expect(value, lessThanOrEqualTo(IdGenerator.maxIncrementFor(4)));
      }
    });

    test('is a single fixed value where the band is one wide', () {
      for (var i = 0; i < 3; i++) {
        expect(
          IdGenerator.degradedIncrement(incrementLength: 2, priorFailures: i),
          99,
        );
      }
    });
  });

  group('running out of range', () {
    test('throws rather than return a value that will not fit', () async {
      // padLeft does not truncate, so returning 9990 here would have produced
      // an 11-character ID in a 10-character scheme once padded -- and 10000
      // an even longer one. Both silently break joins and exports.
      await expectLater(
        nextFor([
          {'subjid': '21050059989'},
        ]),
        throwsA(isA<IdCapacityException>()),
      );
    });

    test('the message names the field that needs a wider increment', () async {
      await expectLater(
        nextFor([
          {'subjid': '21050059989'},
        ]),
        throwsA(
          isA<IdCapacityException>().having(
            (e) => e.message,
            'message',
            allOf(contains('subjid'), contains('incrementLength')),
          ),
        ),
      );
    });

    test('the last usable value before the band is still issued', () async {
      final next = await nextFor([
        {'subjid': '21050059988'},
      ]);

      expect(next, 9989);
      expect(next, lessThan(IdGenerator.sentinelFloorFor(incrementLength)));
    });
  });
}
