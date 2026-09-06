import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/field_comparator.dart';

/// This is the primary correctness net for comparison logic shared by skip,
/// logic_check, and calculations -- coverage that used to be scattered
/// (skip_service.dart had none of its own) and inconsistent (one engine's
/// checkbox fix never reached the others).
void main() {
  group('resolveText / resolveTextOrEmpty', () {
    test('null resolves to null, or to empty for the *OrEmpty variant', () {
      expect(FieldComparator.resolveText(null), isNull);
      expect(FieldComparator.resolveTextOrEmpty(null), '');
    });

    test('a checkbox List is comma-joined, not bracketed', () {
      expect(FieldComparator.resolveText(['1', '3']), '1,3');
      expect(FieldComparator.resolveText(['99']), '99');
    });

    test('an empty List resolves to empty text, not "[]"', () {
      expect(FieldComparator.resolveText(<String>[]), '');
    });

    test('a plain String passes through unchanged', () {
      expect(FieldComparator.resolveText('1'), '1');
    });

    test('a non-String, non-List value is stringified', () {
      expect(FieldComparator.resolveText(5), '5');
    });
  });

  group('compare -- numeric', () {
    test('equality operators', () {
      expect(FieldComparator.compare('18', '=', '18'), isTrue);
      expect(FieldComparator.compare('18', '=', '17'), isFalse);
      expect(FieldComparator.compare('18', '!=', '17'), isTrue);
      expect(FieldComparator.compare('18', '!=', '18'), isFalse);
    });

    test('ordering operators', () {
      expect(FieldComparator.compare('17', '<', '18'), isTrue);
      expect(FieldComparator.compare('18', '<', '18'), isFalse);
      expect(FieldComparator.compare('18', '>', '17'), isTrue);
      expect(FieldComparator.compare('18', '<=', '18'), isTrue);
      expect(FieldComparator.compare('18', '>=', '18'), isTrue);
      expect(FieldComparator.compare('17', '>=', '18'), isFalse);
    });

    test('numeric parsing wins over accidental lexicographic ordering', () {
      // '9' > '10' lexicographically, but 9 < 10 numerically.
      expect(FieldComparator.compare('9', '<', '10'), isTrue);
      expect(FieldComparator.compare('9', '>', '10'), isFalse);
    });

    test('decimals', () {
      expect(FieldComparator.compare('0.5', '<', '0.75'), isTrue);
    });

    test('two long IDs differing in the last digit are not equal', () {
      // The reason this parses with num and not double. A 17-digit barcode is
      // past a double's exact-integer range, so as doubles these two are the
      // same value -- and a skip or logic_check on a long ID took the branch
      // meant for the other participant.
      const a = '12345678901234567';
      const b = '12345678901234568';
      expect(double.parse(a) == double.parse(b), isTrue,
          reason: 'guard: if this ever fails, the hazard is gone');

      expect(FieldComparator.compare(a, '=', b), isFalse);
      expect(FieldComparator.compare(a, '!=', b), isTrue);
      expect(FieldComparator.compare(a, '<', b), isTrue);
      expect(FieldComparator.compare(b, '>', a), isTrue);
      expect(FieldComparator.compare(a, '=', a), isTrue);
    });

    test('an int and a decimal naming the same value are still equal', () {
      // num mixes int and double freely, so nothing that used to compare
      // equal through double stops doing so.
      expect(FieldComparator.compare('1', '=', '1.0'), isTrue);
      expect(FieldComparator.compare('4', '=', '04'), isTrue);
      expect(FieldComparator.compare('1', '<', '1.5'), isTrue);
      expect(FieldComparator.compare('2', '>', '1.5'), isTrue);
      expect(FieldComparator.compare('1e3', '=', '1000'), isTrue);
    });

    test('a 0x-prefixed string now parses as a number', () {
      // Not a wanted feature -- a consequence of num.tryParse reaching for
      // int.tryParse, which reads a 0x prefix where double.tryParse refused
      // it. Pinned so the widening is a recorded decision rather than a
      // surprise; nothing in a data dictionary is expected to hit it.
      expect(FieldComparator.compare('0x10', '=', '16'), isTrue);
    });
  });

  group('compare -- dates', () {
    test('date-only strings, ordering and equality', () {
      expect(FieldComparator.compare('2024-01-01', '<', '2024-06-01'), isTrue);
      expect(FieldComparator.compare('2024-06-01', '>', '2024-01-01'), isTrue);
      expect(FieldComparator.compare('2024-01-01', '<=', '2024-01-01'), isTrue);
      expect(FieldComparator.compare('2024-01-01', '=', '2024-01-01'), isTrue);
      expect(FieldComparator.compare('2024-01-01', '!=', '2024-06-01'), isTrue);
    });

    test('a datetime and a date-only string at the same moment are equal',
        () {
      expect(
          FieldComparator.compare(
              '2024-01-01T00:00:00', '=', '2024-01-01'),
          isTrue);
    });

    test('this is the tier a plain-string comparison would get wrong', () {
      // Lexicographically '2024-1-9' > '2024-10-1' would be backwards for
      // non-zero-padded input; a true date parse gets it right regardless.
      expect(
          FieldComparator.compare('2024-01-09', '<', '2024-10-01'), isTrue);
    });
  });

  group('compare -- plain strings', () {
    test('equality', () {
      expect(FieldComparator.compare('yes', '=', 'yes'), isTrue);
      expect(FieldComparator.compare('yes', '!=', 'no'), isTrue);
    });

    test('ordering falls back to lexicographic comparison', () {
      expect(FieldComparator.compare('apple', '<', 'banana'), isTrue);
      expect(FieldComparator.compare('banana', '>', 'apple'), isTrue);
      expect(FieldComparator.compare('apple', '<=', 'apple'), isTrue);
    });
  });

  group('compare -- contains / does not contain', () {
    test('membership in a comma-joined checkbox answer', () {
      final selected = FieldComparator.resolveText(['1', '3'])!;
      expect(FieldComparator.compare(selected, 'contains', '3'), isTrue);
      expect(FieldComparator.compare(selected, 'contains', '5'), isFalse);
      expect(
          FieldComparator.compare(selected, 'does not contain', '5'), isTrue);
      expect(FieldComparator.compare(selected, 'does not contain', '3'),
          isFalse);
    });

    test('membership in a plain comma-separated string answer', () {
      expect(FieldComparator.compare('1,99', 'contains', '99'), isTrue);
    });

    test('an empty left side contains nothing', () {
      // The shape an unanswered field takes via resolveTextOrEmpty.
      expect(FieldComparator.compare('', 'contains', '99'), isFalse);
      expect(FieldComparator.compare('', 'does not contain', '99'), isTrue);
    });

    test('contains is case-sensitive to the exact stored value', () {
      expect(FieldComparator.compare('1,3', 'contains', ' 3'), isFalse,
          reason: 'each element is trimmed, but the search value is not, '
              'matching the existing behavior this replaces');
    });
  });

  group('compare -- operator synonyms', () {
    test('== behaves identically to =', () {
      expect(FieldComparator.compare('18', '==', '18'), isTrue);
      expect(FieldComparator.compare('yes', '==', 'yes'), isTrue);
    });

    test('<> behaves identically to !=', () {
      expect(FieldComparator.compare('18', '<>', '17'), isTrue);
      expect(FieldComparator.compare('yes', '<>', 'no'), isTrue);
    });

    test('HTML-entity-encoded operators decode before comparison', () {
      expect(FieldComparator.compare('18', '&gt;', '17'), isTrue);
      expect(FieldComparator.compare('17', '&lt;', '18'), isTrue);
      expect(FieldComparator.compare('18', '&lt;&gt;', '17'), isTrue);
    });
  });

  group('compare -- unrecognized operator', () {
    test('returns false rather than throwing', () {
      expect(FieldComparator.compare('18', '~=', '18'), isFalse);
    });
  });
}
