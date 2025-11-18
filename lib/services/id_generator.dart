import 'dart:convert';
import 'package:flutter/material.dart';
import 'db_service.dart';

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
  static Future<String> generateId({
    required String tableName,
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
          baseId.write(paddedValue.substring(paddedValue.length - field.length));
        } else {
          baseId.write(paddedValue);
        }
      }

      // Query database to find the next increment number
      final baseIdStr = baseId.toString();
      final nextIncrement = await _getNextIncrement(
        tableName: tableName,
        baseId: baseIdStr,
        incrementLength: config.incrementLength,
      );

      // Build the complete ID
      final completeId =
          '$baseIdStr${nextIncrement.toString().padLeft(config.incrementLength, '0')}';

      debugPrint('Generated ID: $completeId');
      return completeId;
    } catch (e) {
      debugPrint('Error generating ID: $e');
      rethrow;
    }
  }

  /// Gets the next increment number for a given base ID
  ///
  /// For example, if baseId = "GX57" and the database has:
  /// - GX57001
  /// - GX57002
  ///
  /// This will return 3 (for GX57003)
  static Future<int> _getNextIncrement({
    required String tableName,
    required String baseId,
    required int incrementLength,
  }) async {
    try {
      // Get all records from the table
      final records = await DbService.getExistingRecords(tableName);

      // Find the maximum increment number for this base ID
      int maxIncrement = 0;

      for (final record in records) {
        // Assuming the unique ID is stored in a field called 'subjid' or similar
        // We need to check all fields to find the one that matches our pattern
        for (final entry in record.entries) {
          final value = entry.value?.toString();
          if (value != null && value.startsWith(baseId)) {
            // Extract the increment part
            final incrementPart = value.substring(baseId.length);
            if (incrementPart.length == incrementLength) {
              final increment = int.tryParse(incrementPart);
              if (increment != null && increment > maxIncrement) {
                maxIncrement = increment;
              }
            }
          }
        }
      }

      return maxIncrement + 1;
    } catch (e) {
      debugPrint('Error getting next increment: $e');
      // If there's an error, start from 1
      return 1;
    }
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
}
