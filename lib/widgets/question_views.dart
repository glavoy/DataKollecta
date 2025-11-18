// lib/widgets/question_views.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../services/auto_fields.dart';

class QuestionView extends StatefulWidget {
  final Question question;
  final AnswerMap answers; // shared map so we can restore / persist answers
  final void Function(String)? onAnswerChanged;
  final VoidCallback? onRequestNext; // ask parent to navigate to next question
  final bool isEditMode; // Whether we're editing an existing record

  const QuestionView({
    super.key,
    required this.question,
    required this.answers,
    this.onAnswerChanged,
    this.onRequestNext,
    this.isEditMode = false,
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
      try {
        final parsed = DateTime.parse(existing);
        _selectedDate = parsed;
        _selectedDateTime = parsed;
      } catch (_) {
        // Not a valid date string
      }
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
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
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
            errorText: _textError,
          ),
          onChanged: (val) {
            setState(() {
              _textError = _validateText(val);
            });
            widget.answers[q.fieldName] = val;
            AutoFields.touchLastMod(widget.answers);
            widget.onAnswerChanged?.call(q.fieldName);
          },
        ),
      ],
    );
  }

  Widget _buildRadio(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
        ...q.options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RadioGroup<String>(
              groupValue: _radioSelection,
              onChanged: (val) {
                setState(() {
                  _radioSelection = val;
                  widget.answers[q.fieldName] = val;
                  AutoFields.touchLastMod(widget.answers);
                });
                widget.onAnswerChanged?.call(q.fieldName);
                // Auto-advance on selection
                if (val != null && val.isNotEmpty) {
                  widget.onRequestNext?.call();
                }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
        Wrap(
          runSpacing: 8,
          children: q.options.map((opt) {
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
                    if (val == true) {
                      _checkboxSelection.add(opt.value);
                    } else {
                      _checkboxSelection.remove(opt.value);
                    }
                    widget.answers[q.fieldName] = _checkboxSelection.toList();
                    AutoFields.touchLastMod(widget.answers);
                  });
                  widget.onAnswerChanged?.call(q.fieldName);
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCombobox(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
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
            items: q.options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt.value,
                child: Text(opt.label),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _comboboxSelection = val;
                widget.answers[q.fieldName] = val;
                AutoFields.touchLastMod(widget.answers);
              });
              widget.onAnswerChanged?.call(q.fieldName);
              // Auto-advance on selection
              if (val != null && val.isNotEmpty) {
                widget.onRequestNext?.call();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDate(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() {
                _selectedDate = picked;
                widget.answers[q.fieldName] = picked;
                AutoFields.touchLastMod(widget.answers);
              });
              widget.onAnswerChanged?.call(q.fieldName);
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
                  _selectedDate != null
                      ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                      : 'Select a date',
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDate != null ? Colors.black : Colors.grey,
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

  Widget _buildDateTime(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
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
                  AutoFields.touchLastMod(widget.answers);
                });
                widget.onAnswerChanged?.call(q.fieldName);
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
            _buildSectionTitle(q.text ?? 'Automatic: ${q.fieldName}'),
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
