import 'dart:convert';
import 'package:flutter/material.dart';
import 'db_service.dart';
import 'settings_service.dart';

/// A base ID has used up every value its increment suffix can express.
///
/// Distinct from an ordinary generation failure: nothing is wrong with the
/// device or the database, the study has simply outgrown the width its data
/// dictionary declared, and the only fix is a longer `incrementLength`.
class IdCapacityException implements Exception {
  final String message;
  const IdCapacityException(this.message);

  @override
  String toString() => 'IdCapacityException: $message';
}

/// Configuration for generating unique identifiers
class IdConfig {
  final String prefix;
  final List<IdField> fields;
  final int incrementLength;

  IdConfig({
    required this.prefix,
    required this.fields,
    required this.incrementLength,
  });

  factory IdConfig.fromJson(Map<String, dynamic> json) {
    return IdConfig(
      prefix: json['prefix'] as String? ?? '',
      fields: (json['fields'] as List<dynamic>)
          .map((f) => IdField.fromJson(f as Map<String, dynamic>))
          .toList(),
      incrementLength: json['incrementLength'] as int? ?? 3,
    );
  }
}

/// Represents a field in the ID configuration
class IdField {
  final String name;
  final int length;

  IdField({required this.name, required this.length});

  factory IdField.fromJson(Map<String, dynamic> json) {
    return IdField(
      name: json['name'] as String,
      length: json['length'] as int,
    );
  }
}

/// Service for generating unique identifiers based on configuration
class IdGenerator {
  /// Generates a unique ID based on the configuration and current answers
  ///
  /// For example, if config is:
  /// - prefix: "GX"
  /// - fields: [{"name": "tabletnum", "length": 2}]
  /// - incrementLength: 3
  ///
  /// And answers has tabletnum = "57"
  ///
  /// This will generate: GX57001, GX57002, etc.
  ///
  /// [fieldName] is the field the generated ID is stored in (e.g. `subjid`).
  /// The auto-increment counter is derived from that column alone.
  static Future<String> generateId({
    required String surveyId,
    required String tableName,
    required String fieldName,
    required String idConfigJson,
    required Map<String, dynamic> answers,
  }) async {
    try {
      // Parse the ID configuration
      final config = IdConfig.fromJson(json.decode(idConfigJson));

      // Build the base part of the ID from the configured fields
      final StringBuffer baseId = StringBuffer(config.prefix);

      for (final field in config.fields) {
        final value = answers[field.name];
        if (value == null) {
          throw Exception(
              'Required field "${field.name}" not found in answers for ID generation');
        }

        // Convert value to string and pad with leading zeros
        final stringValue = value.toString();
        final paddedValue = stringValue.padLeft(field.length, '0');

        // If the padded value exceeds the configured length, take the last part of the string
        if (paddedValue.length > field.length) {
          baseId
              .write(paddedValue.substring(paddedValue.length - field.length));
        } else {
          baseId.write(paddedValue);
        }
      }

      // Query database to find the next increment number
      final baseIdStr = baseId.toString();

      // Build the complete ID
      String completeId;
      if (config.incrementLength == 0) {
        // No auto-increment suffix - just use the base ID
        completeId = baseIdStr;
      } else {
        // Add auto-increment suffix
        final nextIncrement = await _getNextIncrement(
          surveyId: surveyId,
          tableName: tableName,
          fieldName: fieldName,
          baseId: baseIdStr,
          incrementLength: config.incrementLength,
        );
        completeId =
            '$baseIdStr${nextIncrement.toString().padLeft(config.incrementLength, '0')}';
      }

      debugPrint('Generated ID: $completeId');
      return completeId;
    } catch (e) {
      debugPrint('Error generating ID: $e');
      rethrow;
    }
  }

  /// The largest value the increment suffix can hold, e.g. 999 for length 3.
  @visibleForTesting
  static int maxIncrementFor(int incrementLength) =>
      int.parse('9' * incrementLength);

