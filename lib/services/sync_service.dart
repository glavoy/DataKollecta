import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'db_service.dart';
import 'settings_service.dart';

/// Result of a sync operation
class SyncResult {
  final int syncedCount;
  final int failedCount;
  final List<String> syncedUuids;
  final List<String> formchangesSyncedUuids;
  final List<SyncError> errors;

  SyncResult({
    required this.syncedCount,
    required this.failedCount,
    required this.syncedUuids,
    required this.formchangesSyncedUuids,
    required this.errors,
  });

  bool get hasErrors => failedCount > 0;
  bool get isSuccess => failedCount == 0 && syncedCount > 0;
}

/// Error details for a failed sync
class SyncError {
  final String uuid;
  final String message;

  SyncError({required this.uuid, required this.message});
}

/// Progress callback for sync operations
typedef SyncProgressCallback = void Function(
  String tableName,
  int current,
  int total,
  String status,
);

/// Service for uploading data to the Supabase backend
class SyncService {
  static const String _syncEndpoint =
      'https://qetzeqyuuiposzseqwvb.supabase.co/functions/v1/app-sync';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFldHplcXl1dWlwb3N6c2Vxd3ZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMzYyODYsImV4cCI6MjA4MjcxMjI4Nn0.RqIPiYMUr46tJhgPTgwPwWWbAPymr_VGszuMsHbCTmE';

  static const int _batchSize = 10;

  final _settingsService = SettingsService();

