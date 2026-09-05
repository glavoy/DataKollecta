import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/services/answer_equality.dart';

/// The single rule for "are these two answers the same", which four services
/// each used to answer differently.
///
/// The cases that matter here are the ones where the old four disagreed: a
/// checkbox `List` against the comma-separated string SQLite stores it as, and
/// a `DateTime` against the ISO text it was loaded from. Both arise in normal
/// edit mode -- `_populateAnswersFromRecord` parses ISO strings back into real
/// `DateTime`s -- which is why they were producing change-summary entries that
/// `formchanges` never recorded.
void main() {
  group('canonical', () {
    test('a checkbox List reads the way the rest of the codebase reads one',
        () {
      // '1,3', not Dart's '[1, 3]'. ChangeSummaryService used the latter,
      // which can never equal the value SQLite holds.
      expect(AnswerEquality.canonical(['1', '3']), '1,3');
      expect(AnswerEquality.canonical(['2']), '2');
    });

    test('a DateTime reads as the ISO text it is stored as', () {
      expect(
        AnswerEquality.canonical(DateTime.utc(2025, 12, 9, 11, 22)),
        '2025-12-09T11:22:00.000Z',
      );
    });

    test('null stays null -- unanswered is not empty', () {
      expect(AnswerEquality.canonical(null), isNull);
      expect(AnswerEquality.canonical(''), '');
    });

    test('everything else is its own toString', () {
      expect(AnswerEquality.canonical('04'), '04');
      expect(AnswerEquality.canonical(4), '4');
    });
  });

  group('sameAnswer', () {
    test('padding is not a change', () {
      expect(AnswerEquality.sameAnswer('04', '4'), isTrue);
      expect(AnswerEquality.sameAnswer(4, '04'), isTrue);
    });

    test('different numbers are a change', () {
      expect(AnswerEquality.sameAnswer('4', '5'), isFalse);
      expect(AnswerEquality.sameAnswer('4', '40'), isFalse);
    });

    test('two long IDs that differ in the last digit are NOT the same', () {
      // The reason this uses num.tryParse and not double.tryParse, and the
      // reason FieldComparator.compare is not reused: as doubles these two
      // barcodes are the same value, so a real change would vanish.
      const a = '12345678901234567';
      const b = '12345678901234568';
      expect(double.parse(a) == double.parse(b), isTrue,
          reason: 'guard: if this ever fails, the hazard is gone');
      expect(AnswerEquality.sameAnswer(a, b), isFalse);
    });

    test('a DateTime equals the ISO text it was loaded from', () {
      // The actual defect. In edit mode one side is a parsed DateTime and the
      // other is the string it came from, and three of the four old
      // implementations called that a change.
      final parsed = DateTime.parse('2025-12-09T11:22:00.000');
      expect(
        AnswerEquality.sameAnswer(parsed, '2025-12-09T11:22:00.000'),
        isTrue,
      );
      expect(AnswerEquality.sameAnswer(parsed, '2025-12-09 11:22:00.000'),
          isTrue);
    });

    test('the same moment written in two zones is the same answer', () {
      expect(
        AnswerEquality.sameAnswer(
            '2025-12-09T11:22:00.000Z', '2025-12-09T13:22:00.000+02:00'),
        isTrue,
      );
    });

    test('different moments are a change', () {
      expect(
        AnswerEquality.sameAnswer(
            '2025-12-09T11:22:00.000Z', '2025-12-09T11:23:00.000Z'),
        isFalse,
      );
    });

    test('a checkbox List equals the string SQLite stores it as', () {
      expect(AnswerEquality.sameAnswer(['1', '3'], '1,3'), isTrue);
    });

    test('checkbox order still counts as a change', () {
      // Deliberately unchanged: all four implementations treated this as a
      // change, and making it order-insensitive is a separate decision about
      // what an edit means.
      expect(AnswerEquality.sameAnswer(['3', '1'], ['1', '3']), isFalse);
    });

    test('null equals null, and nothing else', () {
      expect(AnswerEquality.sameAnswer(null, null), isTrue);
      expect(AnswerEquality.sameAnswer(null, '4'), isFalse);
      expect(AnswerEquality.sameAnswer('4', null), isFalse);
      // Clearing an answer to empty text is a change, not a null.
      expect(AnswerEquality.sameAnswer(null, ''), isFalse);
    });

    test('text that parses as neither number nor date compares exactly', () {
      expect(AnswerEquality.sameAnswer('abc', 'ABC'), isFalse);
      expect(AnswerEquality.sameAnswer('abc', 'abc'), isTrue);
      expect(AnswerEquality.sameAnswer('', ' '), isFalse);
    });
  });

  group('isRepresentationOnlyChange', () {
    test('is true only when the text moved but the meaning did not', () {
      expect(AnswerEquality.isRepresentationOnlyChange('04', '4'), isTrue);
      expect(
        AnswerEquality.isRepresentationOnlyChange(
            DateTime.parse('2025-12-09T11:22:00.000'),
            '2025-12-09 11:22:00.000'),
        isTrue,
      );
    });

    test('an exact match is false -- the caller has already handled it', () {
      expect(AnswerEquality.isRepresentationOnlyChange('4', '4'), isFalse);
    });

    test('a real change is false', () {
      expect(AnswerEquality.isRepresentationOnlyChange('4', '5'), isFalse);
    });

    test('a null on either side is false', () {
      expect(AnswerEquality.isRepresentationOnlyChange(null, '4'), isFalse);
      expect(AnswerEquality.isRepresentationOnlyChange('4', null), isFalse);
    });
  });
}
