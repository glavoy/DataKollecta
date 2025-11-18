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
          ? int.tryParse(maxCharsNode.innerText.trim())
          : null;

      // Optional: <numeric_check><values ... /></numeric_check>
      NumericCheck? numericCheck;
      final numericNode = q.getElement('numeric_check');
      if (numericNode != null) {
        final valuesNode = numericNode.getElement('values');
        if (valuesNode != null) {
          final minStr = valuesNode.getAttribute('minvalue');
          final maxStr = valuesNode.getAttribute('maxvalue');
          final otherVals = valuesNode.getAttribute('other_values');
          final msg = valuesNode.getAttribute('message');
          numericCheck = NumericCheck(
            minValue: minStr != null ? int.tryParse(minStr) : null,
            maxValue: maxStr != null ? int.tryParse(maxStr) : null,
            otherValues: otherVals,
            message: msg,
          );
        }
      }

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

      // Parse skip conditions
      final preSkips = _parseSkips(q.getElement('preskip'));
      final postSkips = _parseSkips(q.getElement('postskip'));

      // Parse logic check string
      final logicCheckNode = q.getElement('logic_check');
      final logicCheck = logicCheckNode?.innerText.trim();

      // Parse special response values (for date fields)
      final dontKnowNode = q.getElement('dont_know');
      final dontKnow = dontKnowNode?.innerText.trim();

      final refuseNode = q.getElement('refuse');
      final refuse = refuseNode?.innerText.trim();

      questions.add(
        Question(
          type: type,
          fieldName: fieldName,
          fieldType: fieldType,
          text: text,
          maxCharacters: maxChars,
          numericCheck: numericCheck,
          options: options,
          preSkips: preSkips,
          postSkips: postSkips,
          logicCheck: logicCheck,
          dontKnow: dontKnow,
          refuse: refuse,
        ),
      );
    }
    return questions;
  }

  /// Parse skip conditions from preskip or postskip element
  static List<SkipCondition> _parseSkips(XmlElement? skipElement) {
    if (skipElement == null) return [];

    final skips = <SkipCondition>[];
    for (final skipNode in skipElement.findElements('skip')) {
      final fieldName = skipNode.getAttribute('fieldname') ?? '';
      final condition = skipNode.getAttribute('condition') ?? '';
      final response = skipNode.getAttribute('response') ?? '';
      final responseType = skipNode.getAttribute('response_type') ?? 'fixed';
      final skipToFieldName = skipNode.getAttribute('skiptofieldname') ?? '';

      if (fieldName.isNotEmpty && skipToFieldName.isNotEmpty) {
        skips.add(SkipCondition(
          fieldName: fieldName,
          condition: condition,
          response: response,
          responseType: responseType,
          skipToFieldName: skipToFieldName,
        ));
      }
    }
    return skips;
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
}
