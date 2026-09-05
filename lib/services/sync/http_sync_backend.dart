import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../db_service.dart';
import '../survey_config_service.dart';
import 'api_client.dart';
import 'device_identity.dart';
import 'project_sessions.dart';
import 'record_uploader.dart';
import 'sync_backend.dart';

/// One project's survey as offered by [HttpSyncBackend.checkAllForUpdates]
/// -- carries everything needed to download it and to record which project
/// it belongs to, without a second lookup.
class RemoteProjectSurvey {
  final String projectCode;
  final String name;

  /// From the survey's manifest -- the authoritative, device-global
  /// install key (folder name, and DbService's map key). Every survey
  /// listed here has one; app-login embeds the manifest, so this is known
  /// before any download happens.
  final String surveyId;
  final String? databaseName;
  final String? downloadUrl;

  const RemoteProjectSurvey({
    required this.projectCode,
    required this.name,
    required this.surveyId,
    this.databaseName,
    this.downloadUrl,
  });
}

/// One project's outcome from a [HttpSyncBackend.checkAllForUpdates] pass --
/// either its surveys, or why it couldn't be reached/logged into. A single
/// project failing must never suppress the others.
class ProjectCheckResult {
  final String projectCode;
  final String? projectName;
  final List<RemoteProjectSurvey> surveys;
  final SyncException? error;

  const ProjectCheckResult({
    required this.projectCode,
    this.projectName,
    this.surveys = const [],
    this.error,
  });

  bool get succeeded => error == null;
}

/// Why [HttpSyncBackend.uploadPending] couldn't even determine which
/// project's token to upload with -- distinct from
/// [UploadStopReason], which describes why an upload *run* ended early
/// after it had already started. A routing failure never reaches
/// [RecordUploader] at all, so it does not belong in that enum.
enum RoutingFailure {
  /// The survey has no recorded project, and either no project or more
  /// than one project is configured, so there is nothing safe to guess.
  noAssociatedProject,

  /// The survey's project has no stored session (e.g. it was removed in
  /// Settings).
  noSessionForProject,

  /// The stored token was missing/expired and a silent re-login with the
  /// stored password failed.
  loginFailed,
}

class TokenResolution {
  final String? token;
  final RoutingFailure? failure;

  const TokenResolution.token(this.token) : failure = null;
  const TokenResolution.failed(this.failure) : token = null;

  bool get hasToken => token != null;
}

/// The result of attempting to upload one survey's pending records -- either
/// it was routed to a project and [RecordUploader] ran (see [outcome]), or
/// routing itself failed before any record upload was attempted (see
/// [routingFailure]).
class SurveyUploadResult {
  final UploadOutcome? outcome;
  final RoutingFailure? routingFailure;

  const SurveyUploadResult.completed(UploadOutcome this.outcome)
      : routingFailure = null;
  const SurveyUploadResult.notRouted(RoutingFailure reason)
      : outcome = null,
        routingFailure = reason;

  bool get routed => routingFailure == null;
}

/// One installed survey's upload result, named for display -- the mapping
/// from "which project" back to "which survey the interviewer recognizes"
/// lives here so the UI never has to do a second lookup.
class InstalledSurveyUploadResult {
  final String surveyName;
  final String surveyId;
  final SurveyUploadResult result;

  const InstalledSurveyUploadResult(
      this.surveyName, this.surveyId, this.result);
}

/// The DataKollecta product's sync engine: per-project login/session
/// management, survey download with provenance tracking, and routed,
/// upload-everything record sync.
///
/// Deliberately does not implement [SyncBackend] -- that interface's
/// `connect(username, password)` has no meaning once there is no single
/// "the" project, and nothing in production called through it as an
/// interface anyway (both sync screens already instantiate their backend
/// concretely). [SyncException] and its family are still shared from
/// sync_backend.dart, since those genuinely are common to both products.
class HttpSyncBackend {
  final ApiClient _api;
  final SurveyConfigService _surveyConfig;
  final ProjectSessionsRepository _repo;

  /// Projects whose login failed on the most recent [checkAllForUpdates] --
  /// their surveys' signed download URLs are up to 24h old from a *previous*
  /// login and must not be offered for download until checked again.
  final Set<String> _failedProjectCodes = {};

  HttpSyncBackend({
    ApiClient? apiClient,
    SurveyConfigService? surveyConfig,
    ProjectSessionsRepository? repository,
  })  : _api = apiClient ?? ApiClient(),
        _surveyConfig = surveyConfig ?? SurveyConfigService(),
        _repo = repository ?? ProjectSessionsRepository.shared;

