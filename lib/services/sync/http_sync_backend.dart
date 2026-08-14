import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../db_service.dart';
import '../settings_service.dart';
import 'api_client.dart';
import 'device_identity.dart';
import 'record_uploader.dart';
import 'sync_backend.dart';

/// Adapts [ApiClient] to [SyncBackend] for the DataKollecta product. Upload
/// stays out of the [SyncBackend] seam (see sync_backend.dart) -- callers
/// use [uploadPending] directly, the same way sync_screen.dart calls
/// FtpService.uploadFile directly for the FTP product.
class HttpSyncBackend implements SyncBackend {
  final ApiClient _api;
  final SettingsService _settings;
  List<ApiSurvey> _surveys = const [];

  /// Set on the most recent failed [connect] or [downloadSurvey] call
  /// (cleared at the start of each), so a caller that gets `false`/`null`
  /// back can exhaustively switch on the reason instead of guessing from a
  /// generic failure.
  SyncException? lastError;

  HttpSyncBackend({ApiClient? apiClient, SettingsService? settings})
      : _api = apiClient ?? ApiClient(),
        _settings = settings ?? SettingsService();

  @override
  Future<bool> connect(String username, String password) async {
    lastError = null;
    final projectCode = await _settings.projectCode;
    if (projectCode == null || projectCode.isEmpty) {
      lastError = const SyncAuthException('No project code configured');
      return false;
    }

    try {
      final deviceId = await DeviceIdentity.deviceId();
      final deviceInfo = await _deviceInfoJson();
      final session = await _api.login(
        projectCode: projectCode,
        username: username,
        password: password,
        deviceId: deviceId,
        deviceInfo: deviceInfo,
      );
      _surveys = session.surveys;
      await _settings.setAuthToken(session.token, session.expiresAt);
      return true;
    } on SyncException catch (e) {
      lastError = e;
      debugPrint('[HttpSyncBackend] connect failed: $e');
      return false;
    }
  }

  @override
  Future<List<RemoteSurvey>> listSurveys() async =>
      _surveys.map((s) => RemoteSurvey(s.name)).toList();

  @override
  Future<File?> downloadSurvey(String filename) async {
    lastError = null;
    final survey = _findSurveyByName(filename);
    final downloadUrl = survey?.downloadUrl;
    if (downloadUrl == null) {
      lastError = SyncTransferException('No download URL for "$filename"');
      return null;
    }

    try {
      return await _api.downloadSurveyZip(
          downloadUrl, resolveLocalFilename(downloadUrl, filename));
    } on SyncException catch (e) {
      lastError = e;
      debugPrint('[HttpSyncBackend] download failed: $e');
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    _surveys = const [];
    _api.close();
  }

  /// Uploads every unsynced record and formchange for [surveyId]. Not part
  /// of [SyncBackend] -- called directly by the DataKollecta sync screen,
  /// the same way FTP upload is called directly on FtpService.
  Future<UploadOutcome> uploadPending(String surveyId) async {
    final token = await _settings.validAuthToken;
    if (token == null) {
      return const UploadOutcome(
        syncedCount: 0,
        failures: [],
        stopReason: UploadStopReason.sessionExpired,
      );
    }

    final db = await DbService.getDatabaseForQueries(surveyId);
    final deviceId = await DeviceIdentity.deviceId();
    final uploader = RecordUploader(apiClient: _api);
    return uploader.uploadSurvey(db: db, token: token, deviceId: deviceId);
  }

  /// A live count of unsynced records across every CRF table plus
  /// formchanges, for the "N pending" display before a user taps upload.
  Future<int> countPending(String surveyId) async {
    try {
      final db = await DbService.getDatabaseForQueries(surveyId);
      final tableRows = await db.query('crfs', columns: ['tablename']);
      var total = 0;
      for (final row in tableRows) {
        final tableName = row['tablename'] as String?;
        if (tableName == null) continue;
        final result = await db
            .rawQuery('SELECT COUNT(*) as count FROM $tableName WHERE synced_at IS NULL');
        total += (result.first['count'] as int?) ?? 0;
      }
      final formchangesResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM formchanges '
          'WHERE changeuniqueid IS NOT NULL AND synced_at IS NULL');
      total += (formchangesResult.first['count'] as int?) ?? 0;
      return total;
    } catch (e) {
      debugPrint('[HttpSyncBackend] countPending failed: $e');
      return 0;
    }
  }

  ApiSurvey? _findSurveyByName(String name) {
    for (final survey in _surveys) {
      if (survey.name == name) return survey;
    }
    return null;
  }

  /// A signed download URL's last path segment is a random, timestamp-
  /// prefixed filename (e.g. `1768751055830_survey.zip`), not the original
  /// upload name -- strip that numeric prefix so the local zip lands under
  /// its real name. Falls back to `<surveyName>.zip` if the URL is
  /// unparseable or has nothing usable.
  ///
  /// Public to allow this parsing to be verified without a network call.
  @visibleForTesting
  static String resolveLocalFilename(String downloadUrl, String surveyName) {
    try {
      final segments = Uri.parse(downloadUrl).pathSegments;
      if (segments.isEmpty || segments.last.isEmpty) {
        return '$surveyName.zip';
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
      return '$surveyName.zip';
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
