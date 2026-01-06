// lib/widgets/question_views.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../services/auto_fields.dart';
import '../services/csv_data_service.dart';
import '../services/database_response_service.dart';

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

class QuestionView extends StatefulWidget {
  final Question question;
  final AnswerMap answers; // shared map so we can restore / persist answers
  final void Function(String fieldName, dynamic oldValue, dynamic newValue)?
      onAnswerChanged;
  final VoidCallback? onRequestNext; // ask parent to navigate to next question
  final bool isEditMode; // Whether we're editing an existing record
  final String? logicError; // The logic check error message to display
  final CsvDataService csvDataService;
  final String surveyId;

  const QuestionView({
    super.key,
    required this.question,
    required this.answers,
    this.onAnswerChanged,
    this.onRequestNext,
    this.isEditMode = false,
    this.logicError,
    required this.csvDataService,
    required this.surveyId,
  });

  @override
  State<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<QuestionView> {
  late TextEditingController _textController;
  late FocusNode _textFocusNode;
  late Set<String> _checkboxSelection;
  String? _radioSelection;
  String? _comboboxSelection;
  DateTime? _selectedDate;
  DateTime? _selectedDateTime;
  List<QuestionOption> _dynamicOptions = [];
  final ScrollController _radioScrollController = ScrollController();
  final ScrollController _checkboxScrollController = ScrollController();

  String _normalizeValue(dynamic value) {
    if (value == null) return '';
    String s = value.toString();
    if (widget.question.fixedLength &&
        widget.question.maxCharacters != null &&
        s.isNotEmpty) {
      if (int.tryParse(s) != null) {
        return s.padLeft(widget.question.maxCharacters!, '0');
      }
    }
    return s;
  }

  @override
  void initState() {
    super.initState();

    // Seed state from existing answers if any:
    final q = widget.question;
    final existing = widget.answers[q.fieldName];

    // Handle padding for fixed length numeric fields
    String initialText = _normalizeValue(existing);
    final originalText = initialText;

    // If there's a mask and it's a new record, initialize with prefix
    if (q.type == QuestionType.text && initialText.isEmpty && q.mask != null) {
      initialText = MaskedTextInputFormatter.getInitialPrefix(q.mask!);
    }

    _textFocusNode = FocusNode();
    _textController = TextEditingController(
      text: initialText,
    );

    // If we padded the text, update the source of truth immediately
    if (initialText != originalText) {
      debugPrint(
          '[QuestionView] ${q.fieldName} padding triggered: "$originalText" -> "$initialText"');
      widget.answers[q.fieldName] = initialText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onAnswerChanged?.call(q.fieldName, originalText, initialText);
        }
      });
    }

    _checkboxSelection = {
      if (existing is List) ...existing.map((e) => _normalizeValue(e)),
    };

    // Convert existing value to string for radio/combobox
    // This ensures consistency with option values from CSV/database
    _radioSelection = existing != null ? _normalizeValue(existing) : null;
    _comboboxSelection = existing != null ? _normalizeValue(existing) : null;

    // Handle date/datetime initialization
    if (existing is DateTime) {
      _selectedDate = existing;
      _selectedDateTime = existing;
    } else if (existing is String && existing.isNotEmpty) {
      // Check if it's a special response value (e.g., "-7", "-8")
      final isSpecialResponse = existing == q.dontKnow || existing == q.refuse;

      if (!isSpecialResponse) {
        try {
          final parsed = DateTime.parse(existing);
          _selectedDate = parsed;
          _selectedDateTime = parsed;
        } catch (_) {
          // Not a valid date string
        }
      }
    }

    // Centralized automatic variable calculation
    // Only compute automatic fields, NOT date/datetime fields
    // Centralized automatic variable calculation
    // Only compute automatic fields, NOT date/datetime fields
    // Date/datetime fields should require explicit user selection
    if (q.type == QuestionType.automatic || q.calculation != null) {
      // Force calculation if it's automatic OR has a calculation defined
      // We do NOT check 'existing == null' here anymore, because we want updates
      // to propagate (AutoFields.compute handles 'preserve' flag if needed).
      _computeAutoValue();
    }

    // Autofocus text input on initial load when applicable
    if (q.type == QuestionType.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }

    // Load dynamic options for CSV/database sources
    if (q.responseConfig != null) {
      _loadDynamicOptions();
    }
  }

  Future<void> _computeAutoValue() async {
    final rawVal = await AutoFields.compute(widget.answers, widget.question,
        isEditMode: widget.isEditMode, surveyId: widget.surveyId);
    if (mounted) {
      final val = _normalizeValue(rawVal);
      final oldVal = widget.answers[widget.question.fieldName]?.toString();
      final newVal = val;
      final hasChanged = oldVal != newVal;

      setState(() {
        if (widget.question.type == QuestionType.automatic) {
          // For automatic, just update answers
        } else if (widget.question.type == QuestionType.datetime) {
          _selectedDateTime = DateTime.tryParse(val);
        } else if (widget.question.type == QuestionType.date) {
          try {
            _selectedDate = DateTime.parse(val);
          } catch (_) {}
        }
        // Update controller for text-based auto fields if any
        if (widget.question.type == QuestionType.text) {
          _textController.text = val;
        }

        // Always update the answers map
        widget.answers[widget.question.fieldName] = val;
      });

      if (hasChanged) {
        debugPrint(
            '[QuestionView] ${widget.question.fieldName} auto value change: "$oldVal" -> "$newVal"');
        widget.onAnswerChanged?.call(widget.question.fieldName, oldVal, newVal);
      }
    }
  }

  Future<void> _loadDynamicOptions() async {
    final config = widget.question.responseConfig;
    if (config == null) return;

    try {
      List<QuestionOption> options = [];

      if (config.source == ResponseSource.csv) {
        options = await widget.csvDataService
            .getResponseOptions(config, widget.answers);
      } else if (config.source == ResponseSource.database) {
        options = await DatabaseResponseService.getResponseOptions(
          widget.surveyId,
          config,
          widget.answers,
        );
      }

      // Normalize option values for fixed-length fields
      options = options.map((opt) {
        final normalizedValue = _normalizeValue(opt.value);
        if (normalizedValue != opt.value) {
          return QuestionOption(value: normalizedValue, label: opt.label);
        }
        return opt;
      }).toList();

      if (mounted) {
        setState(() {
          _dynamicOptions = options;
        });

        // Update answers map if current selection exists in options
        if (_radioSelection != null &&
            options.any((opt) => opt.value == _radioSelection)) {
          final currentVal =
              widget.answers[widget.question.fieldName]?.toString();
          if (currentVal != _radioSelection) {
            debugPrint(
                '[QuestionView] ${widget.question.fieldName} dynamic option match but value mismatch: currentVal="$currentVal", _radioSelection="$_radioSelection"');
            widget.answers[widget.question.fieldName] = _radioSelection;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onAnswerChanged?.call(
                    widget.question.fieldName, currentVal, _radioSelection);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading dynamic options: $e');
      if (mounted) {
        setState(() {
          _dynamicOptions = [];
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant QuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If we navigated to a different question, refresh local state
    if (oldWidget.question.fieldName != widget.question.fieldName) {
      final existing = widget.answers[widget.question.fieldName];

      // Reset text field
      _textController.text = _normalizeValue(existing);

      // Reset radio/checkbox/combobox selections
      // Convert to string to ensure consistency with option values
      _radioSelection = existing != null ? _normalizeValue(existing) : null;
      _comboboxSelection = existing != null ? _normalizeValue(existing) : null;
      _checkboxSelection = {
        if (existing is List) ...existing.map((e) => _normalizeValue(e)),
      };
      // Reset date/datetime
      if (existing is DateTime) {
        _selectedDate = existing;
        _selectedDateTime = existing;
      } else if (existing is String && existing.isNotEmpty) {
        try {
          final parsed = DateTime.parse(existing);
          _selectedDate = parsed;
          _selectedDateTime = parsed;
        } catch (_) {
          _selectedDate = null;
          _selectedDateTime = null;
        }
      } else {
        _selectedDate = null;
        _selectedDateTime = null;
      }
      setState(() {}); // ensure rebuild

      // Request focus for text questions when they appear
      if (widget.question.type == QuestionType.text) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _textFocusNode.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _textFocusNode.dispose();
    _textController.dispose();
    _radioScrollController.dispose();
    _checkboxScrollController.dispose();
    super.dispose();
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildInformation(Question q) {
    final display = q.text != null
        ? SurveyLoader.expandPlaceholders(q.text!, widget.answers)
        : '';
    final isWarning = SurveyLoader.isWarning(display);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty)
          _buildSectionTitle(isWarning ? 'Warning' : 'Information'),
        Container(
          decoration: BoxDecoration(
            color: isWarning
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.amber.shade900.withValues(alpha: 0.2)
                    : Colors.amber.shade50)
                : Colors.white,
            border: isWarning
                ? Border.all(color: Colors.amber.shade400, width: 2)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWarning) ...[
                Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.amber.shade200
                        : Colors.amber.shade900,
                    size: 28),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  display,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isWarning ? FontWeight.bold : null,
                    color: isWarning
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.amber.shade100
                            : Colors.amber.shade900)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.black87
                            : null),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildText(Question q) {
    final isIntegerField = q.fieldType.toLowerCase().contains('integer');
    final formatters = <TextInputFormatter>[];
    if (q.maxCharacters != null) {
      formatters.add(LengthLimitingTextInputFormatter(q.maxCharacters));
    }
    if (isIntegerField) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    } else {
      if (q.mask != null) {
        formatters.add(MaskedTextInputFormatter(mask: q.mask!));
      } else {
        // For non-integer fields, convert text to uppercase
        formatters.add(UpperCaseTextFormatter());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textController,
          focusNode: _textFocusNode,
          autofocus: true,
          maxLength: q.maxCharacters,
          minLines: 1,
          maxLines: 6,
          maxLengthEnforcement: q.maxCharacters != null
              ? MaxLengthEnforcement.enforced
              : MaxLengthEnforcement.none,
          keyboardType:
              isIntegerField ? TextInputType.number : TextInputType.text,
          inputFormatters: formatters,
          decoration: const InputDecoration(
            hintText: 'Type your answer',
          ),
          onChanged: (val) {
            final old = widget.answers[q.fieldName];
            if (old == val) return;
            widget.answers[q.fieldName] = val;
            widget.onAnswerChanged?.call(q.fieldName, old, val);
          },
        ),
      ],
    );
  }

  Widget _buildRadio(Question q) {
    // Use dynamic options if available, otherwise use static options
    final options = _dynamicOptions.isNotEmpty ? _dynamicOptions : q.options;

    debugPrint(
        '[QuestionView] Building radio for ${q.fieldName}: _radioSelection=$_radioSelection, options.length=${options.length}, _dynamicOptions.length=${_dynamicOptions.length}');

    // Show empty message if no options and config has empty message
    if (options.isEmpty && q.responseConfig?.emptyMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((q.text ?? '').isNotEmpty)
            _buildSectionTitle(
                SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              q.responseConfig!.emptyMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Radio buttons
        RadioGroup<String>(
          groupValue: _radioSelection,
          onChanged: (val) {
            if (val == null) return;
            final old = widget.answers[q.fieldName];
            if (old == val) return;
            setState(() {
              _radioSelection = val;
              widget.answers[q.fieldName] = val;
            });
            widget.onAnswerChanged?.call(q.fieldName, old, val);
          },
          child: Column(
            children: options.map(
              (opt) {
                // Check if this is a special response option
                final isDontKnow = q.dontKnow != null && opt.value == q.dontKnow;
                final isRefuse = q.refuse != null && opt.value == q.refuse;
                final isSpecial = isDontKnow || isRefuse;

                final radioTile = AppRadioTheme(
                  child: Builder(
                    builder: (context) => RadioListTile<String>(
                      value: opt.value,
                      title: Text(
                        opt.label,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black87
                              : null,
                        ),
                      ),
                      dense: true,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor: isSpecial
                          ? (isDontKnow
                              ? Colors.orange.shade100
                              : Colors.red.shade100)
                          : Colors.white,
                    ),
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: isSpecial
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 0.5,
                            child: radioTile,
                          ),
                        )
                      : radioTile,
                );
              },
            ).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(Question q) {
    // Debug: Log checkbox state
    debugPrint(
        'Building checkbox ${q.fieldName}, selection: $_checkboxSelection');

    // Use dynamic options if available, otherwise use static options
    final options = _dynamicOptions.isNotEmpty ? _dynamicOptions : q.options;

    // Show empty message if no options and config has empty message
    if (options.isEmpty && q.responseConfig?.emptyMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((q.text ?? '').isNotEmpty)
            _buildSectionTitle(
                SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              q.responseConfig!.emptyMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    }

    // Get special option values (from static config or dynamic config)
    final dontKnowValue = q.responseConfig?.dontKnowValue ?? q.dontKnow;
    final refuseValue = q.refuse;
    final notInListValue = q.responseConfig?.notInListValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox options
        Column(
          children: options.map((opt) {
            final checked = _checkboxSelection.contains(opt.value);
            debugPrint(
                '  Option ${opt.value} (${opt.label}): checked=$checked');

            // Check if this is a special response option
            final isDontKnow =
                dontKnowValue != null && opt.value == dontKnowValue;
            final isRefuse = refuseValue != null && opt.value == refuseValue;
            final isSpecial = isDontKnow || isRefuse;

            final checkboxTile = CheckboxListTile(
              value: checked,
              dense: true,
              title: Text(
                opt.label,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black87
                      : null,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tileColor: isSpecial
                  ? (isDontKnow ? Colors.orange.shade100 : Colors.red.shade100)
                  : Colors.white,
              onChanged: (val) {
                final oldValues = _checkboxSelection.toList();
                setState(() {
                  // Check if this is a special option (don't know, refuse, not in list)
                  final isSpecial = opt.value == dontKnowValue ||
                      opt.value == refuseValue ||
                      opt.value == notInListValue;

                  if (val == true) {
                    if (isSpecial) {
                      // If selecting a special option, clear everything else
                      _checkboxSelection.clear();
                      _checkboxSelection.add(opt.value);
                    } else {
                      // If selecting a normal option, remove any special options
                      if (dontKnowValue != null)
                        _checkboxSelection.remove(dontKnowValue);
                      if (refuseValue != null)
                        _checkboxSelection.remove(refuseValue);
                      if (notInListValue != null)
                        _checkboxSelection.remove(notInListValue);
                      _checkboxSelection.add(opt.value);
                    }
                  } else {
                    // Deselecting is always allowed
                    _checkboxSelection.remove(opt.value);
                  }
                  widget.answers[q.fieldName] = _checkboxSelection.toList();
                });

                final newValues = _checkboxSelection.toList();
                bool changed = oldValues.length != newValues.length ||
                    !oldValues.every((v) => newValues.contains(v));

                if (changed) {
                  widget.onAnswerChanged
                      ?.call(q.fieldName, oldValues, newValues);
                }
              },
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: isSpecial
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        child: checkboxTile,
                      ),
                    )
                  : checkboxTile,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCombobox(Question q) {
    // Use dynamic options if available, otherwise use static options
    final options = _dynamicOptions.isNotEmpty ? _dynamicOptions : q.options;

    // Show empty message if no options and config has empty message
    if (options.isEmpty && q.responseConfig?.emptyMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((q.text ?? '').isNotEmpty)
            _buildSectionTitle(
                SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              q.responseConfig!.emptyMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DropdownButton<String>(
            value: _comboboxSelection,
            hint: const Text('Select an option'),
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black87
                  : Colors.black87,
            ),
            items: options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt.value,
                child: Text(opt.label),
              );
            }).toList(),
            onChanged: (val) {
              final old = widget.answers[q.fieldName];
              if (old == val) return;
              setState(() {
                _comboboxSelection = val;
                widget.answers[q.fieldName] = val;
              });
              widget.onAnswerChanged?.call(q.fieldName, old, val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDate(Question q) {
    // Check if current answer is a special response
    final currentAnswer = widget.answers[q.fieldName]?.toString();
    // Only match special response if answer exists and is non-empty, and special response is defined
    final isDontKnow = currentAnswer != null &&
        currentAnswer.isNotEmpty &&
        q.dontKnow != null &&
        currentAnswer == q.dontKnow;
    final isRefuse = currentAnswer != null &&
        currentAnswer.isNotEmpty &&
        q.refuse != null &&
        currentAnswer == q.refuse;
    final hasSpecialResponse = isDontKnow || isRefuse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            // Calculate date limits
            DateTime firstDate = DateTime(1900);
            DateTime lastDate = DateTime(2100);

            // Fix: parse string to DateTime for minDate/maxDate
            if (q.minDate != null) {
              // q.minDate is already DateTime? in our model
              firstDate = q.minDate!;
            }

            if (q.maxDate != null) {
              lastDate = q.maxDate!;
            }

            // Ensure initial date is within range
            DateTime initialDate = _selectedDate ?? DateTime.now();
            if (initialDate.isBefore(firstDate)) initialDate = firstDate;
            if (initialDate.isAfter(lastDate)) initialDate = lastDate;

            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (picked != null) {
              final newVal = picked.toIso8601String().split('T')[0];
              final old = widget.answers[q.fieldName];
              if (old == newVal) return;
              setState(() {
                _selectedDate = picked;
                // For 'date' type, store as 'YYYY-MM-DD' string
                widget.answers[q.fieldName] = newVal;
              });
              widget.onAnswerChanged?.call(q.fieldName, old, newVal);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasSpecialResponse
                      ? (isDontKnow ? "Don't know" : 'Refuse')
                      : (_selectedDate != null
                          ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                          : 'Select a date'),
                  style: TextStyle(
                    fontSize: 16,
                    color: hasSpecialResponse
                        ? Colors.orange.shade700
                        : (_selectedDate != null ? Colors.black : Colors.grey),
                    fontWeight: hasSpecialResponse
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
                Icon(Icons.calendar_today, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
        // Special response buttons for date fields
        if (q.dontKnow != null || q.refuse != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (q.dontKnow != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final old = widget.answers[q.fieldName];
                        setState(() {
                          _selectedDate = null;
                          widget.answers[q.fieldName] = q.dontKnow;
                        });
                        widget.onAnswerChanged
                            ?.call(q.fieldName, old, q.dontKnow);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor:
                            isDontKnow ? Colors.orange.shade50 : null,
                        side: BorderSide(
                          color: isDontKnow
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                          width: isDontKnow ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Don't know",
                        style: TextStyle(
                          color: isDontKnow
                              ? Colors.orange.shade700
                              : Colors.grey.shade700,
                          fontWeight:
                              isDontKnow ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                if (q.dontKnow != null && q.refuse != null)
                  const SizedBox(width: 12),
                if (q.refuse != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final old = widget.answers[q.fieldName];
                        setState(() {
                          _selectedDate = null;
                          widget.answers[q.fieldName] = q.refuse;
                        });
                        widget.onAnswerChanged
                            ?.call(q.fieldName, old, q.refuse);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor:
                            isRefuse ? Colors.orange.shade50 : null,
                        side: BorderSide(
                          color: isRefuse
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                          width: isRefuse ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Refuse',
                        style: TextStyle(
                          color: isRefuse
                              ? Colors.orange.shade700
                              : Colors.grey.shade700,
                          fontWeight:
                              isRefuse ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDateTime(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final old = widget.answers[q.fieldName];
            final pickedDate = await showDatePicker(
              context: context,
              initialDate: _selectedDateTime ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (pickedDate != null) {
              final pickedTime = await showTimePicker(
                context: context,
                initialTime:
                    TimeOfDay.fromDateTime(_selectedDateTime ?? DateTime.now()),
              );
              if (pickedTime != null) {
                final combined = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
                if (widget.answers[q.fieldName] == combined.toIso8601String())
                  return;
                setState(() {
                  _selectedDateTime = combined;
                  widget.answers[q.fieldName] = combined.toIso8601String();
                });
                widget.onAnswerChanged
                    ?.call(q.fieldName, old, combined.toIso8601String());
              }
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDateTime != null
                      ? '${_selectedDateTime!.year}-${_selectedDateTime!.month.toString().padLeft(2, '0')}-${_selectedDateTime!.day.toString().padLeft(2, '0')} ${_selectedDateTime!.hour.toString().padLeft(2, '0')}:${_selectedDateTime!.minute.toString().padLeft(2, '0')}'
                      : 'Select date and time',
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        _selectedDateTime != null ? Colors.black : Colors.grey,
                  ),
                ),
                Icon(Icons.calendar_today, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    switch (q.type) {
      case QuestionType.automatic:
        final val = widget.answers[q.fieldName]?.toString() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(SurveyLoader.expandPlaceholders(
                q.text ?? 'Automatic: ${q.fieldName}', widget.answers)),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              child: Text(val,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      case QuestionType.information:
        return _buildInformation(q);
      case QuestionType.text:
        return _buildText(q);
      case QuestionType.radio:
        return _buildRadio(q);
      case QuestionType.checkbox:
        return _buildCheckbox(q);
      case QuestionType.combobox:
        return _buildCombobox(q);
      case QuestionType.date:
        return _buildDate(q);
      case QuestionType.datetime:
        return _buildDateTime(q);
    }
  }
}

// Helper widget for RadioGroup if needed, or just use standard Column
// Helper widget for RadioTheme if needed
class AppRadioTheme extends StatelessWidget {
  final Widget child;

  const AppRadioTheme({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return Theme.of(context).primaryColor;
            }
            return Colors.grey.shade600;
          }),
        ),
      ),
      child: child,
    );
  }
}
