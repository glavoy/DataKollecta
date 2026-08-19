import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/csv_data_service.dart';

void main() {
  // A survey CSV may be authored on any platform: Excel on Windows writes
  // CRLF, a script or editor on macOS/Linux writes LF, and older Mac tools
  // write bare CR. All three must load identically.
  const header = 'mrccode,schoolcode,schoolname';
  const line1 = '40,21090008,Out Citizen Primary School';
  const line2 = '47,21070001,Atauso primary school';

  String build(String eol, {bool trailing = false}) =>
      [header, line1, line2].join(eol) + (trailing ? eol : '');

  void expectBothRows(List<Map<String, String>> rows) {
    expect(rows.length, 2);
    expect(rows[0]['mrccode'], '40');
    expect(rows[0]['schoolcode'], '21090008');
    expect(rows[0]['schoolname'], 'Out Citizen Primary School');
    expect(rows[1]['mrccode'], '47');
    expect(rows[1]['schoolname'], 'Atauso primary school');
  }

  group('line endings', () {
    test('parses Windows CRLF files', () {
      expectBothRows(CsvDataService.parseCsv(build('\r\n')));
    });

    test('parses Linux and macOS LF files', () {
      expectBothRows(CsvDataService.parseCsv(build('\n')));
    });

    test('parses legacy CR files', () {
      expectBothRows(CsvDataService.parseCsv(build('\r')));
    });

    test('every line ending yields identical rows', () {
      final crlf = CsvDataService.parseCsv(build('\r\n'));
      final lf = CsvDataService.parseCsv(build('\n'));
      final cr = CsvDataService.parseCsv(build('\r'));

      expect(lf, crlf);
      expect(cr, crlf);
    });

    test('a trailing newline does not add a blank row', () {
      for (final eol in ['\r\n', '\n', '\r']) {
        expectBothRows(CsvDataService.parseCsv(build(eol, trailing: true)));
      }
    });
  });

  group('row shape', () {
    test('a row missing its trailing comma still parses', () {
      // Real files sometimes omit the trailing separator on the last line.
      final rows = CsvDataService.parseCsv(
        'site,mrccode,schoolcode,schoolname,\n'
        'Akokoro,40,21090008,Out Citizen Primary School,\n'
        'Akokoro,40,21090009,Wangachein Primary School',
      );

      expect(rows.length, 2);
      expect(rows[1]['mrccode'], '40');
      expect(rows[1]['schoolcode'], '21090009');
      expect(rows[1]['schoolname'], 'Wangachein Primary School');
    });

    test('values and headers are trimmed', () {
      final rows = CsvDataService.parseCsv(' mrccode , schoolname \n 40 , Some School \n');

      expect(rows.single['mrccode'], '40');
      expect(rows.single['schoolname'], 'Some School');
    });

    test('quoted values containing commas are preserved', () {
      final rows = CsvDataService.parseCsv(
        'mrccode,schoolname\n40,"St Mary\'s, Apac"\n',
      );

      expect(rows.single['schoolname'], "St Mary's, Apac");
    });

    test('empty content yields no rows', () {
      expect(CsvDataService.parseCsv(''), isEmpty);
    });

    test('a header with no data rows yields no rows', () {
      expect(CsvDataService.parseCsv('mrccode,schoolname\n'), isEmpty);
    });
  });

  group('quoting', () {
    test('an embedded comma does not shift later columns', () {
      final rows = CsvDataService.parseCsv(
        'mrccode,schoolname,schoolcode\n'
        '40,"St Mary\'s, Apac",21090008\n',
      );

      expect(rows.single['schoolname'], "St Mary's, Apac");
      expect(rows.single['schoolcode'], '21090008');
    });

    test('escaped double quotes are unescaped', () {
      // Real villages.csv contains: "BUSAMBEKO ""A"""
      final rows = CsvDataService.parseCsv(
        'villageid,village,mrc\n'
        'v1,"BUSAMBEKO ""A""",Nawaikoke HCIII\n',
      );

      expect(rows.single['village'], 'BUSAMBEKO "A"');
      expect(rows.single['mrc'], 'Nawaikoke HCIII');
    });

    test('leading zeros on fixed-length codes are preserved', () {
      final rows = CsvDataService.parseCsv('mrcid,villageid\n056,01\n');

      expect(rows.single['mrcid'], '056');
      expect(rows.single['villageid'], '01');
    });

    test('decimals and negatives are kept as written', () {
      final rows = CsvDataService.parseCsv('lat,offset\n0.5,-7\n');

      expect(rows.single['lat'], '0.5');
      expect(rows.single['offset'], '-7');
    });

    test('a short row still carries every header', () {
      final rows = CsvDataService.parseCsv('a,b,c\n1,2\n');

      expect(rows.single.keys.toList(), ['a', 'b', 'c']);
      expect(rows.single['c'], '');
    });
  });
}
