import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:datakollecta/services/sync/api_client.dart';
import 'package:datakollecta/services/sync/sync_backend.dart';

void main() {
  test('login sends exactly the fields the deployed app-login function expects',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        json.encode({
          'success': true,
          'token': 'session-token',
          'expires_at': '2026-09-13T00:00:00.000Z',
          'surveys': [
            {'id': 'survey-1', 'name': 'AVERT', 'download_url': 'https://x/y.zip'},
          ],
        }),
        200,
      );
    });
    final api = ApiClient(client: client);

    final session = await api.login(
      projectCode: 'demo',
      username: 'alice',
      password: 'super-secret-pw',
      deviceId: 'device-123',
      deviceInfo: {'platform': 'macos'},
    );

    expect(session.token, 'session-token');
    expect(session.expiresAt, DateTime.parse('2026-09-13T00:00:00.000Z'));
    expect(session.surveys.single.id, 'survey-1');
    expect(session.surveys.single.downloadUrl, 'https://x/y.zip');

    expect(captured.headers['Content-Type'], contains('application/json'));
    expect(captured.headers['Authorization'], startsWith('Bearer '));

    final body = json.decode(captured.body) as Map<String, dynamic>;
    expect(body, {
      'project_code': 'demo',
      'username': 'alice',
      'password': 'super-secret-pw',
      'device_id': 'device-123',
      'device_info': {'platform': 'macos'},
    });
  });

  test('login parses the project object and each survey\'s manifest', () async {
    final client = MockClient((request) async => http.Response(
          json.encode({
            'token': 'session-token',
            'expires_at': '2026-09-13T00:00:00.000Z',
            'project': {'id': 'proj-uuid', 'name': 'AVERT UG', 'code': 'avert-ug'},
            'surveys': [
              {
                'id': 'survey-1',
                'name': 'AVERT',
                'download_url': 'https://x/y.zip',
                'manifest': {
                  'surveyId': 'avert_ug_2026',
                  'surveyName': 'AVERT UG 2026',
                  'databaseName': 'avert_ug_2026.sqlite',
                },
              },
            ],
          }),
          200,
        ));
    final api = ApiClient(client: client);

    final session = await api.login(
      projectCode: 'avert-ug',
      username: 'alice',
      password: 'pw',
      deviceId: 'd',
      deviceInfo: const {},
    );

    expect(session.projectName, 'AVERT UG');
    expect(session.surveys.single.surveyId, 'avert_ug_2026');
    expect(session.surveys.single.databaseName, 'avert_ug_2026.sqlite');
  });

  test('login still works when project and manifest are both absent', () async {
    final client = MockClient((request) async => http.Response(
          json.encode({
            'token': 'session-token',
            'expires_at': '2026-09-13T00:00:00.000Z',
            'surveys': [
              {'id': 'survey-1', 'name': 'AVERT'},
            ],
          }),
          200,
        ));
    final api = ApiClient(client: client);

    final session = await api.login(
      projectCode: 'demo',
      username: 'alice',
      password: 'pw',
      deviceId: 'd',
      deviceInfo: const {},
    );

    expect(session.projectName, isNull);
    expect(session.surveys.single.surveyId, isNull);
    expect(session.surveys.single.databaseName, isNull);
  });

  test('login maps 401 to SyncAuthException', () async {
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'Invalid username or password'}), 401));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'alice',
        password: 'wrong',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('login maps 404 (unknown project code) to SyncAuthException', () async {
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'Project not found'}), 404));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'nonexistent',
        username: 'alice',
        password: 'pw',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('login maps 429 to SyncThrottledException, not to an auth failure',
      () async {
    // The throttle is not a credential failure, and the difference is
    // behavioural: the screen replaces an auth failure's message with generic
    // "invalid credentials" copy, which would discard the wait time -- the
    // only part of a throttle response the interviewer can act on.
    final client = MockClient((request) async => http.Response(
        json.encode({
          'error': 'Too many failed attempts. Try again in 15 minutes.',
        }),
        429));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'alice',
        password: 'wrong',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(
        isA<SyncThrottledException>().having(
          (e) => e.message,
          'message',
          'Too many failed attempts. Try again in 15 minutes.',
        ),
      ),
    );
  });

  test('login 429 is not classified as a retryable transfer failure', () async {
    // Before this, an unrecognised 429 fell through to
    // SyncTransferException('Login failed (429)') -- which callers RETRY.
    // Retrying a throttle extends the lockout and loads the endpoint that
    // just asked us to stop.
    final client = MockClient(
        (request) async => http.Response(json.encode({'error': 'slow down'}), 429));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'a',
        password: 'b',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isNot(isA<SyncTransferException>())),
    );
  });

  test('login 429 with no error field still carries usable copy', () async {
    final client = MockClient((request) async => http.Response('', 429));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'a',
        password: 'b',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isA<SyncThrottledException>()
          .having((e) => e.message, 'message', contains('try again'))),
    );
  });

  test('postSync maps 429 to SyncThrottledException', () async {
    // app-sync does not throttle today, but a 429 from a gateway or a future
    // per-device limit must stop the run rather than be retried.
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'slow down'}), 429));
    final api = ApiClient(client: client);

    await expectLater(
      api.postSync(token: 't', submissions: const [], formchanges: const []),
      throwsA(isA<SyncThrottledException>()),
    );
  });

  test('postSync keeps 413 (batch too large) retryable', () async {
    // Deliberately NOT a throttle: an oversized batch is the client's own
    // fault and a smaller one is a sensible retry.
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'Batch too large'}), 413));
    final api = ApiClient(client: client);

    await expectLater(
      api.postSync(token: 't', submissions: const [], formchanges: const []),
      throwsA(isA<SyncTransferException>()),
    );
  });

  test('login maps a 500 to SyncTransferException', () async {
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'Internal server error'}), 500));
    final api = ApiClient(client: client);

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'alice',
        password: 'pw',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isA<SyncTransferException>()),
    );
  });

  test('a hung connection times out as SyncConnectionException, not a hang',
      () async {
    final client = MockClient((request) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });
    final api = ApiClient(
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      api.login(
        projectCode: 'demo',
        username: 'alice',
        password: 'pw',
        deviceId: 'd',
        deviceInfo: const {},
      ),
      throwsA(isA<SyncConnectionException>()),
    );
  });

  test('postSync omits the formchanges key entirely when there are none',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        json.encode({
          'synced': ['u1'],
          'failed': [],
          'formchanges_synced': [],
          'formchanges_failed': [],
        }),
        200,
      );
    });
    final api = ApiClient(client: client);

    final result = await api.postSync(
      token: 'tok',
      submissions: [
        {'table_name': 'enrollee', 'local_uuid': 'u1', 'data': {}},
      ],
      formchanges: const [],
    );

    expect(result.synced, ['u1']);
    final body = json.decode(captured.body) as Map<String, dynamic>;
    expect(body.containsKey('formchanges'), isFalse);
  });

  test('postSync parses partial success -- some synced, some failed',
      () async {
    final client = MockClient((request) async => http.Response(
          json.encode({
            'synced': ['u1'],
            'failed': [
              {'id': 'u2', 'error': 'Survey package not found'}
            ],
            'formchanges_synced': ['fc1'],
            'formchanges_failed': [],
          }),
          200,
        ));
    final api = ApiClient(client: client);

    final result = await api.postSync(
      token: 'tok',
      submissions: [
        {'local_uuid': 'u1'},
        {'local_uuid': 'u2'},
      ],
      formchanges: [
        {'formchanges_uuid': 'fc1'}
      ],
    );

    expect(result.synced, ['u1']);
    expect(result.failed.single.id, 'u2');
    expect(result.failed.single.error, 'Survey package not found');
    expect(result.formchangesSynced, ['fc1']);
  });

  test('postSync maps 401 (expired session) to SyncAuthException', () async {
    final client = MockClient((request) async =>
        http.Response(json.encode({'error': 'Invalid or expired token'}), 401));
    final api = ApiClient(client: client);

    await expectLater(
      api.postSync(token: 'stale', submissions: const [], formchanges: const []),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('a download failure (non-200) never touches the local filesystem',
      () async {
    final client =
        MockClient((request) async => http.Response('not found', 404));
    final api = ApiClient(client: client);

    await expectLater(
      api.downloadSurveyZip('https://x/missing.zip', 'missing.zip'),
      throwsA(isA<SyncTransferException>()),
    );
  });

  test('a download timeout raises SyncConnectionException', () async {
    final client = MockClient((request) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return http.Response.bytes([], 200);
    });
    final api = ApiClient(
      client: client,
      downloadTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      api.downloadSurveyZip('https://x/y.zip', 'y.zip'),
      throwsA(isA<SyncConnectionException>()),
    );
  });

  test(
      'nothing logged during login or sync contains the password, token, or a record value',
      () async {
    final captured = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };

    try {
      final client = MockClient((request) async {
        if (request.url.path.contains('app-login')) {
          return http.Response(
            json.encode({
              'token': 'super-secret-session-token',
              'expires_at': '2026-09-13T00:00:00.000Z',
              'surveys': [],
            }),
            200,
          );
        }
        return http.Response(
          json.encode({
            'synced': [],
            'failed': [],
            'formchanges_synced': [],
            'formchanges_failed': [],
          }),
          200,
        );
      });
      final api = ApiClient(client: client);

      await api.login(
        projectCode: 'demo',
        username: 'alice',
        password: 'super-secret-pw',
        deviceId: 'd',
        deviceInfo: const {},
      );

      await api.postSync(
        token: 'super-secret-session-token',
        submissions: [
          {
            'local_uuid': 'u1',
            'data': {'patient_name': 'a-very-private-name'},
          },
        ],
        formchanges: const [],
      );
    } finally {
      debugPrint = originalDebugPrint;
    }

    for (final line in captured) {
      expect(line, isNot(contains('super-secret-pw')));
      expect(line, isNot(contains('super-secret-session-token')));
      expect(line, isNot(contains('a-very-private-name')));
    }
  });
}
