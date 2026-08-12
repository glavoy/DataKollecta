import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../config/app_config.dart';
import '../models/question.dart';
import 'app_strings.dart';

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
      int? maxChars;
      bool fixedLength = false;
      if (maxCharsNode != null) {
        final textConfig = maxCharsNode.innerText.trim();
        if (textConfig.startsWith('=')) {
          fixedLength = true;
          maxChars = int.tryParse(textConfig.substring(1));
        } else {
          maxChars = int.tryParse(textConfig);
        }
      }

      // Optional: <numeric_range>=x</numeric_range> for zero padding
      int? numericRange;
      final numericRangeNode = q.getElement('numeric_range');
      if (numericRangeNode != null) {
        final rangeText = numericRangeNode.innerText.trim();
        if (rangeText.startsWith('=')) {
          numericRange = int.tryParse(rangeText.substring(1));
        } else {
          numericRange = int.tryParse(rangeText);
        }
      }

      // Fallback removed: numericRange is purely optional, padding controlled by fixedLength

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
            minValue: minStr != null ? num.tryParse(minStr) : null,
            maxValue: maxStr != null ? num.tryParse(maxStr) : null,
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
              ? true // Default to true when element is absent
              : distinctNode.innerText.trim().toLowerCase() == 'true';

          final emptyMessageNode = responsesNode.getElement('empty_message');
          final emptyMessage = emptyMessageNode?.innerText.trim();

          // Parse optional don't_know and not_in_list nodes
          final dontKnowNode = responsesNode.getElement('dont_know');
          final dontKnowValue = dontKnowNode?.getAttribute('value');
          final dontKnowLabel =
              dontKnowNode?.getAttribute('label') ?? "Don't know";

          final notInListNode = responsesNode.getElement('not_in_list');
          final notInListValue = notInListNode?.getAttribute('value');
          final notInListLabel =
              notInListNode?.getAttribute('label') ?? "Not in this list";

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

      // Parse logic checks - support multiple <logic_check> elements
      final logicChecks = <LogicCheck>[];
      final logicCheckNodes = q.findElements('logic_check');
      for (final logicCheckNode in logicCheckNodes) {
        var msg = logicCheckNode.getAttribute('message');
        var condition = logicCheckNode.innerText.trim();

        // Handle legacy format: "condition; 'message'"
        if (condition.contains(';')) {
          final parts = condition.split(';');
          if (parts.length >= 2) {
            condition = parts[0].trim();
            // If message attribute wasn't provided, use the one from the string
            if (msg == null) {
              msg = parts[1].trim().replaceAll("'", "");
            }
          }
        }

        msg ??= 'Invalid value';

        if (condition.isNotEmpty) {
          logicChecks.add(LogicCheck(message: msg, condition: condition));
        }
      }

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
      DateTime? minDate;
      DateTime? maxDate;
      final dateRangeNode = q.getElement('date_range');
      if (dateRangeNode != null) {
        final minDateNode = dateRangeNode.getElement('min_date');
        if (minDateNode != null) {
          minDate = _parseDate(minDateNode.innerText.trim());
        }

        final maxDateNode = dateRangeNode.getElement('max_date');
        if (maxDateNode != null) {
          maxDate = _parseDate(maxDateNode.innerText.trim());
        }
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

      // Parse calculation
      final calculationNode = q.getElement('calculation');
      final calculation = _parseCalculation(calculationNode);

      // Parse mask
      final maskNode = q.getElement('mask');
      final mask = maskNode?.getAttribute('value');

      questions.add(
        Question(
          type: type,
          fieldName: fieldName,
          fieldType: fieldType,
          text: text,
          maxCharacters: maxChars,
          fixedLength: fixedLength,
          numericRange: numericRange,
          numericCheck: numericCheck,
          options: options,
          responseConfig: responseConfig,
          preSkips: preSkips,
          postSkips: postSkips,
          logicChecks: logicChecks,
          dontKnow: dontKnow,
          refuse: refuse,
          minDate: minDate,
          maxDate: maxDate,
          uniqueCheck: uniqueCheck,
          calculation: calculation,
          mask: mask,
        ),
      );
    }
    return finalizeQuestions(questions);
  }

  /// The end-of-survey screen the survey generator writes into every
  /// questionnaire. Recognised by fieldname *and* exact text, so a
  /// hand-customised message is left alone.
  static const String endOfQuestionsField = 'end_of_questions';
  static const String _generatedEndOfQuestionsText =
      "Press the 'Finish' button to save the data.";

  /// The out-of-range message the generator composes for every numeric
  /// question, always in English. Matched on shape rather than rebuilt from the
  /// parsed bounds, because the spreadsheet's `0.50` and the parsed `0.5` would
  /// not compare equal. A message an author wrote by hand does not look like
  /// this and is left alone.
  static final RegExp _generatedNumericRangeMessage =
      RegExp(r'^Number must be between .+ and .+!$');

  /// Whether [message] is the generator's own wording rather than the author's.
  ///
  /// Unlike the end-of-survey screen, this is translated where it is shown
  /// rather than rewritten at load time: it has a single consumer, so the
  /// parsed questionnaire is left exactly as the XML wrote it.
  static bool isGeneratedNumericRangeMessage(String? message) =>
      message != null && _generatedNumericRangeMessage.hasMatch(message.trim());

  /// Translates the generated end-of-survey screen.
  ///
  /// The survey generator supplies everything else a questionnaire needs —
  /// including the reserved system variables, in the positions that make them
  /// correct — so the only thing left to do here is the wording of this one
  /// screen, which no data dictionary can author.
  ///
  /// Public so the behaviour can be tested without a file on disk.
  @visibleForTesting
  static List<Question> finalizeQuestions(List<Question> questions) {
    final result = List<Question>.from(questions);

    // The generator writes this screen's text, so the app owns its wording and
    // can show it in the right language. Custom text is never touched.
    for (var i = 0; i < result.length; i++) {
      final q = result[i];
      if (q.fieldName.toLowerCase() == endOfQuestionsField &&
          q.text?.trim() == _generatedEndOfQuestionsText) {
        result[i] = _withText(q, const AppStrings(AppConfig.isFrench).pressFinishToSave);
      }
    }

    return result;
  }

  static Question _withText(Question q, String text) => Question(
        type: q.type,
        fieldName: q.fieldName,
        fieldType: q.fieldType,
        text: text,
        maxCharacters: q.maxCharacters,
        fixedLength: q.fixedLength,
        numericRange: q.numericRange,
        numericCheck: q.numericCheck,
        options: q.options,
        responseConfig: q.responseConfig,
        preSkips: q.preSkips,
        postSkips: q.postSkips,
        logicChecks: q.logicChecks,
        dontKnow: q.dontKnow,
        refuse: q.refuse,
        minDate: q.minDate,
        maxDate: q.maxDate,
        uniqueCheck: q.uniqueCheck,
        calculation: q.calculation,
        mask: q.mask,
      );

  static String? _sanitizeField(String? field) {
    if (field == null) return null;
    // Strip [[ and ]] if present
    if (field.startsWith('[[') && field.endsWith(']]')) {
      return field.substring(2, field.length - 2);
    }
    return field;
  }

  /// Parse date string that can be:
  /// - ISO date format (e.g., "2024-01-01")
  /// - Relative format with years (e.g., "-3y" = 3 years ago, "+1y" = 1 year from now)
  /// - Relative format with months (e.g., "-6m" = 6 months ago)
  /// - Relative format with days (e.g., "-30d" = 30 days ago)
  /// - "0" = today
  static DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Handle "0" as today
    if (dateStr == '0') {
      return today;
    }

    // Check for relative date format (e.g., "-3y", "+1y", "-6m", "-30d", "+4w")
    final relativePattern = RegExp(r'^([+-]?\d+)([ymwd])$');
    final match = relativePattern.firstMatch(dateStr);

    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      final unit = match.group(2)!;

      if (value != null) {
        switch (unit) {
          case 'y': // years
            return DateTime(today.year + value, today.month, today.day);
          case 'm': // months
            int newMonth = today.month + value;
            int newYear = today.year;
            while (newMonth > 12) {
              newMonth -= 12;
              newYear++;
            }
            while (newMonth < 1) {
              newMonth += 12;
              newYear--;
            }
            return DateTime(newYear, newMonth, today.day);
          case 'w': // weeks
            return today.add(Duration(days: value * 7));
          case 'd': // days
            return today.add(Duration(days: value));
        }
      }
    }

    // Try parsing as ISO date (e.g., "2025-03-01")
    try {
      final parsed = DateTime.parse(dateStr);
      // If it doesn't contain time separator 'T', ensure it's local midnight
      if (!dateStr.contains('T')) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static CalculationConfig? _parseCalculation(XmlElement? node) {
    if (node == null) return null;

    final type = node.getAttribute('type') ?? 'constant';
    final value = node.getAttribute('value');
    final field = _sanitizeField(node.getAttribute('field'));
    final separator = node.getAttribute('separator');
    final operator = node.getAttribute('operator');
    final unit = node.getAttribute('unit');
    final preserve = node.getAttribute('preserve') == 'true';

    // Parse SQL
    String? sql;
    Map<String, String>? sqlParams;
    if (type == 'query') {
      sql = node.getElement('sql')?.innerText.trim();
      final params = <String, String>{};
      for (final p in node.findElements('parameter')) {
        final name = p.getAttribute('name');
        final sourceField = _sanitizeField(p.getAttribute('field'));
        if (name != null && sourceField != null) {
          params[name] = sourceField;
        }
      }
      if (params.isNotEmpty) sqlParams = params;
    }

    // Parse parts (for concat, math)
    List<CalculationConfig>? parts;
    if (type == 'concat' || type == 'math') {
      parts = [];
      for (final partNode in node.findElements('part')) {
        final part = _parseCalculation(partNode);
        if (part != null) parts.add(part);
      }
    }

    // Parse cases
    List<CaseConfig>? cases;
    CalculationConfig? defaultValue;
    if (type == 'case') {
      cases = [];
      for (final whenNode in node.findElements('when')) {
        final field = _sanitizeField(whenNode.getAttribute('field'));
        final op = whenNode.getAttribute('operator') ?? '=';
        final val = whenNode.getAttribute('value');

        final resultNode = whenNode.getElement('result');
        final result = _parseCalculation(resultNode);

        if (field != null && val != null && result != null) {
          cases.add(CaseConfig(
            field: field,
            operator: op,
            value: val,
            result: result,
          ));
        }
      }

      final elseNode = node.getElement('else');
      if (elseNode != null) {
        final resultNode = elseNode.getElement('result');
        defaultValue = _parseCalculation(resultNode);
      }
    }

    return CalculationConfig(
      type: type,
      value: value,
      field: field,
      sql: sql,
      sqlParams: sqlParams,
      separator: separator,
      operator: operator,
      parts: parts,
      cases: cases,
      defaultValue: defaultValue,
      unit: unit,
      preserve: preserve,
    );
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

  /// Check if a question text starts with "Warning" or "Warning!" (case-insensitive)
  static bool isWarning(String? text) {
    if (text == null) return false;
    final trimmed = text.trim().toLowerCase();
    return trimmed.startsWith('warning') || trimmed.startsWith('avertissement');
  }
}

QuestionType parseQuestionType(String type) {
  switch (type.toLowerCase()) {
    case 'text':
      return QuestionType.text;
    case 'checkbox':
      return QuestionType.checkbox;
    case 'radio':
      return QuestionType.radio;
    case 'information':
      return QuestionType.information;
    case 'date':
      return QuestionType.date;
    case 'combobox':
      return QuestionType.combobox;
    case 'datetime':
      return QuestionType.datetime;
    // All spellings of "automatic". What the question actually does is decided
    // by its fieldname (a reserved variable), by whether it carries a
    // calculation, or by the CRF's idconfig — never by the word used here.
    case 'automatic':
    case 'calc':
    case 'calculation':
    case 'calculated':
      return QuestionType.automatic;
    default:
      return QuestionType.information;
  }
}
