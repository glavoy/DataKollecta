import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/widgets/question_views.dart';

/// A `hourmin` field collects a 24-hour time as `hh:mm`. The separator is
/// inserted by the app, so the interviewer only ever presses digits.
void main() {
  final formatter = HourMinInputFormatter();

  TextEditingValue apply(String current, String next, {int? caret}) =>
      formatter.formatEditUpdate(
        TextEditingValue(
            text: current,
            selection: TextSelection.collapsed(offset: current.length)),
        TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: caret ?? next.length)),
      );

  /// The field contents after typing [next] over [current].
  String typed(String current, String next, {int? caret}) =>
      apply(current, next, caret: caret).text;

  /// Types [keys] one character at a time, as a person would.
  String typeAll(String keys) {
    var text = '';
    for (final key in keys.split('')) {
      text = typed(text, '$text$key');
    }
    return text;
  }

  group('the separator is inserted automatically', () {
    test('it appears with the third digit', () {
      expect(typeAll('09'), '09');
      expect(typeAll('093'), '09:3');
      expect(typeAll('0930'), '09:30');
    });

    test('midnight and the last minute of the day', () {
      expect(typeAll('0000'), '00:00');
      expect(typeAll('2359'), '23:59');
    });

    test('a typed separator completes a single-digit hour', () {
      // "9:" means nine o'clock, not 9x:.
      expect(typed('9', '9:'), '09');
      expect(typeAll('9'), '');
    });
  });

  group('backspacing', () {
    test('deleting a minute digit leaves the rest intact', () {
      expect(typed('09:30', '09:3'), '09:3');
    });

    test('deleting past the separator takes it away too', () {
      // Without this the colon strands itself as "09:" and has to be deleted
      // separately, which is the usual complaint about auto-inserted separators.
      expect(typed('09:3', '09:'), '09');
    });

    test('deleting continues through the hour', () {
      expect(typed('09', '0'), '0');
      expect(typed('0', ''), '');
    });

    test('deleting the separator itself removes the digit before the caret', () {
      // Caret sits between "09" and "30"; the colon is gone from the raw text.
      expect(typed('09:30', '0930', caret: 2), '09:30');
    });

    test('clearing the field is allowed', () {
      expect(typed('09:30', ''), '');
    });
  });

  group('only a real time can be typed', () {
    test('an hour cannot start above 2', () {
      for (final digit in ['3', '4', '9']) {
        expect(typeAll(digit), '', reason: '$digit cannot begin an hour');
      }
    });

    test('an hour cannot exceed 23', () {
      expect(typeAll('24'), '2');
      expect(typeAll('29'), '2');
      expect(typeAll('23'), '23');
    });

    test('a 1x hour accepts any second digit', () {
      expect(typeAll('19'), '19');
    });

    test('minutes cannot exceed 59', () {
      expect(typeAll('12'), '12');
      expect(typeAll('126'), '12');
      expect(typeAll('125'), '12:5');
      expect(typeAll('1259'), '12:59');
    });

    test('letters and punctuation are ignored', () {
      expect(typed('', 'ab'), '');
      expect(typed('12', '12-'), '12');
    });

    test('nothing beyond four digits is kept', () {
      expect(typed('12:34', '12:345'), '12:34');
    });

    test('a pasted time is accepted', () {
      expect(typed('', '0745'), '07:45');
      expect(typed('', '07:45'), '07:45');
    });

    test('a pasted impossible time is refused, leaving the field alone', () {
      // Dropping the offending digit instead would shuffle 25:00 down into
      // 20:0 — a wrong time that looks right.
      expect(typed('', '99:99'), '');
      expect(typed('', '25:00'), '');
      expect(typed('08:15', '25:00'), '08:15');
    });
  });

  group('the caret', () {
    test('stays at the end while typing', () {
      expect(apply('09:3', '09:30').selection.baseOffset, 5);
    });

    test('moves past the separator as it is inserted', () {
      expect(apply('09', '093').selection.baseOffset, 4);
    });
  });
}
