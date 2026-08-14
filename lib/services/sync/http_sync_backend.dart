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

  HttpSyncBackend({ApiClient? apiClient, SettingsService? settings})
      : _api = apiClient ?? ApiClient(),
        _settings = settings ?? SettingsService();

  @override
  Future<bool> connect(String username, String password) async {
    final projectCode = await _settings.projectCode;
    if (projectCode == null || projectCode.isEmpty) {
      debugPrint('[HttpSyncBackend] No project code configured');
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
      debugPrint('[HttpSyncBackend] connect failed: $e');
      return false;
    }
  }

  @override
  Future<List<RemoteSurvey>> listSurveys() async =>
      _surveys.map((s) => RemoteSurvey(s.name)).toList();

  @override
  Future<File?> downloadSurvey(String filename) async {
    final survey = _findSurveyByName(filename);
    final downloadUrl = survey?.downloadUrl;
    if (downloadUrl == null) {
      debugPrint('[HttpSyncBackend] No download URL for "$filename"');
      return null;
    }

    try {
      return await _api.downloadSurveyZip(
          downloadUrl, resolveLocalFilename(downloadUrl, filename));
    } on SyncException catch (e) {
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