  Future<void> disconnect() async => _api.close();

  Future<ProjectSessionsDocument> loadDocument() => _repo.load();

  /// Logs into [projectCode] and stores the resulting session (creating or
  /// replacing whatever was there for that project already). The one path
  /// every other login -- add-project, check-for-updates, silent
  /// re-login -- funnels through. Returns the raw [ApiSession] too (it
  /// carries the survey list), so [checkAllForUpdates] costs exactly one
  /// login per project rather than a second one just to see the surveys.
  Future<
      ({
        ProjectSession session,
        ApiSession apiSession,
      })> _login(String projectCode, String username, String password) async {
    final apiSession = await _api.login(
      projectCode: projectCode,
      username: username,
      password: password,
      deviceId: await DeviceIdentity.deviceId(),
      deviceInfo: await _deviceInfoJson(),
    );
    final session = ProjectSession(
      projectCode: projectCode,
      projectName: apiSession.projectName,
      username: username,
      password: password,
      token: apiSession.token,
      expiresAt: apiSession.expiresAt,
    );
    await _repo.update((doc) => doc.withSession(session));
    return (session: session, apiSession: apiSession);
  }

  /// Adds (or re-authenticates) a project from Settings -- the one place a
  /// login failure must surface to the user immediately rather than be
  /// silently retried later. Throws [SyncException] on failure.
  Future<ProjectSession> addProject(
      String projectCode, String username, String password) async {
    final result = await _login(projectCode, username, password);
    return result.session;
  }

  /// Removes a project's stored session. Associations pointing at it are
  /// deliberately left in place: re-adding the same project code repairs
  /// every survey that pointed at it, and in the meantime a bound survey
  /// fails routing cleanly ([RoutingFailure.noSessionForProject]) instead
  /// of silently adopting a different project.
  Future<void> removeProject(String projectCode) =>
      _repo.update((doc) => doc.withoutSession(projectCode));

  /// Every unsynced record across every survey currently bound to
  /// [projectCode] -- what a "remove this project" confirmation shows
  /// before letting the user cancel.
  Future<int> pendingCountForProject(String projectCode) async {
    final doc = await _repo.load();
    var total = 0;
    for (final surveyId in doc.surveysFor(projectCode)) {
      total += await countPending(surveyId);
    }
    return total;
  }

  /// Logs into every configured project in turn, accumulating results
  /// without letting one project's failure suppress the rest. Never calls
  /// [ApiClient.close] between projects -- the underlying http.Client is
  /// shared and meant to be reused across every call this backend makes.
  Future<List<ProjectCheckResult>> checkAllForUpdates() async {
    final doc = await _repo.load();
    _failedProjectCodes.clear();
    final results = <ProjectCheckResult>[];

    for (final session in doc.sessions.values) {
      try {
        final result = await _login(
            session.projectCode, session.username, session.password);
        final refreshed = result.session;
        final apiSession = result.apiSession;

        final surveys = [
          for (final s in apiSession.surveys)
            if (s.surveyId != null)
              RemoteProjectSurvey(
                projectCode: session.projectCode,
                name: s.name,
                surveyId: s.surveyId!,
                databaseName: s.databaseName,
                downloadUrl: s.downloadUrl,
              ),
        ];

        results.add(ProjectCheckResult(
          projectCode: session.projectCode,
          projectName: refreshed.projectName,
          surveys: surveys,
        ));
      } on SyncException catch (e) {
        _failedProjectCodes.add(session.projectCode);
        debugPrint(
            '[HttpSyncBackend] check failed for ${session.projectCode}: $e');
        results.add(ProjectCheckResult(
          projectCode: session.projectCode,
          projectName: session.projectName,
          error: e,
        ));
      }
    }
    return results;
  }

  /// Binds [survey] to its project (refusing a collision with a different
  /// project first) and downloads it. The association is written *before*
  /// the download starts: a failed download simply leaves behind a correct
  /// "this project offers this surveyId" record, which stays true whether
  /// or not the zip ever arrives.
  Future<File> downloadSurvey(RemoteProjectSurvey survey) async {
    final downloadUrl = await prepareDownload(survey);

    return _api.downloadSurveyZip(
      downloadUrl,
      resolveLocalFilename(downloadUrl, survey.surveyId),
    );
  }

