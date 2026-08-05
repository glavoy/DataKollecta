import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/widgets/question_views.dart';

/// A `text_decimal` field must accept digits and a single decimal point and
/// nothing else — height, weight and muac are collected this way.
void main() {
  final formatter = DecimalTextInputFormatter();

  /// What the field ends up holding after typing [next] over [current].
  String typed(String current, String next) => formatter
      .formatEditUpdate(
        TextEditingValue(
            text: current,
            selection: TextSelection.collapsed(offset: current.length)),
        TextEditingValue(
            text: next, selection: TextSelection.collapsed(offset: next.length)),
      )
      .text;

  group('accepted', () {
    test('digits', () => expect(typed('1', '12'), '12'));
    test('one decimal point', () => expect(typed('12', '12.'), '12.'));
    test('digits after the point', () => expect(typed('12.', '12.5'), '12.5'));
    test('a leading point', () => expect(typed('', '.'), '.'));
    test('leading zeros', () => expect(typed('0', '05'), '05'));
    test('clearing the field', () => expect(typed('12.5', ''), ''));
  });

  group('rejected — the value is left as it was', () {
    test('a second decimal point', () => expect(typed('12.5', '12.5.'), '12.5'));
    test('letters', () => expect(typed('12', '12a'), '12'));
    // A lowercase l for 1 is the mistake the numeric keyboard is meant to
    // prevent; the formatter has to catch it on a keyboard that allows it.
    test('a lowercase L', () => expect(typed('', 'l'), ''));
    test('a comma as separator', () => expect(typed('12', '12,'), '12'));
    test('a minus sign', () => expect(typed('', '-'), ''));
    test('a space', () => expect(typed('12', '12 '), '12'));
    test('a pasted value with two points',
        () => expect(typed('', '1.2.3'), ''));
  });
}
