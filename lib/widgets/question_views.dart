// lib/widgets/question_views.dart
import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/survey_loader.dart';
import '../services/auto_fields.dart';

class QuestionView extends StatefulWidget {
  final Question question;
  final AnswerMap answers; // shared map so we can restore / persist answers

  const QuestionView({
    super.key,
    required this.question,
    required this.answers,
  });

  @override
  State<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<QuestionView> {
  late TextEditingController _textController;
  late Set<String> _checkboxSelection;
  String? _radioSelection;

  @override
  void initState() {
    super.initState();

    // Seed state from existing answers if any:
    final q = widget.question;
    final existing = widget.answers[q.fieldName];

    _textController = TextEditingController(
      text: (existing is String) ? existing : '',
    );

    _checkboxSelection = {
      if (existing is List) ...existing.map((e) => e.toString()),
    };

    _radioSelection = (existing is String) ? existing : null;

    // Centralized automatic variable calculation
    if (q.type == QuestionType.automatic && existing == null) {
      final v = AutoFields.compute(widget.answers, q);
      widget.answers[q.fieldName] = v;
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
      // Reset radio/checkbox selections
      _radioSelection = (existing is String) ? existing : null;
      _checkboxSelection = {
        if (existing is List) ...existing.map((e) => e.toString()),
      };
      setState(() {}); // ensure rebuild
    }
  }

  @override
  void dispose() {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
        TextField(
          controller: _textController,
          maxLength: q.maxCharacters,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Type your answer…',
          ),
          onChanged: (val) {
            widget.answers[q.fieldName] = val;
            AutoFields.touchLastMod(widget.answers);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((q.text ?? '').isNotEmpty) _buildSectionTitle(q.text!),
        Wrap(
          runSpacing: 8,
          children: q.options.map((opt) {
            final checked = _checkboxSelection.contains(opt.value);
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
                },
              ),
            );
          }).toList(),
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
    }
  }
}
