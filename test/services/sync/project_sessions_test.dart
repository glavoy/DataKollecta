import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/sync/project_sessions.dart';

ProjectSession _session(String code, {String? token, DateTime? expiresAt}) =>
    ProjectSession(
      projectCode: code,
      projectName: '$code display name',
      username: '${code}_user',
      password: '${code}_pw',
      token: token,
      expiresAt: expiresAt,
    );

void main() {
  group('ProjectSession.isValid', () {
    test('a token with plenty of time left is valid', () {
      final session = _session('a',
          token: 't', expiresAt: DateTime(2026, 1, 1, 12));
      expect(session.isValid(now: DateTime(2026, 1, 1, 0)), isTrue);
    });

    test('a token already past its expiry is invalid', () {
      final session = _session('a',
          token: 't', expiresAt: DateTime(2026, 1, 1, 0));
      expect(session.isValid(now: DateTime(2026, 1, 1, 1)), isFalse);
    });

    test('a token inside the skew margin is treated as invalid, not just-barely-valid', () {
      final session = _session('a',
          token: 't', expiresAt: DateTime(2026, 1, 1, 12, 3));
      // 3 minutes left, default 5-minute skew -- must refresh, not squeak by.
      expect(session.isValid(now: DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('a token just outside the skew margin is still valid', () {
      final session = _session('a',
          token: 't', expiresAt: DateTime(2026, 1, 1, 12, 6));
      expect(session.isValid(now: DateTime(2026, 1, 1, 12, 0)), isTrue);
    });

    test('no token at all is invalid regardless of expiresAt', () {
      final session = _session('a', expiresAt: DateTime(2030));
      expect(session.isValid(now: DateTime(2026)), isFalse);
    });

    test('a token with no expiresAt is invalid', () {
      const session = ProjectSession(
        projectCode: 'a',
        username: 'u',
        password: 'p',
        token: 'orphaned-token',
      );
      expect(session.isValid(now: DateTime(2026)), isFalse);
    });
  });

  group('ProjectSessionsDocument encode/decode', () {
    test('round-trips sessions and associations through JSON', () {
      const doc = ProjectSessionsDocument(
        sessions: {
          'proj-a': ProjectSession(
            projectCode: 'proj-a',
            projectName: 'Project A',
            username: 'alice',
            password: 'pw-a',
            token: 'tok-a',
          ),
        },
        associations: {'survey-1': 'proj-a'},
      );

      final decoded = ProjectSessionsDocument.decode(doc.encode());

      expect(decoded.sessions.keys, ['proj-a']);
      expect(decoded.sessionFor('proj-a')?.username, 'alice');
      expect(decoded.sessionFor('proj-a')?.password, 'pw-a');
      expect(decoded.sessionFor('proj-a')?.token, 'tok-a');
      expect(decoded.projectFor('survey-1'), 'proj-a');
    });

    test('decoding null or empty returns an empty document, not an error', () {
      expect(ProjectSessionsDocument.decode(null).sessions, isEmpty);
      expect(ProjectSessionsDocument.decode('').sessions, isEmpty);
    });

    test('decoding garbage JSON returns an empty document rather than throwing', () {
      final decoded = ProjectSessionsDocument.decode('{not valid json');
      expect(decoded.sessions, isEmpty);
      expect(decoded.associations, isEmpty);
    });

    test('decoding a document with the wrong top-level shape returns empty', () {
      final decoded = ProjectSessionsDocument.decode('[1, 2, 3]');
      expect(decoded.sessions, isEmpty);
    });

    test('a malformed individual session entry is skipped, not fatal to the whole document', () {
      final decoded = ProjectSessionsDocument.decode(
          '{"sessions": {"good": {"projectCode": "good", "username": "u", "password": "p"}, '
          '"bad": {"projectCode": "bad"}}, "associations": {}}');
      expect(decoded.sessions.keys, ['good']);
    });
  });

  group('ProjectSessionsDocument mutation', () {
    test('withSession adds a new project and withSession again replaces it', () {
      final doc = ProjectSessionsDocument.empty
          .withSession(_session('a', token: 'old'))
          .withSession(_session('a', token: 'new'));
      expect(doc.sessions.length, 1);
      expect(doc.sessionFor('a')?.token, 'new');
    });

    test('withoutSession removes the session but leaves associations intact', () {
      final doc = ProjectSessionsDocument.empty
          .withSession(_session('a'))
          .withAssociation('survey-1', 'a')
          .withoutSession('a');

      expect(doc.sessionFor('a'), isNull);
      expect(doc.projectFor('survey-1'), 'a',
          reason: 'removing a project must not silently orphan its survey '
              'bindings -- re-adding the project should repair them');
    });

    test('withAssociation binds a new surveyId', () {
      final doc = ProjectSessionsDocument.empty.withAssociation('s1', 'a');
      expect(doc.projectFor('s1'), 'a');
    });

    test('withAssociation is idempotent for the same project', () {
      final doc = ProjectSessionsDocument.empty.withAssociation('s1', 'a');
      final again = doc.withAssociation('s1', 'a');
      expect(identical(doc, again) || again.projectFor('s1') == 'a', isTrue);
    });

    test('withAssociation refuses to rebind a surveyId to a different project', () {
      final doc = ProjectSessionsDocument.empty.withAssociation('s1', 'a');
      expect(
        () => doc.withAssociation('s1', 'b'),
        throwsA(isA<ProjectAssociationConflict>()
            .having((e) => e.surveyId, 'surveyId', 's1')
            .having((e) => e.existingProjectCode, 'existingProjectCode', 'a')
            .having((e) => e.incomingProjectCode, 'incomingProjectCode', 'b')),
      );
      // And the conflict must not have mutated anything.
      expect(doc.projectFor('s1'), 'a');
    });

    test('withoutAssociation removes just that one binding', () {
      final doc = ProjectSessionsDocument.empty
          .withAssociation('s1', 'a')
          .withAssociation('s2', 'a')
          .withoutAssociation('s1');
      expect(doc.projectFor('s1'), isNull);
      expect(doc.projectFor('s2'), 'a');
    });

    test('surveysFor lists every survey bound to a project', () {
      final doc = ProjectSessionsDocument.empty
          .withAssociation('s1', 'a')
          .withAssociation('s2', 'a')
          .withAssociation('s3', 'b');
      expect(doc.surveysFor('a').toSet(), {'s1', 's2'});
      expect(doc.surveysFor('b'), ['s3']);
      expect(doc.surveysFor('nonexistent'), isEmpty);
    });
  });

  group('ProjectSessionsRepository', () {
    test('load() decodes whatever the injected read closure returns', () async {
      final repo = ProjectSessionsRepository(
        read: () async => ProjectSessionsDocument.empty
            .withSession(_session('a'))
            .encode(),
        write: (_) async {},
      );
      final doc = await repo.load();
      expect(doc.sessionFor('a'), isNotNull);
    });

    test('update() persists the result of applying the function', () async {
      String? written;
      final repo = ProjectSessionsRepository(
        read: () async => written,
        write: (v) async => written = v,
      );

      await repo.update((doc) => doc.withSession(_session('a', token: 'tok')));

      final reloaded = await repo.load();
      expect(reloaded.sessionFor('a')?.token, 'tok');
    });

    test('update() propagates a thrown conflict without writing anything', () async {
      var writeCalls = 0;
      final repo = ProjectSessionsRepository(
        read: () async =>
            ProjectSessionsDocument.empty.withAssociation('s1', 'a').encode(),
        write: (_) async => writeCalls++,
      );

      await expectLater(
        repo.update((doc) => doc.withAssociation('s1', 'b')),
        throwsA(isA<ProjectAssociationConflict>()),
      );
      expect(writeCalls, 0);
    });

    test(
        'two concurrent updates against the same backing store both survive -- '
        'neither drops the other\'s change', () async {
      String? stored;
      final repo = ProjectSessionsRepository(
        read: () async => stored,
        write: (v) async {
          // A tiny delay makes an unserialized read-modify-write race
          // observable: without the repository's single-flight chain, both
          // updates would read the same "before" state and the second
          // write would clobber the first.
          await Future.delayed(const Duration(milliseconds: 5));
          stored = v;
        },
      );

      final first = repo.update((doc) => doc.withSession(_session('a')));
      final second = repo.update((doc) => doc.withSession(_session('b')));
      await Future.wait([first, second]);

      final result = ProjectSessionsDocument.decode(stored);
      expect(result.sessionFor('a'), isNotNull);
      expect(result.sessionFor('b'), isNotNull);
    });

    test('a failed update does not wedge the queue for the next caller', () async {
      final repo = ProjectSessionsRepository(
        read: () async =>
            ProjectSessionsDocument.empty.withAssociation('s1', 'a').encode(),
        write: (_) async {},
      );

      await expectLater(
        repo.update((doc) => doc.withAssociation('s1', 'b')),
        throwsA(isA<ProjectAssociationConflict>()),
      );

      // A perfectly valid subsequent update must still go through.
      final after = await repo.update((doc) => doc.withSession(_session('c')));
      expect(after.sessionFor('c'), isNotNull);
    });
  });
}
