// lib/models/question.dart
// import 'package:flutter/material.dart';

enum QuestionType { automatic, text, checkbox, radio, information }

class QuestionOption {
  final String value;
  final String label;
  QuestionOption({required this.value, required this.label});
}

class Question {
  final QuestionType type;
  final String fieldName;
  final String fieldType; // e.g., integer, text, datetime
  final String? text;
  final int? maxCharacters;
  final List<QuestionOption> options;

  Question({
    required this.type,
    required this.fieldName,
    required this.fieldType,
    this.text,
    this.maxCharacters,
    this.options = const [],
  });
}

/// Simple answer store type: for checkboxes, store List<String>, for others String.
typedef AnswerMap = Map<String, dynamic>;

QuestionType parseQuestionType(String raw) {
  switch (raw.toLowerCase()) {
    case 'automatic':
      return QuestionType.automatic;
    case 'text':
      return QuestionType.text;
    case 'checkbox':
      return QuestionType.checkbox;
    case 'radio':
      return QuestionType.radio;
    case 'information':
      return QuestionType.information;
    default:
      return QuestionType.information;
  }
}