  /// How many values at the top of the range are reserved as sentinels.
  ///
  /// Ten, except where the range is too small to spare them -- reserving ten
  /// of a two-digit range would take a tenth of the study's capacity. Data
  /// dictionaries deliberately oversize the increment (a 50-interview study
  /// still gets a four-digit range), so ten costs nothing in practice.
  @visibleForTesting
  static int sentinelBandSizeFor(int incrementLength) =>
      maxIncrementFor(incrementLength) >= 100 ? 10 : 1;

  /// The lowest reserved value. Ordinary IDs run from 1 up to this minus one.
  @visibleForTesting
  static int sentinelFloorFor(int incrementLength) =>
      maxIncrementFor(incrementLength) - sentinelBandSizeFor(incrementLength) + 1;

  /// The increment to use when the existing IDs could not be read.
  ///
  /// Counts **down** from the top of the range, driven by [priorFailures] --
  /// a device-local tally, because the one thing we cannot do here is ask the
  /// table which sentinels are already taken. Failing to read that table is
  /// precisely why we are in this method.
  ///
  /// The point is not to avoid a duplicate outright; two devices that both
  /// fail can still land on the same value, and every record carries a
  /// `uniqueid` UUID that keeps such a collision resolvable. The point is that
  /// `GX57999` announces itself, where the old fallback of `1` produced
  /// `GX57001` -- indistinguishable from a legitimate first record, so nobody
  /// ever found out. `WHERE subjid LIKE '%999'` finds every degraded record.
  @visibleForTesting
  static int degradedIncrement({
    required int incrementLength,
    required int priorFailures,
  }) {
    final band = sentinelBandSizeFor(incrementLength);
    return maxIncrementFor(incrementLength) - (priorFailures % band);
  }

  /// Gets the next increment number for a given base ID
  ///
  /// For example, if fieldName = "subjid", baseId = "GX57" and the database has:
  /// - GX57001
  /// - GX57002
  ///
  /// This will return 3 (for GX57003)
  ///
  /// If the existing IDs cannot be read, this returns a sentinel from the top
  /// of the range instead of restarting at 1, and never refuses -- losing an
  /// interview is worse than issuing an ID that has to be reconciled later.
  static Future<int> _getNextIncrement({
    required String surveyId,
    required String tableName,
    required String fieldName,
    required String baseId,
    required int incrementLength,
  }) async {
    // One `SELECT MAX(...)` over just this base ID's own rows, rather than
    // reading the whole table into Dart to find one integer.
    //
    // `null` means the read failed; `0` means the table genuinely holds no
    // record under this base ID, which is an ordinary first-record case. The
    // original code called `getExistingRecords`, which reported both as an
    // empty list -- so a locked or unreadable database silently produced
    // increment 1 and an ID that collided with an already-enrolled subject.
    final maxIncrement = await DbService.tryGetMaxIdIncrement(
      surveyId: surveyId,
      tableName: tableName,
      fieldName: fieldName,
      baseId: baseId,
      incrementLength: incrementLength,
      sentinelFloor: sentinelFloorFor(incrementLength),
    );

    if (maxIncrement == null) {
      final settings = SettingsService();
      final priorFailures = await settings.idFallbackCount;
      await settings.setIdFallbackCount(priorFailures + 1);

      final sentinel = degradedIncrement(
        incrementLength: incrementLength,
        priorFailures: priorFailures,
      );
      debugPrint(
          '[IdGenerator] Could not read existing "$fieldName" values in '
          '"$tableName". Issuing the reserved increment $sentinel for base '
          '"$baseId" so the record is still saved and the ID is identifiable. '
          'Degraded ID count on this device is now ${priorFailures + 1}.');
      return sentinel;
    }

    return nextIncrementAfter(
      maxIncrement: maxIncrement,
      fieldName: fieldName,
      baseId: baseId,
      incrementLength: incrementLength,
    );
  }

