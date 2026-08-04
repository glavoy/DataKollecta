import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/services/id_generator.dart';

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
}
