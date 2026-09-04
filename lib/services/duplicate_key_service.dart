import 'package:flutter/foundation.dart';

import '../models/question.dart';
import 'db_service.dart';

/// Whether the primary key an interviewer is building already exists.
///
/// Pulled out of `SurveyScreen` so it can be tested. The screen keeps the
/// dialog; this owns the snapshot and the comparison, both of which are pure
/// once the snapshot is loaded.
///
/// **New records only.** An existing record's own key is in the snapshot, so
/// checking one against it would always report a duplicate of itself. The
/// caller loads no snapshot at all in edit mode, and [isDuplicate] refuses to
/// answer without one.
class DuplicateKeySnapshot {
  /// The lowercased `crfs.primarykey` fields, in the order they compose the key.
  final List<String> keyFields;

  /// One `|`-joined signature per record already in the table.
  final Set<String> existingKeys;

  const DuplicateKeySnapshot({
    required this.keyFields,
    required this.existingKeys,
  });

  static const DuplicateKeySnapshot empty =
      DuplicateKeySnapshot(keyFields: [], existingKeys: {});

  /// Reads every existing primary key for [tableName].
  ///
  /// Both sides of the later comparison are built the same way, from this same
  /// lowercased field list, so a case difference between the worksheet and the
  /// XML cannot make them disagree. Loading once per screen is enough: the
  /// auto-repeat loop pushes a fresh `SurveyScreen` per child, so each child
  /// sees its siblings.
  static Future<DuplicateKeySnapshot> load({
    required String surveyId,
    required String tableName,
  }) async {
    final keyFields = await DbService.getPrimaryKeyFields(surveyId, tableName);
    if (keyFields.isEmpty) return empty;

    final allKeys =
        await DbService.getAllPrimaryKeys(surveyId, tableName, keyFields);

    final existingKeys = allKeys
        .map((row) => keyFields.map((f) => row[f]?.toString() ?? '').join('|'))
        .toSet();

    debugPrint(
        'Loaded ${existingKeys.length} existing primary keys for duplicate check');

    return DuplicateKeySnapshot(
      keyFields: keyFields,
      existingKeys: existingKeys,
    );
  }

  /// Whether [fieldName] is one of the fields that compose the key.
  ///
  /// Case-insensitive, because `keyFields` are lowercased `crfs` values while a
  /// question's `fieldName` carries the XML's own case.
  bool isKeyField(String fieldName) =>
      keyFields.contains(fieldName.toLowerCase());

  /// Whether the key now in [answers] already exists in the table.
  ///
  /// Kept separate from any one question's change handler, because that only
  /// runs for the question the interviewer is *on* -- so a primary key made
  /// entirely of `automatic` fields could never trigger it. In PRISM CSS both
  /// halves of `(hhid, linenum)` are `type='automatic'` with no
  /// `<calculation>`, so neither ever renders and this check had never once
  /// fired for that survey until it was also called where the key is computed.
  bool isDuplicate(AnswerMap answers) {
    if (keyFields.isEmpty || existingKeys.isEmpty) return false;

    final values = <String>[];
    for (final keyField in keyFields) {
      final value = answerFor(answers, keyField)?.toString() ?? '';
      // A partial key cannot be compared -- every record would collide on the
      // same half-empty signature.
      if (value.isEmpty) return false;
      values.add(value);
    }

    return existingKeys.contains(values.join('|'));
  }

  /// Reads an answer by field name, ignoring case.
  ///
  /// The key fields are lowercased `crfs` values while an answer map is keyed
  /// by the XML's own fieldname, so the two only line up when the dictionary
  /// happens to agree with itself about case.
  static dynamic answerFor(AnswerMap answers, String fieldName) {
    if (answers.containsKey(fieldName)) return answers[fieldName];
    final target = fieldName.toLowerCase();
    for (final entry in answers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }
}