  /// Get count of unsynced records for a table
  Future<int> getUnsyncedCount(String surveyId, String tableName) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE synced_at IS NULL',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('[SyncService] Error getting unsynced count: $e');
      return 0;
    }
  }

  /// Get count of unsynced formchanges
  Future<int> getUnsyncedFormchangesCount(String surveyId) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM formchanges WHERE synced_at IS NULL',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('[SyncService] Error getting unsynced formchanges count: $e');
      return 0;
    }
  }

  /// Get total count of all unsynced records across all CRF tables
  Future<Map<String, int>> getAllUnsyncedCounts(String surveyId) async {
    final counts = <String, int>{};

    try {
      // Get list of CRF tables
      final db = await DbService.getDatabaseForQueries(surveyId);
      final crfsResult = await db.query('crfs', columns: ['tablename']);

      for (final row in crfsResult) {
        final tableName = row['tablename'] as String?;
        if (tableName != null) {
          counts[tableName] = await getUnsyncedCount(surveyId, tableName);
        }
      }

      // Add formchanges count
      counts['formchanges'] = await getUnsyncedFormchangesCount(surveyId);
    } catch (e) {
      debugPrint('[SyncService] Error getting all unsynced counts: $e');
    }

    return counts;
  }

  /// Get unsynced records from a table (limited by batch size)
  Future<List<Map<String, dynamic>>> _getUnsyncedRecords(
    String surveyId,
    String tableName,
    int limit,
  ) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final results = await db.query(
        tableName,
        where: 'synced_at IS NULL',
        limit: limit,
      );
      return results;
    } catch (e) {
      debugPrint('[SyncService] Error getting unsynced records: $e');
      return [];
    }
  }

  /// Get unsynced formchanges (limited by batch size)
  Future<List<Map<String, dynamic>>> _getUnsyncedFormchanges(
    String surveyId,
    int limit,
  ) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final results = await db.query(
        'formchanges',
        where: 'synced_at IS NULL',
        limit: limit,
      );
      return results;
    } catch (e) {
      debugPrint('[SyncService] Error getting unsynced formchanges: $e');
      return [];
    }
  }

  /// Mark records as synced
  Future<void> _markAsSynced(
    String surveyId,
    String tableName,
    List<String> uuids,
    String syncedAt,
  ) async {
    if (uuids.isEmpty) return;

    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final placeholders = List.filled(uuids.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE $tableName SET synced_at = ? WHERE uuid IN ($placeholders)',
        [syncedAt, ...uuids],
      );
      debugPrint(
          '[SyncService] Marked ${uuids.length} records as synced in $tableName');
    } catch (e) {
      debugPrint('[SyncService] Error marking records as synced: $e');
    }
  }

  /// Mark formchanges as synced
  Future<void> _markFormchangesAsSynced(
    String surveyId,
    List<String> uuids,
    String syncedAt,
  ) async {
    if (uuids.isEmpty) return;

    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final placeholders = List.filled(uuids.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE formchanges SET synced_at = ? WHERE formchanges_uuid IN ($placeholders)',
        [syncedAt, ...uuids],
      );
      debugPrint('[SyncService] Marked ${uuids.length} formchanges as synced');
    } catch (e) {
      debugPrint('[SyncService] Error marking formchanges as synced: $e');
    }
  }

  /// Upload a batch of records to the server
  Future<SyncResult> _uploadBatch({
    required String token,
    required List<Map<String, dynamic>> submissions,
    required List<Map<String, dynamic>> formchanges,
    required String deviceId,
  }) async {
    try {
      // Build payload
      final payload = <String, dynamic>{
        'token': token,
        'submissions': submissions.map((record) {
          return {
            // Note: survey_package_id is looked up by server from data.survey_id
            'table_name': record['_table_name'], // We add this when preparing
            'local_uuid': record['uuid'],
            'data': Map<String, dynamic>.from(record)
              ..remove('_table_name')
              ..remove('synced_at'), // Don't send synced_at to server
            'collected_at': record['stoptime'] ?? record['lastmod'],
            'swver': record['swver'],
            'device_id': deviceId,
          };
        }).toList(),
      };

      // Only add formchanges if there are any
      if (formchanges.isNotEmpty) {
        payload['formchanges'] = formchanges.map((fc) {
          return {
            'formchanges_uuid': fc['formchanges_uuid'],
            'record_uuid': fc['record_uuid'],
            'tablename': fc['tablename'],
            'fieldname': fc['fieldname'],
            'oldvalue': fc['oldvalue'],
            'newvalue': fc['newvalue'],
            'surveyor_id': fc['surveyor_id'],
            'changed_at': fc['changed_at'],
          };
        }).toList();
      }

      debugPrint(
          '[SyncService] Sending batch: ${submissions.length} submissions, ${formchanges.length} formchanges');
      debugPrint('[SyncService] Payload: ${json.encode(payload)}');

      final response = await http.post(
        Uri.parse(_syncEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_supabaseAnonKey',
        },
        body: json.encode(payload),
      );

      debugPrint('[SyncService] Response status: ${response.statusCode}');
      debugPrint('[SyncService] Response body: ${response.body}');

      if (response.statusCode == 401) {
        throw Exception('Session expired. Please log in again.');
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Upload failed: ${response.statusCode} - ${response.body}');
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;

      // Parse response
      final syncedUuids = (responseData['synced'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final formchangesSyncedUuids =
          (responseData['formchanges_synced'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
      final failedList = responseData['failed'] as List<dynamic>? ?? [];

      final errors = failedList.map((f) {
        final map = f as Map<String, dynamic>;
        return SyncError(
          uuid: map['id']?.toString() ?? 'unknown',
          message: map['error']?.toString() ?? 'Unknown error',
        );
      }).toList();

      return SyncResult(
        syncedCount: syncedUuids.length + formchangesSyncedUuids.length,
        failedCount: errors.length,
        syncedUuids: syncedUuids,
        formchangesSyncedUuids: formchangesSyncedUuids,
        errors: errors,
      );
    } catch (e) {
      debugPrint('[SyncService] Upload error: $e');
      return SyncResult(
        syncedCount: 0,
        failedCount: submissions.length + formchanges.length,
        syncedUuids: [],
        formchangesSyncedUuids: [],
        errors: [SyncError(uuid: 'batch', message: e.toString())],
      );
    }
  }

  /// Main upload method - uploads all unsynced data
  Future<SyncResult> uploadAllData({
    required String surveyId,
    required String deviceId,
    SyncProgressCallback? onProgress,
  }) async {
    // Get auth token
    final token = await _settingsService.authToken;
    if (token == null || token.isEmpty) {
      return SyncResult(
        syncedCount: 0,
        failedCount: 0,
        syncedUuids: [],
        formchangesSyncedUuids: [],
        errors: [
          SyncError(
              uuid: 'auth',
              message:
                  'No authentication token. Please connect to server first.')
        ],
      );
    }

    // Note: survey_package_id is looked up by the server based on survey_id in the data
    // We don't need to pass it explicitly from the mobile app

    int totalSynced = 0;
    int totalFailed = 0;
    final allSyncedUuids = <String>[];
    final allFormchangesSyncedUuids = <String>[];
    final allErrors = <SyncError>[];

    try {
      // Get list of CRF tables
      final db = await DbService.getDatabaseForQueries(surveyId);
      final crfsResult = await db.query('crfs',
          columns: ['tablename'], orderBy: 'display_order');
      final tableNames =
          crfsResult.map((r) => r['tablename'] as String).toList();

      // First, get all formchanges to include with first batch
      var unsyncedFormchanges =
          await _getUnsyncedFormchanges(surveyId, _batchSize * 10);
      var formchangesIncluded = false;

      // Process each table
      for (final tableName in tableNames) {
        onProgress?.call(tableName, 0, 0, 'Checking for unsynced records...');

        var hasMore = true;
        var batchNumber = 0;

        while (hasMore) {
          // Get batch of unsynced records
          final records =
              await _getUnsyncedRecords(surveyId, tableName, _batchSize);
          if (records.isEmpty) {
            hasMore = false;
            continue;
          }

          batchNumber++;
          onProgress?.call(tableName, batchNumber, -1,
              'Uploading batch $batchNumber (${records.length} records)...');

          // Add table name to each record for the payload
          final recordsWithTable = records.map((r) {
            return Map<String, dynamic>.from(r)..['_table_name'] = tableName;
          }).toList();

          // Include formchanges with first batch only
          final formchangesToSend = formchangesIncluded
              ? <Map<String, dynamic>>[]
              : unsyncedFormchanges;
          formchangesIncluded = true;

          // Upload batch
          final result = await _uploadBatch(
            token: token,
            submissions: recordsWithTable,
            formchanges: formchangesToSend,
            deviceId: deviceId,
          );

          // Update local state based on response
          final syncedAt = DateTime.now().toIso8601String();

          if (result.syncedUuids.isNotEmpty) {
            await _markAsSynced(
                surveyId, tableName, result.syncedUuids, syncedAt);
            allSyncedUuids.addAll(result.syncedUuids);
          }

          if (result.formchangesSyncedUuids.isNotEmpty) {
            await _markFormchangesAsSynced(
                surveyId, result.formchangesSyncedUuids, syncedAt);
            allFormchangesSyncedUuids.addAll(result.formchangesSyncedUuids);
          }

          totalSynced += result.syncedCount;
          totalFailed += result.failedCount;
          allErrors.addAll(result.errors);

          // If we got fewer than batch size, we're done with this table
          if (records.length < _batchSize) {
            hasMore = false;
          }

          // Small delay between batches to avoid overwhelming the server
          await Future.delayed(const Duration(milliseconds: 100));
        }

        onProgress?.call(tableName, 0, 0, 'Complete');
      }

      // If we still have formchanges to send (in case no submissions were sent)
      if (!formchangesIncluded && unsyncedFormchanges.isNotEmpty) {
        onProgress?.call('formchanges', 0, 0, 'Uploading form changes...');

        final result = await _uploadBatch(
          token: token,
          submissions: [],
          formchanges: unsyncedFormchanges,
          deviceId: deviceId,
        );

        final syncedAt = DateTime.now().toIso8601String();
        if (result.formchangesSyncedUuids.isNotEmpty) {
          await _markFormchangesAsSynced(
              surveyId, result.formchangesSyncedUuids, syncedAt);
          allFormchangesSyncedUuids.addAll(result.formchangesSyncedUuids);
        }

        totalSynced += result.syncedCount;
        totalFailed += result.failedCount;
        allErrors.addAll(result.errors);
      }

      onProgress?.call('', 0, 0, 'Upload complete');
    } catch (e) {
      debugPrint('[SyncService] Upload all data error: $e');
      allErrors.add(SyncError(uuid: 'general', message: e.toString()));
    }

    return SyncResult(
      syncedCount: totalSynced,
      failedCount: totalFailed,
      syncedUuids: allSyncedUuids,
      formchangesSyncedUuids: allFormchangesSyncedUuids,
      errors: allErrors,
    );
  }
}
