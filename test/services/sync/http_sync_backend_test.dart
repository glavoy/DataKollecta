import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:datakollecta/services/sync/api_client.dart';
import 'package:datakollecta/services/sync/http_sync_backend.dart';
import 'package:datakollecta/services/sync/project_sessions.dart';
import 'package:datakollecta/services/sync/record_uploader.dart';
import 'package:datakollecta/services/sync/sync_backend.dart';

/// An in-memory-only repository: no SettingsService, no plugins, so
/// resolveToken's storage side of things is exercised without touching
/// real (or platform-channel-backed) storage.
ProjectSessionsRepository _fakeRepo([ProjectSessionsDocument? seed]) {
  String? stored = seed?.encode();
  return ProjectSessionsRepository(
    read: () async => stored,
    write: (v) async => stored = v,
  );
}

http.Response _loginResponse({
  String token = 'tok',
  String expiresAt = '2099-01-01T00:00:00.000Z',
  List<Map<String, dynamic>> surveys = const [],
}) =>
    http.Response(
      json.encode(
          {'token': token, 'expires_at': expiresAt, 'surveys': surveys}),
      200,
    );

/// Thrown from a [MockClient] handler to simulate an unreachable server --
/// ApiClient turns anything thrown by the transport into a
/// SyncConnectionException.
class _Unreachable implements Exception {
  final String message;
  const _Unreachable(this.message);
}

