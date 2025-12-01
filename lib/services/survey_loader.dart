import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import '../models/question.dart';

class SurveyLoader {
  /// Load and parse a survey XML from a local File.
  static Future<List<Question>> loadFromFile(File file) async {
    final xmlStr = await file.readAsString();
    return _parseXml(xmlStr);
  }

  /// Load and parse a survey XML from assets.
  static Future<List<Question>> loadFromAsset(String assetPath) async {
    final xmlStr = await rootBundle.loadString(assetPath);
    return _parseXml(xmlStr);
  }

  static List<Question> _parseXml(String xmlStr) {
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

      // <responses> - can be static, csv, or database
      final responsesNode = q.getElement('responses');
      final options = <QuestionOption>[];
      ResponseConfig? responseConfig;

      if (responsesNode != null) {
        final sourceAttr = responsesNode.getAttribute('source') ?? 'static';
        final source = _parseResponseSource(sourceAttr);

        if (source == ResponseSource.static_) {
          // Static responses: <response value='x'>Label</response>
          for (final r in responsesNode.findElements('response')) {
            final value = r.getAttribute('value') ?? '';
            final label = r.innerText.trim();
            options.add(QuestionOption(value: value, label: label));
          }
        } else {
          // CSV or Database responses
          final file = responsesNode.getAttribute('file');
          final table = responsesNode.getAttribute('table');
          final filters = <ResponseFilter>[];

          // Parse <filter> elements
          for (final filterNode in responsesNode.findElements('filter')) {
            final column = filterNode.getAttribute('column') ?? '';
            final value = filterNode.getAttribute('value') ?? '';
            final operator = filterNode.getAttribute('operator') ?? '=';

            if (column.isNotEmpty) {
              filters.add(ResponseFilter(
                column: column,
                value: value,
                operator: operator,
              ));
            }
          }

          // Parse <display>, <value>, <distinct>, <empty_message>
          final displayNode = responsesNode.getElement('display');
          final displayColumn = displayNode?.getAttribute('column');

          final valueNode = responsesNode.getElement('value');
          final valueColumn = valueNode?.getAttribute('column');

          final distinctNode = responsesNode.getElement('distinct');
          final distinct = distinctNode == null
              ? true  // Default to true when element is absent
              : distinctNode.innerText.trim().toLowerCase() == 'true';

          final emptyMessageNode = responsesNode.getElement('empty_message');
          final emptyMessage = emptyMessageNode?.innerText.trim();

          // Parse optional don't_know and not_in_list nodes
          final dontKnowNode = responsesNode.getElement('dont_know');
          final dontKnowValue = dontKnowNode?.getAttribute('value');
          final dontKnowLabel = dontKnowNode?.getAttribute('label') ?? "Don't know";

          final notInListNode = responsesNode.getElement('not_in_list');
          final notInListValue = notInListNode?.getAttribute('value');
          final notInListLabel = notInListNode?.getAttribute('label') ?? "Not in this list";

          responseConfig = ResponseConfig(
            source: source,
            file: file,
            table: table,
            filters: filters,
            displayColumn: displayColumn,
            valueColumn: valueColumn,
            distinct: distinct,
            emptyMessage: emptyMessage,
            dontKnowValue: dontKnowValue,
            dontKnowLabel: dontKnowLabel,
            notInListValue: notInListValue,
            notInListLabel: notInListLabel,
          );
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

      // Auto-add special options if they don't exist in the list
      if (dontKnow != null && dontKnow.isNotEmpty) {
        if (!options.any((opt) => opt.value == dontKnow)) {
          options.add(QuestionOption(value: dontKnow, label: "Don't know"));
        }
      }

      if (refuse != null && refuse.isNotEmpty) {
        if (!options.any((opt) => opt.value == refuse)) {
          options.add(QuestionOption(value: refuse, label: "Refuse to answer"));
        }
      }

      // Parse date range
      String? minDate;
      String? maxDate;
      final dateRangeNode = q.getElement('date_range');
      if (dateRangeNode != null) {
        final minDateNode = dateRangeNode.getElement('min_date');
        minDate = minDateNode?.innerText.trim();

        final maxDateNode = dateRangeNode.getElement('max_date');
        maxDate = maxDateNode?.innerText.trim();
      }

      // Parse unique check
      UniqueCheck? uniqueCheck;
      final uniqueCheckNode = q.getElement('unique_check');
      if (uniqueCheckNode != null) {
        final messageNode = uniqueCheckNode.getElement('message');
        uniqueCheck = UniqueCheck(
          message: messageNode?.innerText.trim(),
        );
      }

      questions.add(
        Question(
          type: type,
          fieldName: fieldName,
          fieldType: fieldType,
          text: text,
          maxCharacters: maxChars,
          numericCheck: numericCheck,
          options: options,
          responseConfig: responseConfig,
          preSkips: preSkips,
          postSkips: postSkips,
          logicCheck: logicCheck,
          dontKnow: dontKnow,
          refuse: refuse,
          minDate: minDate,
          maxDate: maxDate,
          uniqueCheck: uniqueCheck,
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

  /// Parse response source type
  static ResponseSource _parseResponseSource(String source) {
    switch (source.toLowerCase()) {
      case 'csv':
        return ResponseSource.csv;
      case 'database':
        return ResponseSource.database;
      case 'static':
      default:
        return ResponseSource.static_;
    }
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
