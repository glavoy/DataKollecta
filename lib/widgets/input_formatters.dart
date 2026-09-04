import 'package:flutter/services.dart';

/// The `TextInputFormatter`s a question's text field can be given.
///
/// Split out of `question_views.dart`, which was 1,282 lines. These four have
/// no dependency on anything else in that file -- no `Question`, no
/// `AnswerMap`, no `AppStrings`, no `BuildContext`. They take a text edit and
/// return a text edit, which is why two of them already had dedicated test
/// files while most of the widget code around them had none.
///
/// Which formatter a field gets is decided by `_QuestionViewState._buildText`
/// from the question's `fieldType`, `mask` and `fixedLength`.

/// Custom TextInputFormatter that converts all input to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Custom TextInputFormatter that allows digits and a single decimal point.
///
/// The whole value is checked rather than the keystroke, so a paste cannot
/// smuggle in a second point.
class DecimalTextInputFormatter extends TextInputFormatter {
  static final RegExp _decimal = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _decimal.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Custom TextInputFormatter for a 24-hour time, `hh:mm`.
///
/// The separator is inserted for the interviewer as the third digit arrives,
/// so the only key ever pressed is a digit. Editing works on the digits rather
/// than the displayed text, which is what makes backspacing behave: deleting
/// the "3" of `12:34` leaves `12:3`, and deleting again leaves `12` — the
/// separator goes with the digit it was inserted for instead of stranding a
/// trailing colon that has to be deleted separately.
///
/// An edit that would not leave the start of a real time is refused outright,
/// so `9` cannot begin an hour and `12:6` cannot begin a minute. Refusing the
/// whole edit rather than dropping the offending digit matters on a paste:
/// dropping would shuffle `25:00` down into `20:0`, a wrong time that looks
/// right, where refusing leaves the field as it was. The value is therefore
/// always the start of a real time; whether it is *complete* is a separate
/// question, answered by the field's fixed length of 5.
class HourMinInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text;

    // A typed separator means "the hour is finished": "9:" is 09:.
    final separator = raw.indexOf(':');
    if (separator == 1 && _isDigit(raw[0])) {
      raw = '0$raw';
    }

    // Count the digits the caret sits after, so it can be put back in the
    // same place once the separator has moved.
    final caret = newValue.selection.end.clamp(0, raw.length);
    var digitsBeforeCaret = 0;
    for (var i = 0; i < caret; i++) {
      if (_isDigit(raw[i])) digitsBeforeCaret++;
    }

    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (!_startsARealTime(digits)) return oldValue;

    final text = digits.length > 2
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : digits;

    // Never leave the caret before the separator it has just passed.
    var offset = digitsBeforeCaret <= 2
        ? digitsBeforeCaret
        : digitsBeforeCaret + 1;
    offset = offset.clamp(0, text.length);

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) ^ 0x30 <= 9;

  /// Whether these digits are the beginning of a real 24-hour time.
  static bool _startsARealTime(String digits) {
    if (digits.length > 4) return false;
    if (digits.isEmpty) return true;
    if (digits.codeUnitAt(0) > '2'.codeUnitAt(0)) return false;
    if (digits.length >= 2 && int.parse(digits.substring(0, 2)) > 23) {
      return false;
    }
    if (digits.length >= 3 && digits.codeUnitAt(2) > '5'.codeUnitAt(0)) {
      return false;
    }
    return true;
  }
}

/// Custom TextInputFormatter that applies a mask (e.g., "R21-[0-9][0-9][0-9]-[A-Z0-9][0-9A-Z][A-Z0-9][A-Z0-9]")
class MaskedTextInputFormatter extends TextInputFormatter {
  final String mask;
  late final List<_MaskSlot> _slots;

  MaskedTextInputFormatter({required this.mask}) {
    _slots = _parseMaskToSlots(mask);
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (mask.isEmpty) return newValue;

    var text = newValue.text.toUpperCase();
    final prefix = getInitialPrefix(mask);

    // 1. Prevent deleting fixed prefix
    if (text.length < prefix.length &&
        newValue.text.length < oldValue.text.length) {
      return TextEditingValue(
        text: prefix,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
    }

    // 2. Backspace Logic: If user deletes a literal, also delete the preceding placeholder
    if (newValue.text.length < oldValue.text.length &&
        newValue.selection.end < oldValue.text.length) {
      final deletedChar = oldValue.text[newValue.selection.end];
      // Check if the character being deleted is a literal in the mask at that position
      if (newValue.selection.end < _slots.length) {
        final slot = _slots[newValue.selection.end];
        if (slot.literal != null && slot.literal == deletedChar) {
          // It's a literal! Strip one more character from the end to "jump" it
          if (text.isNotEmpty) {
            text = text.substring(0, text.length - 1);
          }
        }
      }
    }

    final buffer = StringBuffer();
    int textIdx = 0;

    for (final slot in _slots) {
      if (textIdx >= text.length) {
        // Auto-fill following literals
        if (slot.literal != null) {
          buffer.write(slot.literal);
        } else {
          break;
        }
      } else {
        if (slot.placeholder != null) {
          // Find next valid char from text that matches placeholder regex
          while (textIdx < text.length &&
              !slot.placeholder!.hasMatch(text[textIdx])) {
            textIdx++;
          }
          if (textIdx < text.length) {
            buffer.write(text[textIdx]);
            textIdx++;
          } else {
            break;
          }
        } else {
          // It's a literal slot
          buffer.write(slot.literal);
          if (textIdx < text.length && text[textIdx] == slot.literal) {
            textIdx++;
          }
        }
      }
    }

    final result = buffer.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  static List<_MaskSlot> _parseMaskToSlots(String mask) {
    final slots = <_MaskSlot>[];
    final regex = RegExp(r'\[([^\]]+)\]|([^\[]+)');
    final matches = regex.allMatches(mask);

    for (final m in matches) {
      if (m.group(1) != null) {
        // Placeholder, e.g., [0-9]
        slots.add(_MaskSlot(placeholder: RegExp(m.group(0)!)));
      } else {
        // Literal, e.g., "R21-"
        final literal = m.group(2)!;
        for (int i = 0; i < literal.length; i++) {
          slots.add(_MaskSlot(literal: literal[i]));
        }
      }
    }
    return slots;
  }

  static String getInitialPrefix(String mask) {
    final slots = _parseMaskToSlots(mask);
    final buffer = StringBuffer();
    for (final slot in slots) {
      if (slot.placeholder != null) break;
      buffer.write(slot.literal);
    }
    return buffer.toString();
  }
}

class _MaskSlot {
  final String? literal;
  final RegExp? placeholder;
  _MaskSlot({this.literal, this.placeholder});
}