void main() {
  // HttpSyncBackend._login always calls DeviceIdentity.deviceId(), which is
  // not an injectable seam -- on a device with nothing native to offer it
  // falls back to SettingsService.deviceUuid, i.e. real SharedPreferences
  // (this host runs the _usePrefs branch), which needs the test binding and
  // a mocked store rather than a real platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('resolveLocalFilename', () {
    test('strips a numeric timestamp prefix from the signed URL\'s filename',
        () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/'
            '1768751055830_avert_english.zip?token=abc',
        'AVERT',
      );
      expect(name, 'avert_english.zip');
    });

    test('leaves a filename with no numeric prefix untouched', () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/survey.zip',
        'AVERT',
      );
      expect(name, 'survey.zip');
    });

    test('does not strip a prefix that only looks numeric-ish', () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/'
            'v2_survey.zip',
        'AVERT',
      );
      expect(name, 'v2_survey.zip');
    });

    test('falls back to "<surveyName>.zip" for a malformed URL', () {
      final name =
          HttpSyncBackend.resolveLocalFilename('https://[invalid', 'AVERT');
      expect(name, 'AVERT.zip');
    });

    test('falls back to "<surveyName>.zip" when the URL has no path segments',
        () {
      final name = HttpSyncBackend.resolveLocalFilename(
          'https://x.supabase.co', 'AVERT');
      expect(name, 'AVERT.zip');
    });
  });

  group('resolveToken', () {
    test(
        'a survey bound to a project with a still-valid token uses it directly, no login',
        () async {
      var loginCalls = 0;
      final client = MockClient((request) async {
        loginCalls++;
        return _loginResponse(token: 'should-not-be-used');
      });
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
            projectCode: 'proj-a',
            username: 'u',
            password: 'p',
            token: 'valid-token',
            expiresAt: DateTime.now().add(const Duration(days: 1)),
          ))
          .withAssociation('survey-1', 'proj-a'));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final result = await backend.resolveToken('survey-1');

      expect(result.hasToken, isTrue);
      expect(result.token, 'valid-token');
      expect(loginCalls, 0);
    });

    test(
        'an expired token triggers a silent re-login with that project\'s own credentials',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _loginResponse(token: 'fresh-token');
      });
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
            projectCode: 'proj-a',
            username: 'alice',
            password: 'super-secret',
            token: 'stale-token',
            expiresAt: DateTime.now().subtract(const Duration(days: 1)),
          ))
          .withAssociation('survey-1', 'proj-a'));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final result = await backend.resolveToken('survey-1');

      expect(result.token, 'fresh-token');
      final body = json.decode(captured!.body) as Map<String, dynamic>;
      expect(body['project_code'], 'proj-a');
      expect(body['username'], 'alice');
      expect(body['password'], 'super-secret');

      // And the refreshed token is persisted, not just returned once.
      final reloaded = await repo.load();
      expect(reloaded.sessionFor('proj-a')?.token, 'fresh-token');
    });

    test(
        'a token about to expire within the skew margin also triggers a refresh',
        () async {
      final client =
          MockClient((request) async => _loginResponse(token: 'refreshed'));
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
            projectCode: 'proj-a',
            username: 'u',
            password: 'p',
            token: 'about-to-expire',
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          ))
          .withAssociation('survey-1', 'proj-a'));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final result = await backend.resolveToken('survey-1');
      expect(result.token, 'refreshed');
    });

    test(
        'a survey with no recorded project adopts the one configured project, '
        'without persisting the guess', () async {
      final client = MockClient((request) async => _loginResponse());
      final repo = _fakeRepo(ProjectSessionsDocument.empty.withSession(
        ProjectSession(
          projectCode: 'only-project',
          username: 'u',
          password: 'p',
          token: 'tok',
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      ));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final result = await backend.resolveToken('unassociated-survey');

      expect(result.hasToken, isTrue);
      expect(result.token, 'tok');

      final reloaded = await repo.load();
      expect(reloaded.projectFor('unassociated-survey'), isNull,
          reason: '"exactly one project configured" is a fact about right '
              'now, not about when the data was collected -- adding a '
              'second project later must still be able to fix this survey, '
              'which a persisted guess would prevent');
    });

    test(
        'a survey with no recorded project and more than one configured project '
        'fails routing rather than guessing', () async {
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(
              ProjectSession(projectCode: 'a', username: 'u', password: 'p'))
          .withSession(
              ProjectSession(projectCode: 'b', username: 'u', password: 'p')));
      final backend = HttpSyncBackend(repository: repo);

      final result = await backend.resolveToken('unassociated-survey');

      expect(result.hasToken, isFalse);
      expect(result.failure, RoutingFailure.noAssociatedProject);
    });

    test(
        'a survey bound to a project with no configured session at all fails routing',
        () async {
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withAssociation('survey-1', 'removed-project'));
      final backend = HttpSyncBackend(repository: repo);

      final result = await backend.resolveToken('survey-1');

      expect(result.hasToken, isFalse);
      expect(result.failure, RoutingFailure.noSessionForProject);
    });

    test(
        'a silent re-login that fails (e.g. a rotated password) fails routing cleanly',
        () async {
      final client = MockClient((request) async => http.Response(
          json.encode({'error': 'Invalid username or password'}), 401));
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
            projectCode: 'proj-a',
            username: 'u',
            password: 'stale-password',
            token: 'expired',
            expiresAt: DateTime.now().subtract(const Duration(days: 1)),
          ))
          .withAssociation('survey-1', 'proj-a'));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final result = await backend.resolveToken('survey-1');

      expect(result.hasToken, isFalse);
      expect(result.failure, RoutingFailure.loginFailed);
    });
  });

  group('resolveToken failure kinds', () {
    ProjectSessionsRepository expiredRepo() =>
        _fakeRepo(ProjectSessionsDocument.empty
            .withSession(ProjectSession(
              projectCode: 'proj-a',
              username: 'u',
              password: 'p',
              token: 'expired',
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ))
            .withAssociation('survey-1', 'proj-a'));

    test('an unreachable server is noConnection, never "wrong password"',
        () async {
      final client =
          MockClient((request) async => throw const _Unreachable('offline'));
      final backend = HttpSyncBackend(
          apiClient: ApiClient(client: client), repository: expiredRepo());

      final result = await backend.resolveToken('survey-1');

      expect(result.failure, RoutingFailure.noConnection);
    });

    test('a throttled or failing server is loginUnavailable', () async {
      for (final status in [429, 500]) {
        final client = MockClient((request) async =>
            http.Response(json.encode({'error': 'nope'}), status));
        final backend = HttpSyncBackend(
            apiClient: ApiClient(client: client), repository: expiredRepo());

        final result = await backend.resolveToken('survey-1');

        expect(result.failure, RoutingFailure.loginUnavailable,
            reason: 'status $status');
      }
    });
  });

  group('uploadPending recovering from a server-rejected token', () {
    // A token the device believes has weeks left -- exactly what a phone
    // holds right after its credential's password is reset on the portal.
    ProjectSessionsRepository locallyValidRepo() =>
        _fakeRepo(ProjectSessionsDocument.empty
            .withSession(ProjectSession(
              projectCode: 'proj-a',
              username: 'alice',
              password: 'stored-password',
              token: 'revoked-token',
              expiresAt: DateTime.now().add(const Duration(days: 20)),
            ))
            .withAssociation('survey-1', 'proj-a'));

    const expired = UploadOutcome(
        syncedCount: 0,
        failures: [],
        stopReason: UploadStopReason.sessionExpired);
    const ok = UploadOutcome(
        syncedCount: 3, failures: [], stopReason: UploadStopReason.none);

    test(
        'discards the rejected token and retries with a fresh login, instead '
        'of resending the same token', () async {
      var loginCalls = 0;
      final client = MockClient((request) async {
        loginCalls++;
        return _loginResponse(token: 'fresh-token');
      });
      final tokensUsed = <String>[];
      final repo = locallyValidRepo();
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
        uploadWithToken: (surveyId, token) async {
          tokensUsed.add(token);
          return token == 'revoked-token' ? expired : ok;
        },
      );

      final result = await backend.uploadPending('survey-1');

      expect(tokensUsed, ['revoked-token', 'fresh-token']);
      expect(loginCalls, 1);
      expect(result.routed, isTrue);
      expect(result.outcome!.syncedCount, 3);
      expect((await repo.load()).sessionFor('proj-a')?.token, 'fresh-token');
    });

    test(
        'reports loginFailed when the stored credentials are rejected too, '
        'keeping the stored username/password for the user to fix', () async {
      final client = MockClient((request) async => http.Response(
          json.encode({'error': 'Invalid project code, username, or password'}),
          401));
      final tokensUsed = <String>[];
      final repo = locallyValidRepo();
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
        uploadWithToken: (surveyId, token) async {
          tokensUsed.add(token);
          return expired;
        },
      );

      final result = await backend.uploadPending('survey-1');

      expect(tokensUsed, ['revoked-token'],
          reason: 'the dead token must not be sent a second time');
      expect(result.routed, isFalse);
      expect(result.routingFailure, RoutingFailure.loginFailed);

      final stored = (await repo.load()).sessionFor('proj-a')!;
      expect(stored.username, 'alice');
      expect(stored.password, 'stored-password');
      expect(stored.token, isNull);
    });
  });

  group('addProject (add or update credentials)', () {
    test(
        're-adding an existing project code replaces its credentials and token',
        () async {
      final client =
          MockClient((request) async => _loginResponse(token: 'new'));
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
            projectCode: 'proj-a',
            username: 'old-user',
            password: 'old-password',
            token: 'old',
            expiresAt: DateTime.now().add(const Duration(days: 20)),
          ))
          .withAssociation('survey-1', 'proj-a'));
      final backend = HttpSyncBackend(
          apiClient: ApiClient(client: client), repository: repo);

      await backend.addProject('proj-a', 'new-user', 'new-password');

      final doc = await repo.load();
      expect(doc.sessions, hasLength(1));
      final session = doc.sessionFor('proj-a')!;
      expect(session.username, 'new-user');
      expect(session.password, 'new-password');
      expect(session.token, 'new');
      expect(doc.projectFor('survey-1'), 'proj-a',
          reason:
              'updating credentials must not unbind the project\'s surveys');
    });

    test('rejected or unverifiable credentials store nothing', () async {
      final seed = ProjectSessionsDocument.empty.withSession(ProjectSession(
          projectCode: 'proj-a',
          username: 'old-user',
          password: 'old-password'));
      for (final client in [
        MockClient((request) async =>
            http.Response(json.encode({'error': 'Invalid'}), 401)),
        MockClient((request) async => throw const _Unreachable('offline')),
      ]) {
        final repo = _fakeRepo(seed);
        final backend = HttpSyncBackend(
            apiClient: ApiClient(client: client), repository: repo);

        await expectLater(backend.addProject('proj-a', 'new-user', 'wrong'),
            throwsA(isA<SyncException>()));
        await expectLater(backend.addProject('proj-b', 'u', 'p'),
            throwsA(isA<SyncException>()));

        final doc = await repo.load();
        expect(doc.sessionFor('proj-a')?.password, 'old-password');
        expect(doc.sessionFor('proj-b'), isNull);
      }
    });
  });

  group('checkAllForUpdates', () {
    test('one project failing does not suppress another project\'s surveys',
        () async {
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        if (body['project_code'] == 'broken-project') {
          return http.Response(
              json.encode({'error': 'Internal server error'}), 500);
        }
        return _loginResponse(surveys: [
          {
            'id': 'srv-1',
            'name': 'Healthy Survey',
            'download_url': 'https://x/y.zip',
            'manifest': {
              'surveyId': 'healthy_survey',
              'databaseName': 'h.sqlite'
            },
          },
        ]);
      });
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withSession(ProjectSession(
              projectCode: 'broken-project', username: 'u', password: 'p'))
          .withSession(ProjectSession(
              projectCode: 'healthy-project', username: 'u', password: 'p')));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      final results = await backend.checkAllForUpdates();

      expect(results, hasLength(2));
      final broken =
          results.firstWhere((r) => r.projectCode == 'broken-project');
      final healthy =
          results.firstWhere((r) => r.projectCode == 'healthy-project');

      expect(broken.succeeded, isFalse);
      expect(broken.error, isA<SyncTransferException>());
      expect(healthy.succeeded, isTrue);
      expect(healthy.surveys.single.name, 'Healthy Survey');
      expect(healthy.surveys.single.surveyId, 'healthy_survey');
    });
  });

  group(
      'collision guard (surveyId only -- no databaseName, so no filesystem access)',
      () {
    test(
        'downloading a surveyId already bound to a different project is refused',
        () async {
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withAssociation('shared_survey_id', 'proj-a'));
      final backend = HttpSyncBackend(repository: repo);

      final survey = RemoteProjectSurvey(
        projectCode: 'proj-b',
        name: 'Same Survey, Different Project',
        surveyId: 'shared_survey_id',
        downloadUrl: 'https://x/y.zip',
      );

      await expectLater(
        backend.prepareDownload(survey),
        throwsA(isA<ProjectAssociationConflict>()
            .having(
                (e) => e.existingProjectCode, 'existingProjectCode', 'proj-a')
            .having(
                (e) => e.incomingProjectCode, 'incomingProjectCode', 'proj-b')),
      );

      // And the existing binding must be untouched.
      final doc = await repo.load();
      expect(doc.projectFor('shared_survey_id'), 'proj-a');
    });

    test(
        're-downloading a surveyId already bound to the SAME project is not a conflict',
        () async {
      final repo = _fakeRepo(ProjectSessionsDocument.empty
          .withAssociation('own_survey', 'proj-a'));
      final backend = HttpSyncBackend(repository: repo);

      final survey = RemoteProjectSurvey(
        projectCode: 'proj-a',
        name: 'My Own Survey',
        surveyId: 'own_survey',
        downloadUrl: 'https://x/y.zip',
      );

      // Must not throw, and must return the URL to fetch.
      final url = await backend.prepareDownload(survey);
      expect(url, 'https://x/y.zip');
    });

    test(
        'a project that failed the last Check for Updates cannot be downloaded from',
        () async {
      final repo = _fakeRepo(ProjectSessionsDocument.empty.withSession(
          ProjectSession(projectCode: 'broken', username: 'u', password: 'p')));
      final client = MockClient((request) async =>
          http.Response(json.encode({'error': 'Internal server error'}), 500));
      final backend = HttpSyncBackend(
        apiClient: ApiClient(client: client),
        repository: repo,
      );

      await backend.checkAllForUpdates(); // marks 'broken' as failed

      final survey = RemoteProjectSurvey(
        projectCode: 'broken',
        name: 'Stale Survey',
        surveyId: 'stale_survey',
        downloadUrl: 'https://x/stale.zip',
      );

      await expectLater(
        backend.prepareDownload(survey),
        throwsA(isA<SyncAuthException>()),
      );
    });
  });
}