  /// The increment to issue given [maxIncrement], the highest already in use
  /// under [baseId].
  ///
  /// Values in the reserved sentinel band are excluded from [maxIncrement] by
  /// the query that produces it (see [DbService.maxIdIncrementIn]), so a
  /// degraded ID cannot poison the counter: with records 001-042 plus a
  /// sentinel 999, the next ID is 043. Without that exclusion one transient
  /// read failure would push `MAX` to 999 and every subsequent record would
  /// hit the capacity check below -- worse than the bug this replaced.
  ///
  /// Throws [IdCapacityException] rather than return a value that would not
  /// fit [incrementLength]. `padLeft` does not truncate, so 1000 in a
  /// three-digit scheme silently produced an eight-character `GX571000`.
  ///
  /// Public so the counter's arithmetic can be verified without a database.
  @visibleForTesting
  static int nextIncrementAfter({
    required int maxIncrement,
    required String fieldName,
    required String baseId,
    required int incrementLength,
  }) {
    final sentinelFloor = sentinelFloorFor(incrementLength);
    final next = maxIncrement + 1;

    if (next >= sentinelFloor) {
      throw IdCapacityException(
          'Base ID "$baseId" has reached the end of its $incrementLength-digit '
          'range: $maxIncrement is the highest in use and $sentinelFloor upward '
          'is reserved. The data dictionary needs a longer incrementLength for '
          '"$fieldName".');
    }
    return next;
  }

  /// Validates that all required fields for ID generation are present in answers
  static bool validateIdFields({
    required String idConfigJson,
    required Map<String, dynamic> answers,
  }) {
    try {
      final config = IdConfig.fromJson(json.decode(idConfigJson));

      for (final field in config.fields) {
        if (!answers.containsKey(field.name) || answers[field.name] == null) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error validating ID fields: $e');
      return false;
    }
  }

  /// Gets the list of field names required for ID generation
  static List<String> getRequiredFields(String idConfigJson) {
    try {
      final config = IdConfig.fromJson(json.decode(idConfigJson));
      return config.fields.map((f) => f.name).toList();
    } catch (e) {
      debugPrint('Error getting required fields: $e');
      return [];
    }
  }

  /// Extracts the base ID (without increment part) from a complete ID
  /// For example: "18122001" with incrementLength=3 returns "18122"
  static String extractBaseId({
    required String completeId,
    required String idConfigJson,
  }) {
    try {
      final config = IdConfig.fromJson(json.decode(idConfigJson));

      if (config.incrementLength == 0) {
        return completeId;
      }

      // The base is everything except the last incrementLength characters
      if (completeId.length > config.incrementLength) {
        return completeId.substring(0, completeId.length - config.incrementLength);
      }

      return completeId;
    } catch (e) {
      debugPrint('Error extracting base ID: $e');
      return completeId;
    }
  }

  /// Builds the expected base ID from current answers
  /// Returns the base part without the increment suffix
  static String buildBaseId({
    required String idConfigJson,
    required Map<String, dynamic> answers,
  }) {
    try {
      final config = IdConfig.fromJson(json.decode(idConfigJson));
      final StringBuffer baseId = StringBuffer(config.prefix);

      for (final field in config.fields) {
        final value = answers[field.name];
        if (value == null) {
          throw Exception(
              'Required field "${field.name}" not found in answers for ID generation');
        }

        final stringValue = value.toString();
        final paddedValue = stringValue.padLeft(field.length, '0');

        if (paddedValue.length > field.length) {
          baseId
              .write(paddedValue.substring(paddedValue.length - field.length));
        } else {
          baseId.write(paddedValue);
        }
      }

      return baseId.toString();
    } catch (e) {
      debugPrint('Error building base ID: $e');
      rethrow;
    }
  }

  /// Checks if the base ID components have changed compared to an existing ID
  /// Returns true if the base parts match (meaning component fields haven't changed)
  static bool hasBaseIdChanged({
    required String existingId,
    required String idConfigJson,
    required Map<String, dynamic> answers,
  }) {
    try {
      final existingBase = extractBaseId(
        completeId: existingId,
        idConfigJson: idConfigJson,
      );
      final currentBase = buildBaseId(
        idConfigJson: idConfigJson,
        answers: answers,
      );

      debugPrint('[IdGenerator] Comparing bases: existing="$existingBase" current="$currentBase"');
      return existingBase != currentBase;
    } catch (e) {
      debugPrint('Error checking base ID change: $e');
      return true; // Assume changed if we can't determine
    }
  }
}
