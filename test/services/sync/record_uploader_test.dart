import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/services/sync/api_client.dart';
import 'package:GiSTX/services/sync/record_uploader.dart';
import 'package:GiSTX/services/sync/sync_backend.dart';

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
}
