// lib/services/survey_loader.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import '../models/question.dart';

class SurveyLoader {
  /// Load and parse a survey XML from assets.
  static Future<List<Question>> loadFromAsset(String assetPath) async {
    final xmlStr = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(xmlStr);

    final questions = <Question>[];
    for (final q in doc.findAllElements('question')) {
      final type = parseQuestionType(q.getAttribute('type') ?? 'information');
      final fieldName = q.getAttribute('fieldname') ?? 'unknown';
      final fieldType = q.getAttribute('fieldtype') ?? 'text';

      // <text>...</text>
      final textNode = q.getElement('text');
      final text = textNode?.innerText.trim();

      // Optional: <maxCharacters>...</maxCharacters>
      final maxCharsNode = q.getElement('maxCharacters');
      final maxChars = maxCharsNode != null
          ? int.tryParse(maxCharsNode.value?.trim() ?? '')
          : null;

      // <responses> -> <response value='x'>Label</response>
      final responsesNode = q.getElement('responses');
      final options = <QuestionOption>[];
      if (responsesNode != null) {
        for (final r in responsesNode.findElements('response')) {
          final value = r.getAttribute('value') ?? '';
          final label = r.innerText.trim();
          options.add(QuestionOption(value: value, label: label));
        }
      }

      questions.add(
        Question(
          type: type,
          fieldName: fieldName,
          fieldType: fieldType,
          text: text,
          maxCharacters: maxChars,
          options: options,
        ),
      );
    }
    return questions;
  }

  /// Very simple placeholder expansion like "This is [[intid]]"
  static String expandPlaceholders(
      String template, Map<String, dynamic> answers) {
    return template.replaceAllMapped(RegExp(r'\[\[(.+?)\]\]'), (m) {
      final key = m.group(1)!;
      final val = answers[key];
      if (val == null) return '';
      if (val is List) return val.join(', ');
      return val.toString();
    });
  }

  // /// Dummy automatic values for now.
  // static String dummyAutomaticValue(String fieldType) {
  //   switch (fieldType.toLowerCase()) {
  //     case 'datetime':
  //       return DateTime.now().toIso8601String();
  //     case 'integer':
  //       return '1';
  //     default:
  //       return 'auto';
  //   }
  // }
}
