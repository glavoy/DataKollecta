import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:datakollecta/services/settings_service.dart';
import 'package:datakollecta/services/sync/api_client.dart';
import 'package:datakollecta/services/sync/record_uploader.dart';
import 'package:datakollecta/services/sync/sync_backend.dart';

void main() {
  final uploader = RecordUploader(batchSize: 2, maxConsecutiveFailures: 3);

  UploadRow row(int rowId) =>
      UploadRow(rowId: rowId, wireId: 'w$rowId', data: {'uniqueid': 'w$rowId'});

  test('nothing to upload makes no send calls and does not stop early',
      () async {
    var sendCalls = 0;
    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async => [],
      markSynced: (_) async {},
      send: (batch) async {
        sendCalls++;
        return const BatchResult(syncedWireIds: [], failed: []);
      },
    );

    expect(sendCalls, 0);
    expect(outcome.syncedCount, 0);
    expect(outcome.failures, isEmpty);
    expect(outcome.stoppedEarly, isFalse);
  });

  test('every row across every batch succeeds and gets marked synced',
      () async {
    final allRows = List.generate(5, (i) => row(i + 1));
    final markedRowIds = <int>[];

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async =>
          allRows.where((r) => r.rowId > after).take(limit).toList(),
      markSynced: (rowIds) async => markedRowIds.addAll(rowIds),
      send: (batch) async => BatchResult(
        syncedWireIds: batch.map((r) => r.wireId).toList(),
        failed: const [],
      ),
    );

    expect(outcome.syncedCount, 5);
    expect(outcome.failures, isEmpty);
    expect(outcome.stoppedEarly, isFalse);
    expect(markedRowIds, [1, 2, 3, 4, 5]);
  });

  test('the cursor is strictly monotonic across batches', () async {
    final allRows = List.generate(6, (i) => row(i + 1));
    final requestedAfter = <int>[];

    await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async {
        requestedAfter.add(after);
        return allRows.where((r) => r.rowId > after).take(limit).toList();
      },
      markSynced: (_) async {},
      send: (batch) async => BatchResult(
        syncedWireIds: batch.map((r) => r.wireId).toList(),
        failed: const [],
      ),
    );

    expect(requestedAfter, [0, 2, 4, 6]);
  });

  test('a partially failed batch marks the successes and records the failure',
      () async {
    final batch = [row(1), row(2)];
    final markedRowIds = <int>[];

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async => after == 0 ? batch : [],
      markSynced: (rowIds) async => markedRowIds.addAll(rowIds),
      send: (b) async => const BatchResult(
        syncedWireIds: ['w1'],
        failed: [ApiSyncFailure(id: 'w2', error: 'Survey package not found')],
      ),
    );

    expect(outcome.syncedCount, 1);
    expect(markedRowIds, [1]);
    expect(outcome.failures.single.id, 'w2');
    expect(outcome.failures.single.error, 'Survey package not found');
    expect(outcome.stoppedEarly, isFalse);
  });

  test(
      'a server that fails every batch terminates within a bounded number of '
      'send calls instead of hanging (regression test for the reference '
      'branch\'s infinite-retry defect)', () async {
    // Far more rows than 3 (maxConsecutiveFailures) batches of 2 could ever
    // cover -- if the old bug were present, this source would be re-queried
    // forever instead of the run stopping.
    final allRows = List.generate(1000, (i) => row(i + 1));
    var sendCalls = 0;
    final requestedAfter = <int>[];

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async {
        requestedAfter.add(after);
        return allRows.where((r) => r.rowId > after).take(limit).toList();
      },
      markSynced: (_) async =>
          fail('a batch that only ever fails must never be marked synced'),
      send: (batch) async {
        sendCalls++;
        throw const SyncTransferException('server is down');
      },
    );

    expect(sendCalls, 3); // exactly maxConsecutiveFailures
    expect(outcome.stoppedEarly, isTrue);
    expect(outcome.stopReason, UploadStopReason.tooManyFailures);
    expect(outcome.syncedCount, 0);
    expect(outcome.failedCount, 6); // 3 batches x 2 rows
    // The cursor still advanced on every failed batch.
    expect(requestedAfter, [0, 2, 4]);
  });

  test('a batch that "succeeds" over HTTP but syncs nothing also trips the '
      'circuit breaker (no exception needed)', () async {
    final allRows = List.generate(1000, (i) => row(i + 1));
    var sendCalls = 0;

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async =>
          allRows.where((r) => r.rowId > after).take(limit).toList(),
      markSynced: (_) async {},
      send: (batch) async {
        sendCalls++;
        return BatchResult(
          syncedWireIds: const [],
          failed:
              batch.map((r) => ApiSyncFailure(id: r.wireId, error: 'rejected')).toList(),
        );
      },
    );

    expect(sendCalls, 3);
    expect(outcome.stopReason, UploadStopReason.tooManyFailures);
  });

  test('a session-expired batch stops the run immediately, no further fetches',
      () async {
    var fetchCalls = 0;

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async {
        fetchCalls++;
        return [row(1), row(2)];
      },
      markSynced: (_) async {},
      send: (batch) async => throw const SyncAuthException('Session expired'),
    );

    expect(fetchCalls, 1);
    expect(outcome.stopReason, UploadStopReason.sessionExpired);
    expect(outcome.syncedCount, 0);
  });

  test('a success after earlier failures resets the circuit breaker',
      () async {
    final allRows = List.generate(6, (i) => row(i + 1));
    var callIndex = 0;

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async =>
          allRows.where((r) => r.rowId > after).take(limit).toList(),
      markSynced: (_) async {},
      send: (batch) async {
        callIndex++;
        // Fail the first two batches, then succeed on the rest -- if the
        // breaker didn't reset, batch 3 would push the count to 3 and stop.
        if (callIndex <= 2) throw const SyncTransferException('flaky');
        return BatchResult(
          syncedWireIds: batch.map((r) => r.wireId).toList(),
          failed: const [],
        );
      },
    );

    expect(outcome.stoppedEarly, isFalse);
    expect(outcome.syncedCount, 2); // only the last batch of 2 succeeded
  });

  test(
      'two rows sharing one wireId (a duplicate-uniqueid pair, e.g. the '
      'historical double-tap-save bug) both get marked synced, not just '
      'whichever one a naive wireId -> rowId map happened to keep', () async {
    // Same shape as the real subject 21040040057 case DbService.
    // collapseDuplicateUniqueIds resolves for editing: two on-device rows
    // share one uniqueid. Editing either sets synced_at = null on both, so
    // both land in the same upload batch.
    final batch = [
      UploadRow(rowId: 10, wireId: 'dup', data: const {}),
      UploadRow(rowId: 11, wireId: 'dup', data: const {}),
    ];
    final markedRowIds = <int>[];

    final outcome = await uploader.upload(
      sourceName: 'enrollee',
      fetchBatch: (after, limit) async => after == 0 ? batch : [],
      markSynced: (rowIds) async => markedRowIds.addAll(rowIds),
      // Two entries, not one: app-sync loops per submission, so a batch
      // holding two submissions with the same local_uuid echoes that wireId
      // back twice -- exercising the exact shape that first exposed the
      // double-count bug (naive expansion produced [10, 11, 10, 11]).
      send: (b) async =>
          const BatchResult(syncedWireIds: ['dup', 'dup'], failed: []),
    );

    expect(markedRowIds, unorderedEquals([10, 11]));
    expect(outcome.syncedCount, 2);
  });

  group('uploadSurvey against a real SQLite database', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE crfs (tablename TEXT)',
      );
      await db.execute(
        'CREATE TABLE enrollee (uniqueid TEXT, subjid TEXT, lastmod TEXT, '
        'synced_at DATETIME)',
      );
      await db.execute(
        'CREATE TABLE formchanges (changeid INTEGER PRIMARY KEY AUTOINCREMENT, '
        'tablename TEXT, fieldname TEXT, uniqueid TEXT, oldvalue TEXT, '
        'newvalue TEXT, changed_at TEXT, changeuniqueid TEXT, '
        'surveyor_id TEXT, synced_at DATETIME)',
      );
      await db.insert('crfs', {'tablename': 'enrollee'});
    });

    tearDown(() => db.close());

    test(
        'a genuine unsynced row is read with a real int rowid and gets '
        'marked synced end-to-end (the happy path this file had zero real-'
        'database coverage for before)', () async {
      await db.insert('enrollee',
          {'uniqueid': 'u1', 'subjid': 's1', 'lastmod': 't1'});

      final uploader = RecordUploader(apiClient: _FakeApiClient());
      final outcome = await uploader.uploadSurvey(
          db: db, token: 't', deviceId: 'd');

      expect(outcome.syncedCount, 1);
      expect(outcome.stoppedEarly, isFalse);
      final rows = await db.query('enrollee');
      expect(rows.single['synced_at'], isNotNull);
    });

    test(
        'two rows sharing one uniqueid (an edit swept both back to '
        'synced_at = null) both get marked synced after upload, mirroring '
        'the real subject 21040040057 scenario', () async {
      await db.insert('enrollee',
          {'uniqueid': 'dup', 'subjid': 's1', 'lastmod': 't1'});
      await db.insert('enrollee',
          {'uniqueid': 'dup', 'subjid': 's1', 'lastmod': 't2'});

      final uploader = RecordUploader(apiClient: _FakeApiClient());
      final outcome = await uploader.uploadSurvey(
          db: db, token: 't', deviceId: 'd');

      expect(outcome.syncedCount, 2);
      final rows = await db.query('enrollee');
      expect(rows.every((r) => r['synced_at'] != null), isTrue);
    });

    test(
        'a formchanges row is uploaded and marked synced, not skipped as '
        'malformed (regression test for the changeid/rowid column collision: '
        "formchanges' own INTEGER PRIMARY KEY is named changeid, not rowid, "
        'so SELECT rowid, * used to report the alias under the name '
        '"changeid" -- identical to the real changeid column from *, which '
        'silently swallowed the rowid key and made every row look malformed)',
        () async {
      await db.insert('formchanges', {
        'tablename': 'enrollee',
        'fieldname': 'nmembers',
        'uniqueid': 'u1',
        'oldvalue': '2',
        'newvalue': '1',
        'changed_at': 't1',
        'changeuniqueid': 'c1',
        'surveyor_id': 's1',
      });

      final uploader = RecordUploader(apiClient: _FakeApiClient());
      final outcome = await uploader.uploadSurvey(
          db: db, token: 't', deviceId: 'd');

      expect(outcome.syncedCount, 1);
      final rows = await db.query('formchanges');
      expect(rows.single['synced_at'], isNotNull);
    });
  });

  group('the configured batch size', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('comes from settings, not from the compiled-in default', () async {
      await SettingsService().setSyncBatchSize(50);

      final configured =
          await RecordUploader.configured(apiClient: _FakeApiClient());

      expect(configured.batchSize, 50);
      expect(configured.batchSize, isNot(RecordUploader.defaultBatchSize));
    });

    test('is 25 on a device that has never set one', () async {
      final configured =
          await RecordUploader.configured(apiClient: _FakeApiClient());

      expect(configured.batchSize, SettingsService.defaultSyncBatchSize);
    });

    test('is re-read per uploader, so a change takes effect on the next sync',
        () async {
      // The reason `configured` is a factory rather than a cached field: the
      // setting is usually changed *because* a sync is failing on the
      // connection at hand, so waiting for an app restart would defeat it.
      await SettingsService().setSyncBatchSize(5);
      expect((await RecordUploader.configured(apiClient: _FakeApiClient()))
          .batchSize, 5);

      await SettingsService().setSyncBatchSize(100);
      expect((await RecordUploader.configured(apiClient: _FakeApiClient()))
          .batchSize, 100);
    });

    test('a stored value beyond the ceiling is clamped, never sent as-is',
        () async {
      // app-sync refuses more than 500 rows with a 413, which RecordUploader
      // reads as an ordinary transfer failure and retries -- three times,
      // then it stops the run. Clamping means a bad setting degrades to a
      // slow sync rather than a stopped one.
      SharedPreferences.setMockInitialValues({'sync_batch_size': '5000'});

      final configured =
          await RecordUploader.configured(apiClient: _FakeApiClient());

      expect(configured.batchSize, SettingsService.maxSyncBatchSize);
    });
  });
}

/// Reports every submission/formchange it's handed as synced -- enough to
/// drive [RecordUploader.uploadSurvey] end-to-end without a real network
/// call, matching the fakes already used for [RecordUploader.upload] above.
class _FakeApiClient implements ApiClient {
  @override
  Future<ApiSyncResult> postSync({
    required String token,
    required List<Map<String, dynamic>> submissions,
    required List<Map<String, dynamic>> formchanges,
  }) async {
    return ApiSyncResult(
      synced: submissions.map((s) => s['local_uuid'] as String).toList(),
      failed: const [],
      formchangesSynced:
          formchanges.map((f) => f['formchanges_uuid'] as String).toList(),
      formchangesFailed: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