  /// Everything [downloadSurvey] does *before* the actual network fetch:
  /// the failed-project check, the collision guard, and the association
  /// write, returning the URL to fetch. Split out so this -- the part with
  /// real decisions in it -- can be tested without a real download (and
  /// without path_provider's platform channel, which the download half
  /// needs and plain `flutter_test` does not provide).
  @visibleForTesting
  Future<String> prepareDownload(RemoteProjectSurvey survey) async {
    if (_failedProjectCodes.contains(survey.projectCode)) {
      throw SyncAuthException(
          'Project "${survey.projectCode}" could not be reached on the last '
          'check -- tap Check for Updates again before downloading.');
    }
    final downloadUrl = survey.downloadUrl;
    if (downloadUrl == null) {
      throw const SyncTransferException('No download URL for this survey.');
    }

    await _guardAgainstCollision(survey);
    await _repo.update(
        (doc) => doc.withAssociation(survey.surveyId, survey.projectCode));

    return downloadUrl;
  }

  /// Refuses a `surveyId` or `databaseName` already bound to a *different*
  /// project -- both are device-global keys (folder name, open-database map
  /// entry, and the SQLite file itself), so a collision would otherwise
  /// silently mix two projects' records in one physical database.
  Future<void> _guardAgainstCollision(RemoteProjectSurvey survey) async {
    final doc = await _repo.load();

    final existingOwner = doc.projectFor(survey.surveyId);
    if (existingOwner != null && existingOwner != survey.projectCode) {
      throw ProjectAssociationConflict(
        surveyId: survey.surveyId,
        existingProjectCode: existingOwner,
        incomingProjectCode: survey.projectCode,
      );
    }

    final databaseName = survey.databaseName;
    if (databaseName == null) return;
    final ownerSurveyId =
        await _surveyConfig.findSurveyIdForDatabaseName(databaseName);
    if (ownerSurveyId == null || ownerSurveyId == survey.surveyId) return;
    final ownerProject = doc.projectFor(ownerSurveyId);
    if (ownerProject != null && ownerProject != survey.projectCode) {
      throw ProjectAssociationConflict(
        surveyId: survey.surveyId,
        existingProjectCode: ownerProject,
        incomingProjectCode: survey.projectCode,
      );
    }
  }

  /// Resolves which token to upload [surveyId] with, logging in silently if
  /// its project's token is missing or close to expiring. Kept close to
  /// pure -- storage reads and the login call are the only side effects --
  /// so token *selection* is what gets unit-tested, not all of
  /// [uploadPending].
  @visibleForTesting
  Future<TokenResolution> resolveToken(String surveyId, {DateTime? now}) async {
    final doc = await _repo.load();
    var projectCode = doc.projectFor(surveyId);

    if (projectCode == null) {
      // Unknown origin: a zip side-loaded straight into the zips/ folder,
      // or one downloaded before this tracking existed. Adopt the one
      // configured project if there's exactly one -- but never persist the
      // guess. "Exactly one project" is a fact about right now, not about
      // when the data was collected; persisting it would mean a
      // later-added second project could never repair a wrong binding, and
      // the survey list carries no project label the user could notice it
      // by.
      if (doc.sessions.length == 1) {
        projectCode = doc.sessions.keys.single;
      } else {
        return const TokenResolution.failed(RoutingFailure.noAssociatedProject);
      }
    }

    final session = doc.sessionFor(projectCode);
    if (session == null) {
      return const TokenResolution.failed(RoutingFailure.noSessionForProject);
    }

    if (session.isValid(now: now)) {
      return TokenResolution.token(session.token);
    }

    try {
      final result =
          await _login(session.projectCode, session.username, session.password);
      return TokenResolution.token(result.session.token);
    } on SyncException catch (e) {
      debugPrint(
          '[HttpSyncBackend] silent re-login failed for $projectCode: $e');
      return const TokenResolution.failed(RoutingFailure.loginFailed);
    }
  }

  /// Uploads every unsynced record and formchange for [surveyId], routed to
  /// whichever project it's associated with, re-authenticating silently if
  /// that project's token has expired.
  Future<SurveyUploadResult> uploadPending(String surveyId) async {
    final resolution = await resolveToken(surveyId);
    if (!resolution.hasToken) {
      return SurveyUploadResult.notRouted(resolution.failure!);
    }

    var outcome = await _uploadWithToken(surveyId, resolution.token!);

    // The stored token can still expire mid-run (a long upload against a
    // token that had, say, four minutes left when resolveToken checked it).
    // One retry with a freshly resolved token recovers automatically, since
    // the cursor restart only ever re-reads rows still marked unsynced.
    if (outcome.stopReason == UploadStopReason.sessionExpired) {
      final retry = await resolveToken(surveyId);
      if (retry.hasToken) {
        outcome = await _uploadWithToken(surveyId, retry.token!);
      }
    }
    return SurveyUploadResult.completed(outcome);
  }

