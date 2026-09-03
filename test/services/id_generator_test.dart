import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/id_generator.dart';

void main() {
  // Mirrors the AVERT survey config: country(1) + deviceid(3) + mrc(3),
  // with a 4-digit auto-increment suffix.
  const baseId = '2105005';
  const incrementLength = 4;

  int nextFor(List<Map<String, dynamic>> records, {String field = 'subjid'}) {
    return IdGenerator.nextIncrementFrom(
      records: records,
      fieldName: field,
      baseId: baseId,
      incrementLength: incrementLength,
    );
  }

  test('increments past the highest existing ID', () {
    final next = nextFor([
      {'subjid': '21050050001'},
      {'subjid': '21050050002'},
      {'subjid': '21050050003'},
    ]);

    expect(next, 4);
  });

  test('starts at 1 when the table is empty', () {
    expect(nextFor([]), 1);
  });

  test('ignores other columns that share the base ID prefix', () {
    // A value in a non-ID column that matches the base ID prefix and the
    // increment suffix length would previously inflate the counter, skipping
    // IDs. Only the ID column itself may drive the counter.
    final next = nextFor([
      {'subjid': '21050050001', 'villagecode': '21050059999'},
      {'subjid': '21050050002', 'villagecode': '21050058888'},
    ]);

    expect(next, 3);
  });

  test('ignores barcodes and other unrelated identifiers', () {
    final next = nextFor([
      {'subjid': '21050050001', 'barcode': 'R21B-005-YHSU'},
      {'subjid': '21050050002', 'barcode': 'R21B-005-HGU5'},
    ]);

    expect(next, 3);
  });

  test('only counts the named field when several ID columns exist', () {
    // Composite primary keys (e.g. "subjid,visitnum") still generate into a
    // single field; sibling ID columns must not contribute.
    final next = nextFor([
      {'subjid': '21050050001', 'parentid': '21050050050'},
      {'subjid': '21050050002', 'parentid': '21050050051'},
    ]);

    expect(next, 3);
  });

  test('matches the field name case-insensitively', () {
    // getExistingRecords lowercases column names, but XML fieldnames may not be.
    final next = nextFor(
      [
        {'subjid': '21050050007'},
      ],
      field: 'SubjID',
    );

    expect(next, 8);
  });

  test('ignores values whose suffix is the wrong length', () {
    final next = nextFor([
      {'subjid': '21050050002'},
      {'subjid': '2105005123456'},
      {'subjid': '210500599'},
    ]);

    expect(next, 3);
  });

  test('ignores values whose suffix is not numeric', () {
    final next = nextFor([
      {'subjid': '21050050002'},
      {'subjid': '2105005ABCD'},
    ]);

    expect(next, 3);
  });

  test('ignores records from other base IDs', () {
    final next = nextFor([
      {'subjid': '21050050002'},
      {'subjid': '21060060099'},
    ]);

    expect(next, 3);
  });

  test('tolerates null and missing ID values', () {
    final next = nextFor([
      {'subjid': null},
      {'barcode': 'R21B-005-YHSU'},
      {'subjid': '21050050004'},
    ]);

    expect(next, 5);
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

    test('does not poison the counter after a degraded ID was issued', () {
      // The whole reason the band is excluded from MAX. Records 1-3 plus one
      // sentinel: the next ordinary ID is 4, not 10000 (which would not fit
      // four digits and would then fail the capacity check forever).
      final next = nextFor([
        {'subjid': '21050050001'},
        {'subjid': '21050050002'},
        {'subjid': '21050050003'},
        {'subjid': '21050059999'},
      ]);

      expect(next, 4);
    });

    test('ignores every value in the band, not just the top one', () {
      final next = nextFor([
        {'subjid': '21050050007'},
        {'subjid': '21050059990'},
        {'subjid': '21050059995'},
        {'subjid': '21050059999'},
      ]);

      expect(next, 8);
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
    test('throws rather than return a value that will not fit', () {
      // padLeft does not truncate, so returning 9990 here would have produced
      // an 11-character ID in a 10-character scheme once padded -- and 10000
      // an even longer one. Both silently break joins and exports.
      expect(
        () => nextFor([
          {'subjid': '21050059989'},
        ]),
        throwsA(isA<IdCapacityException>()),
      );
    });

    test('the message names the field that needs a wider increment', () {
      expect(
        () => nextFor([
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

    test('the last usable value before the band is still issued', () {
      final next = nextFor([
        {'subjid': '21050059988'},
      ]);

      expect(next, 9989);
      expect(next, lessThan(IdGenerator.sentinelFloorFor(incrementLength)));
    });
  });
}
