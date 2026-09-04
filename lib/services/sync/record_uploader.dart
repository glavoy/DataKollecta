import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'api_client.dart';
import 'sync_backend.dart';

/// A not-yet-synced row read from SQLite, carrying its `rowid` (for the
/// cursor) and the wire id ([wireId] -- `uniqueid` for a CRF table,
/// `changeuniqueid` for formchanges) alongside its column data.
class UploadRow {
  final int rowId;
  final String wireId;
  final Map<String, dynamic> data;

  const UploadRow({required this.rowId, required this.wireId, required this.data});
}

/// What one batch's HTTP call reported, in wire-id terms -- translated back
/// to `rowid`s by [RecordUploader.upload] before marking rows synced.
class BatchResult {
  final List<String> syncedWireIds;
  final List<ApiSyncFailure> failed;

  const BatchResult({required this.syncedWireIds, required this.failed});
}

class UploadFailure {
  final String sourceName;
  final String id;
  final String error;

  const UploadFailure(
      {required this.sourceName, required this.id, required this.error});
}

/// Why an upload run ended before every unsynced row was attempted. Kept as
/// an enum rather than an exception message so a caller can exhaustively
/// switch into a user-facing string instead of sniffing text the
/// DataKollecta reference branch's UI did (`message.contains('404')`).
enum UploadStopReason { none, sessionExpired, tooManyFailures, throttled }

class UploadOutcome {
  final int syncedCount;
  final List<UploadFailure> failures;
  final UploadStopReason stopReason;

  const UploadOutcome({
    required this.syncedCount,
    required this.failures,
    required this.stopReason,
  });

  bool get stoppedEarly => stopReason != UploadStopReason.none;
  int get failedCount => failures.length;
}

/// Uploads unsynced records in batches, with a termination guarantee that
/// the DataKollecta reference branch's sync_service.dart lacked (defect
/// #4): there, `_getUnsyncedRecords` always re-queried the same
/// `WHERE synced_at IS NULL LIMIT 10`, so a batch that failed -- and so was
/// never marked synced -- was re-fetched and re-sent forever, an infinite
/// "Uploading..." spinner over the same 10 rows.
///
/// Three independent mechanisms fix that here: [upload]'s cursor is
/// strictly monotonic (it advances past a batch whether or not that batch
/// succeeded), a run stops after [maxConsecutiveFailures] consecutive
/// failed batches, and a run stops immediately on [SyncAuthException].
class RecordUploader {
  /// How many records go in one HTTP request.
  ///
  /// 25 is where HTTP overhead stops dominating while the payload -- each
  /// submission carries a whole form's answers as JSON -- is still comfortable
  /// on a poor link. Tune it here and rebuild rather than exposing it: the
  /// right number is a property of the connections the field actually sees,
  /// which is something to learn from watching uploads, not something an
  /// interviewer should be asked about.
  ///
  /// app-sync refuses more than 500 rows in one array with a 413, which
  /// [upload] would read as an ordinary transfer failure and retry three times
  /// before stopping the run. Any value set here must stay well under that.
  static const int defaultBatchSize = 25;
  static const int defaultMaxConsecutiveFailures = 3;

  final ApiClient apiClient;
  final int batchSize;
  final int maxConsecutiveFailures;

  RecordUploader({
    ApiClient? apiClient,
    this.batchSize = defaultBatchSize,
    this.maxConsecutiveFailures = defaultMaxConsecutiveFailures,
  }) : apiClient = apiClient ?? ApiClient();

