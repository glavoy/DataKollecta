// lib/widgets/question_views.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../services/auto_fields.dart';
import '../services/csv_data_service.dart';
import '../services/database_response_service.dart';

class QuestionView extends StatefulWidget {
  final Question question;
  final AnswerMap answers; // shared map so we can restore / persist answers
  final VoidCallback? onAnswerChanged;
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
  String? _textError;
  List<QuestionOption> _dynamicOptions = [];

  @override
  void initState() {
    super.initState();

    // Seed state from existing answers if any:
    final q = widget.question;
    final existing = widget.answers[q.fieldName];

    _textFocusNode = FocusNode();
    _textController = TextEditingController(
      text: (existing is String) ? existing : '',
    );

    _checkboxSelection = {
      if (existing is List) ...existing.map((e) => e.toString()),
    };

    // Debug checkbox initialization
    if (q.type == QuestionType.checkbox) {
      debugPrint('Initializing checkbox ${q.fieldName}');
      debugPrint('  existing value from answers[${q.fieldName}]: $existing (type: ${existing.runtimeType})');
      debugPrint('  is List? ${existing is List}');
      debugPrint('  _checkboxSelection after init: $_checkboxSelection');
      debugPrint('  Available options: ${q.options.map((o) => o.value).toList()}');
    }

    _radioSelection = (existing is String) ? existing : null;
    _comboboxSelection = (existing is String) ? existing : null;

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
      // If it is a special response, leave _selectedDate null and keep the string value
    }