  Future<UploadOutcome> _uploadWithToken(String surveyId, String token) async {
    final db = await DbService.getDatabaseForQueries(surveyId);
    final deviceId = await DeviceIdentity.deviceId();
    final uploader = RecordUploader(apiClient: _api);
    return uploader.uploadSurvey(db: db, token: token, deviceId: deviceId);
  }

  /// Uploads every installed survey, each routed to its own project. One
  /// call flushes everything on the device -- the mechanism that makes "the
  /// interviewer never switches projects" actually true, rather than true
  /// only for whichever survey happens to be active on the main screen.
  Future<List<InstalledSurveyUploadResult>> uploadAllPending() async {
    final results = <InstalledSurveyUploadResult>[];
    for (final entry in await _installedSurveys()) {
      final result = await uploadPending(entry.$2);
      results.add(InstalledSurveyUploadResult(entry.$1, entry.$2, result));
    }
    return results;
  }

  /// The summed "Pending records" count across every installed survey.
  Future<int> countAllPending() async {
    var total = 0;
    for (final entry in await _installedSurveys()) {
      total += await countPending(entry.$2);
    }
    return total;
  }

  Future<List<(String name, String surveyId)>> _installedSurveys() async {
    final names = await _surveyConfig.getAvailableSurveys();
    final result = <(String, String)>[];
    for (final name in names) {
      final id = await _surveyConfig.getSurveyId(name);
      if (id != null) result.add((name, id));
    }
    return result;
  }

  /// A live count of unsynced records across every CRF table plus
  /// formchanges, for one survey.
  Future<int> countPending(String surveyId) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final tableRows = await db.query('crfs', columns: ['tablename']);
      var total = 0;
      for (final row in tableRows) {
        final tableName = row['tablename'] as String?;
        if (tableName == null) continue;
        final result = await db.rawQuery(
            'SELECT COUNT(*) as count FROM $tableName WHERE synced_at IS NULL');
        total += (result.first['count'] as int?) ?? 0;
      }
      final formchangesResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM formchanges '
              'WHERE changeuniqueid IS NOT NULL AND synced_at IS NULL');
      total += (formchangesResult.first['count'] as int?) ?? 0;
      return total;
    } catch (e) {
      debugPrint('[HttpSyncBackend] countPending failed: $e');
      return 0;
    }
  }

  /// A signed download URL's last path segment is a random, timestamp-
  /// prefixed filename (e.g. `1768751055830_survey.zip`), not the original
  /// upload name -- strip that numeric prefix so the local zip lands under
  /// its real name. Falls back to `<surveyId>.zip` if the URL is
  /// unparseable or has nothing usable. Basing the fallback on `surveyId`
  /// (rather than the display name, as before) keeps it consistent with
  /// the on-device invariant that the extraction folder name must equal
  /// `surveyId` (see SurveyConfigService/DbService).
  ///
  /// Public to allow this parsing to be verified without a network call.
  @visibleForTesting
  static String resolveLocalFilename(String downloadUrl, String surveyId) {
    try {
      final segments = Uri.parse(downloadUrl).pathSegments;
      if (segments.isEmpty || segments.last.isEmpty) {
        return '$surveyId.zip';
      }
      var filename = segments.last;
      final underscoreIndex = filename.indexOf('_');
      if (underscoreIndex != -1) {
        final prefix = filename.substring(0, underscoreIndex);
        if (RegExp(r'^\d+$').hasMatch(prefix)) {
          filename = filename.substring(underscoreIndex + 1);
        }
      }
      return filename;
    } catch (e) {
      return '$surveyId.zip';
    }
  }

  /// A real JSON object (platform, model, OS version) rather than a flat
  /// display string -- nothing in datakollecta-web reads it except
  /// device_id separately, so the richer shape is free.
  Future<Map<String, dynamic>> _deviceInfoJson() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return {
          'platform': 'android',
          'model': info.model,
          'osVersion': info.version.release,
        };
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return {
          'platform': 'windows',
          'model': info.productName,
          'osVersion': info.displayVersion,
        };
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return {
          'platform': 'macos',
          'model': info.model,
          'osVersion': info.osRelease,
        };
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return {
          'platform': 'linux',
          'model': info.name,
          'osVersion': info.version,
        };
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return {
          'platform': 'ios',
          'model': info.model,
          'osVersion': info.systemVersion,
        };
      }
    } catch (e) {
      debugPrint('[HttpSyncBackend] device info lookup failed: $e');
    }
    return {'platform': Platform.operatingSystem};
  }
}