  /// The core loop, free of SQLite/HTTP specifics so it can be tested with
  /// fake data sources: no real database, no real network, and -- the
  /// property that actually matters -- a source that fails every batch
  /// must still make [upload] return within a bounded number of calls to
  /// [send], not hang.
  Future<UploadOutcome> upload({
    required String sourceName,
    required Future<List<UploadRow>> Function(int afterRowId, int limit)
        fetchBatch,
    required Future<void> Function(List<int> rowIds) markSynced,
    required Future<BatchResult> Function(List<UploadRow> batch) send,
  }) async {
    var cursor = 0;
    var syncedCount = 0;
    var consecutiveFailures = 0;
    final failures = <UploadFailure>[];

    while (true) {
      final batch = await fetchBatch(cursor, batchSize);
      if (batch.isEmpty) break;

      // Advances no matter what happens below -- this is the guarantee
      // that a failing batch cannot be re-fetched forever.
      cursor = batch.map((r) => r.rowId).reduce((a, b) => a > b ? a : b);

      BatchResult result;
      try {
        result = await send(batch);
      } on SyncAuthException {
        return UploadOutcome(
          syncedCount: syncedCount,
          failures: failures,
          stopReason: UploadStopReason.sessionExpired,
        );
      } on SyncThrottledException {
        // Deliberately before the general SyncException branch, and a stop
        // rather than a counted failure: the server has asked us to slow
        // down, so burning the remaining retries against it is the one
        // response guaranteed to make things worse.
        return UploadOutcome(
          syncedCount: syncedCount,
          failures: failures,
          stopReason: UploadStopReason.throttled,
        );
      } on SyncException catch (e) {
        consecutiveFailures++;
        failures.addAll(batch.map((r) =>
            UploadFailure(sourceName: sourceName, id: r.wireId, error: e.message)));
        if (consecutiveFailures >= maxConsecutiveFailures) {
          return UploadOutcome(
            syncedCount: syncedCount,
            failures: failures,
            stopReason: UploadStopReason.tooManyFailures,
          );
        }
        continue;
      }

      if (result.syncedWireIds.isNotEmpty) {
        // A wireId can legitimately map to more than one rowId here: a
        // duplicate-uniqueid row (the historical double-tap-save bug, see
        // DbService.collapseDuplicateUniqueIds) means two on-device rows
        // share one uniqueid, and editing either sets synced_at = null on
        // both, sweeping both into the same batch. Grouping (rather than a
        // wireId -> single-rowId map, which would silently drop all but the
        // last row sharing a wireId) ensures every duplicate gets marked
        // synced together, not just one of them forever re-swept in.
        final rowIdsByWireId = <String, List<int>>{};
        for (final r in batch) {
          rowIdsByWireId.putIfAbsent(r.wireId, () => []).add(r.rowId);
        }
        // Dedupe wireIds before expanding: a duplicate-uniqueid pair sends
        // two submissions sharing one wireId, so the server can (and does,
        // per app-sync's per-submission loop) echo that wireId back twice in
        // syncedWireIds -- expanding per occurrence would double-count and
        // double-pass the same rowIds to markSynced/syncedCount.
        final syncedRowIds = [
          for (final id in result.syncedWireIds.toSet()) ...?rowIdsByWireId[id]
        ];
        if (syncedRowIds.isNotEmpty) await markSynced(syncedRowIds);
        syncedCount += syncedRowIds.length;
      }
      failures.addAll(result.failed.map((f) =>
          UploadFailure(sourceName: sourceName, id: f.id, error: f.error)));

      consecutiveFailures = result.syncedWireIds.isEmpty ? consecutiveFailures + 1 : 0;
      if (consecutiveFailures >= maxConsecutiveFailures) {
        return UploadOutcome(
          syncedCount: syncedCount,
          failures: failures,
          stopReason: UploadStopReason.tooManyFailures,
        );
      }
    }

    return UploadOutcome(
      syncedCount: syncedCount,
      failures: failures,
      stopReason: UploadStopReason.none,
    );
  }

  /// Uploads every unsynced row across every CRF table, then formchanges,
  /// for one survey's database. Stops the whole run immediately if any
  /// stage hits [UploadStopReason.sessionExpired]; a table hitting
  /// [UploadStopReason.tooManyFailures] does not block the remaining
  /// tables, since that usually means something specific to that table's
  /// data rather than the server being unreachable.
  Future<UploadOutcome> uploadSurvey({
    required Database db,
    required String token,
    required String deviceId,
  }) async {
    final tableRows = await db.query('crfs', columns: ['tablename']);
    final tableNames = tableRows
        .map((r) => r['tablename'] as String?)
        .whereType<String>()
        .toSet();

    var syncedCount = 0;
    final failures = <UploadFailure>[];

    for (final tableName in tableNames) {
      final outcome = await upload(
        sourceName: tableName,
        fetchBatch: (afterRowId, limit) =>
            _fetchTableBatch(db, tableName, afterRowId, limit),
        markSynced: (rowIds) => _markTableSynced(db, tableName, rowIds),
        send: (batch) => _sendSubmissions(tableName, deviceId, token, batch),
      );
      syncedCount += outcome.syncedCount;
      failures.addAll(outcome.failures);
      if (outcome.stopReason == UploadStopReason.sessionExpired) {
        return UploadOutcome(
          syncedCount: syncedCount,
          failures: failures,
          stopReason: UploadStopReason.sessionExpired,
        );
      }
    }

    final formchangesOutcome = await upload(
      sourceName: 'formchanges',
      fetchBatch: (afterRowId, limit) =>
          _fetchFormchangesBatch(db, afterRowId, limit),
      markSynced: (rowIds) => _markFormchangesSynced(db, rowIds),
      send: (batch) => _sendFormchanges(token, batch),
    );
    syncedCount += formchangesOutcome.syncedCount;
    failures.addAll(formchangesOutcome.failures);

    final stopReason = formchangesOutcome.stopReason;
    return UploadOutcome(
        syncedCount: syncedCount, failures: failures, stopReason: stopReason);
  }