    // Centralized automatic variable calculation
    if (q.type == QuestionType.automatic && existing == null) {
      final v = AutoFields.compute(widget.answers, q, isEditMode: widget.isEditMode);
      widget.answers[q.fieldName] = v;
    }
    // Also handle datetime type automatic fields
    if (q.type == QuestionType.datetime && existing == null) {
      final v = AutoFields.compute(widget.answers, q, isEditMode: widget.isEditMode);
      widget.answers[q.fieldName] = v;
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

  Future<void> _loadDynamicOptions() async {
    final config = widget.question.responseConfig;
    if (config == null) return;

    try {
      List<QuestionOption> options = [];

      if (config.source == ResponseSource.csv) {
        options = await widget.csvDataService.getResponseOptions(config, widget.answers);
      } else if (config.source == ResponseSource.database) {
        options = await DatabaseResponseService.getResponseOptions(
          widget.surveyId,
          config,
          widget.answers,
        );
      }

      if (mounted) {
        setState(() {
          _dynamicOptions = options;
        });
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
      _textController.text = (existing is String) ? existing : '';
      // Reset radio/checkbox/combobox selections
      _radioSelection = (existing is String) ? existing : null;
      _comboboxSelection = (existing is String) ? existing : null;
      _checkboxSelection = {
        if (existing is List) ...existing.map((e) => e.toString()),
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
      _textError = null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle('Information'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Text(display, style: const TextStyle(fontSize: 16)),
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
    }
    String? _validateText(String val) {
      if (isIntegerField && val.isNotEmpty) {
        final parsed = int.tryParse(val);
        if (parsed == null) {
          return 'Enter a number';
        }
        final nc = q.numericCheck;
        if (nc != null) {
          final exceptions = (nc.otherValues ?? '')
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet();
          if (!exceptions.contains(parsed.toString())) {
            if (nc.minValue != null && parsed < nc.minValue!) {
              return nc.message ?? 'Value must be >= ${nc.minValue}';
            }
            if (nc.maxValue != null && parsed > nc.maxValue!) {
              return nc.message ?? 'Value must be <= ${nc.maxValue}';
            }
          }
        }
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
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
          decoration: InputDecoration(
            hintText: 'Type your answer',
            errorText: widget.logicError ?? _textError,
          ),
          onChanged: (val) {
            setState(() {
              _textError = _validateText(val);
            });
            widget.answers[q.fieldName] = val;
            widget.onAnswerChanged?.call();
          },
        ),
      ],
    );
  }

  Widget _buildRadio(Question q) {
    // Use dynamic options if available, otherwise use static options
    final options = _dynamicOptions.isNotEmpty ? _dynamicOptions : q.options;

    // Show empty message if no options and config has empty message
    if (options.isEmpty && q.responseConfig?.emptyMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
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
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
        if (widget.logicError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              widget.logicError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        ...options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RadioGroup<String>(
              groupValue: _radioSelection,
              onChanged: (val) {
                setState(() {
                  _radioSelection = val;
                  widget.answers[q.fieldName] = val;
                });
                widget.onAnswerChanged?.call();
              },
              child: RadioListTile<String>(
                value: opt.value,
                title: Text(opt.label),
                dense: true,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(Question q) {
    // Debug: Log checkbox state
    debugPrint('Building checkbox ${q.fieldName}, selection: $_checkboxSelection');

    // Use dynamic options if available, otherwise use static options
    final options = _dynamicOptions.isNotEmpty ? _dynamicOptions : q.options;

    // Show empty message if no options and config has empty message
    if (options.isEmpty && q.responseConfig?.emptyMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
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
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
        if (widget.logicError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              widget.logicError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        Wrap(
          runSpacing: 8,
          children: options.map((opt) {
            final checked = _checkboxSelection.contains(opt.value);
            debugPrint('  Option ${opt.value} (${opt.label}): checked=$checked');
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CheckboxListTile(
                value: checked,
                dense: true,
                title: Text(opt.label),
                controlAffinity: ListTileControlAffinity.leading,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: Colors.white,
                onChanged: (val) {
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
                        if (dontKnowValue != null) _checkboxSelection.remove(dontKnowValue);
                        if (refuseValue != null) _checkboxSelection.remove(refuseValue);
                        if (notInListValue != null) _checkboxSelection.remove(notInListValue);
                        _checkboxSelection.add(opt.value);
                      }
                    } else {
                      // Deselecting is always allowed
                      _checkboxSelection.remove(opt.value);
                    }
                    widget.answers[q.fieldName] = _checkboxSelection.toList();
                  });
                  widget.onAnswerChanged?.call();
                },
              ),
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
          if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
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
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
        if (widget.logicError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, left: 12.0),
            child: Text(
              widget.logicError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
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
            items: options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt.value,
                child: Text(opt.label),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _comboboxSelection = val;
                widget.answers[q.fieldName] = val;
              });
              widget.onAnswerChanged?.call();
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
    final isDontKnow = currentAnswer != null && currentAnswer.isNotEmpty &&
                       q.dontKnow != null && currentAnswer == q.dontKnow;
    final isRefuse = currentAnswer != null && currentAnswer.isNotEmpty &&
                     q.refuse != null && currentAnswer == q.refuse;
    final hasSpecialResponse = isDontKnow || isRefuse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
        InkWell(
          onTap: () async {
            // Calculate date limits
            DateTime firstDate = DateTime(1900);
            DateTime lastDate = DateTime(2100);

            if (q.minDate != null) {
              final calculated = _calculateDate(q.minDate!);
              if (calculated != null) firstDate = calculated;
            }
            
            if (q.maxDate != null) {
              final calculated = _calculateDate(q.maxDate!);
              if (calculated != null) lastDate = calculated;
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
              setState(() {
                _selectedDate = picked;
                // For 'date' type, store as 'YYYY-MM-DD' string
                widget.answers[q.fieldName] = picked.toIso8601String().split('T')[0];
              });
              widget.onAnswerChanged?.call();
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
                    fontWeight: hasSpecialResponse ? FontWeight.w500 : FontWeight.normal,
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
                        setState(() {
                          _selectedDate = null;
                          widget.answers[q.fieldName] = q.dontKnow;
                        });
                        widget.onAnswerChanged?.call();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: isDontKnow ? Colors.orange.shade50 : null,
                        side: BorderSide(
                          color: isDontKnow ? Colors.orange.shade700 : Colors.grey.shade400,
                          width: isDontKnow ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Don't know",
                        style: TextStyle(
                          color: isDontKnow ? Colors.orange.shade700 : Colors.grey.shade700,
                          fontWeight: isDontKnow ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                if (q.dontKnow != null && q.refuse != null) const SizedBox(width: 12),
                if (q.refuse != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedDate = null;
                          widget.answers[q.fieldName] = q.refuse;
                        });
                        widget.onAnswerChanged?.call();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: isRefuse ? Colors.orange.shade50 : null,
                        side: BorderSide(
                          color: isRefuse ? Colors.orange.shade700 : Colors.grey.shade400,
                          width: isRefuse ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Refuse',
                        style: TextStyle(
                          color: isRefuse ? Colors.orange.shade700 : Colors.grey.shade700,
                          fontWeight: isRefuse ? FontWeight.w600 : FontWeight.normal,
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
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text!, widget.answers)),
        InkWell(
          onTap: () async {
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
                setState(() {
                  _selectedDateTime = combined;
                  widget.answers[q.fieldName] = combined;
                });
                widget.onAnswerChanged?.call();
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

  /// Calculate a date from a relative string like "-1y", "+30d"
  DateTime? _calculateDate(String offset) {
    if (offset.isEmpty) return null;
    
    final now = DateTime.now();
    // Remove any whitespace
    final clean = offset.trim();
    
    if (clean.length < 3) return null; // Need at least sign, number, unit
    
    final sign = clean.substring(0, 1);
    final unit = clean.substring(clean.length - 1).toLowerCase();
    final numberStr = clean.substring(1, clean.length - 1);
    final number = int.tryParse(numberStr);
    
    if (number == null) return null;
    
    final multiplier = sign == '-' ? -1 : 1;
    final amount = number * multiplier;
    
    switch (unit) {
      case 'd':
        return now.add(Duration(days: amount));
      case 'w':
        return now.add(Duration(days: amount * 7));
      case 'm':
        // Approximate month calculation
        return DateTime(now.year, now.month + amount, now.day);
      case 'y':
        return DateTime(now.year + amount, now.month, now.day);
      default:
        return null;
    }
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
            _buildSectionTitle(SurveyLoader.expandPlaceholders(q.text ?? 'Automatic: ${q.fieldName}', widget.answers)),
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