  Future<List<UploadRow>> _fetchTableBatch(
      Database db, String tableName, int afterRowId, int limit) async {
    final rows = await db.rawQuery(
      // Aliased, not bare `rowid` -- a table declaring its own
      // `INTEGER PRIMARY KEY` (formchanges does: `changeid`) makes SQLite
      // report the bare rowid column's *name* as that underlying column,
      // not "rowid", so it collides with the identical column `*` already
      // expands. sqflite turns duplicate-named columns into one Map key,
      // last write wins, silently discarding the intended rowid --
      // exactly the "every row is malformed" failure this alias prevents.
      'SELECT rowid AS uploader_rowid, * FROM $tableName '
      'WHERE synced_at IS NULL AND rowid > ? ORDER BY rowid LIMIT ?',
      [afterRowId, limit],
    );
    final result = <UploadRow>[];
    for (final row in rows) {
      final data = Map<String, dynamic>.from(row);
      final rowId = data.remove('uploader_rowid');
      final wireId = data['uniqueid'];
      // Defensive, not expected: every row here came straight out of a
      // rowid table's own rowid pseudo-column, which SQLite never leaves
      // null. But a cast failure here used to abort the *entire* upload
      // (every table, every pending record) instead of just this row --
      // skip and log instead, so one unexpected row can't block everything
      // else that's otherwise ready to sync.
      if (rowId is! int || wireId is! String) {
        debugPrint(
            '[RecordUploader] Skipping malformed $tableName row: rowid=$rowId, uniqueid=$wireId');
        continue;
      }
      result.add(UploadRow(rowId: rowId, wireId: wireId, data: data));
    }
    return result;
  }

  Future<void> _markTableSynced(
      Database db, String tableName, List<int> rowIds) async {
    if (rowIds.isEmpty) return;
    final placeholders = List.filled(rowIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $tableName SET synced_at = ? WHERE rowid IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...rowIds],
    );
  }

  Future<BatchResult> _sendSubmissions(String tableName, String deviceId,
      String token, List<UploadRow> batch) async {
    final result = await apiClient.postSync(
      token: token,
      submissions: batch
          .map((r) => {
                'table_name': tableName,
                'local_uuid': r.wireId,
                'data': r.data,
                'collected_at': r.data['stoptime'] ?? r.data['lastmod'],
                'swver': r.data['swver'],
                'device_id': deviceId,
              })
          .toList(),
      formchanges: const [],
    );
    return BatchResult(syncedWireIds: result.synced, failed: result.failed);
  }

  Future<List<UploadRow>> _fetchFormchangesBatch(
      Database db, int afterRowId, int limit) async {
    final rows = await db.rawQuery(
      // See the comment in _fetchTableBatch -- formchanges is the actual
      // table this collision hits, since it declares
      // `changeid INTEGER PRIMARY KEY AUTOINCREMENT`.
      'SELECT rowid AS uploader_rowid, * FROM formchanges '
      'WHERE changeuniqueid IS NOT NULL '
      'AND synced_at IS NULL AND rowid > ? ORDER BY rowid LIMIT ?',
      [afterRowId, limit],
    );
    final result = <UploadRow>[];
    for (final row in rows) {
      final data = Map<String, dynamic>.from(row);
      final rowId = data.remove('uploader_rowid');
      final wireId = data['changeuniqueid'];
      if (rowId is! int || wireId is! String) {
        debugPrint(
            '[RecordUploader] Skipping malformed formchanges row: rowid=$rowId, changeuniqueid=$wireId');
        continue;
      }
      result.add(UploadRow(rowId: rowId, wireId: wireId, data: data));
    }
    return result;
  }

  Future<void> _markFormchangesSynced(Database db, List<int> rowIds) async {
    if (rowIds.isEmpty) return;
    final placeholders = List.filled(rowIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE formchanges SET synced_at = ? WHERE rowid IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...rowIds],
    );
  }

  Future<BatchResult> _sendFormchanges(
      String token, List<UploadRow> batch) async {
    final result = await apiClient.postSync(
      token: token,
      submissions: const [],
      formchanges: batch
          .map((r) => {
                'formchanges_uuid': r.wireId,
                'record_uuid': r.data['uniqueid'],
                'tablename': r.data['tablename'],
                'fieldname': r.data['fieldname'],
                'oldvalue': r.data['oldvalue'],
                'newvalue': r.data['newvalue'],
                'surveyor_id': r.data['surveyor_id'],
                'changed_at': r.data['changed_at'],
              })
          .toList(),
    );
    return BatchResult(
        syncedWireIds: result.formchangesSynced, failed: result.formchangesFailed);
  }
}
