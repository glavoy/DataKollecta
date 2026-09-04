// lib/services/settings_service.dart
/// Service for managing app settings and user credentials
///
/// Uses flutter_secure_storage on mobile/Windows; falls back to shared_preferences
/// on macOS where keychain entitlements conflict with local ad-hoc signing.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static bool get _usePrefs => Platform.isMacOS || Platform.isLinux;

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  Future<String?> _read(String key) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    try {
      return await _secureStorage.read(key: key);
    } on PlatformException catch (e) {
      // Android's Keystore-backed master key can stop matching the
      // ciphertext already on disk -- observed live as
      // "BadPaddingException ... BAD_DECRYPT" on a device where the key
      // material had gone stale. That failure isn't specific to this key:
      // the whole EncryptedSharedPreferences file was written under the
      // same master key, so every other entry is equally undecryptable.
      // Wiping it (rather than just returning null for this one read)
      // resets the store to the same clean state a fresh install starts
      // from, and lets subsequent writes succeed under a working key
      // instead of failing the same way on every future read.
      debugPrint('[SettingsService] Secure storage read of "$key" failed '
          '(${e.message}); resetting the store.');
      try {
        await _secureStorage.deleteAll();
      } catch (_) {
        // Best-effort -- a failed reset still leaves this read returning
        // null, which is the right fallback either way.
      }
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> _deleteAll() async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secureStorage.deleteAll();
    }
  }

  // Keys for stored values
  static const String _keysurveyorId = 'surveyor_id';
  static const String _keyFtpHost = 'ftp_host';
  static const String _keyFtpUsername = 'ftp_username';
  static const String _keyFtpPassword = 'ftp_password';
  static const String _keyActiveSurvey = 'active_survey';
  static const String _keyDeviceUuid = 'device_uuid';

  /// The encoded ProjectSessionsDocument (see sync/project_sessions.dart) --
  /// every configured DataKollecta project's credentials/token, plus which
  /// project each locally-known survey came from. Replaces what used to be
  /// a single global project_code/api_username/api_password/auth_token set,
  /// which could only ever represent one project at a time.
  static const String _keyProjectSessions = 'dk_project_sessions';

  /// How many times this device has generated a subject ID without being able
  /// to read the existing ones (see [IdGenerator]). It only ever advances, and
  /// it is what makes successive degraded IDs differ from each other -- the
  /// table cannot be consulted to find out which sentinel values are already
  /// taken, because failing to read that table is the reason we are there.
  ///
  /// Persisted rather than kept in memory so a restart between two failures
  /// does not hand out the same sentinel twice.
  static const String _keyIdFallbackCount = 'id_fallback_count';

  // Getters for settings
  Future<String?> get surveyorId async => _read(_keysurveyorId);
  Future<String?> get ftpHost async => _read(_keyFtpHost);
  Future<String?> get ftpUsername async => _read(_keyFtpUsername);
  Future<String?> get ftpPassword async => _read(_keyFtpPassword);
  Future<String?> get activeSurvey async => _read(_keyActiveSurvey);

  /// A random id generated and persisted the first time a platform's own
  /// device-info APIs have nothing usable to offer (see [DeviceIdentity]).
  Future<String?> get deviceUuid async => _read(_keyDeviceUuid);

  /// The raw encoded ProjectSessionsDocument. Read/written through
  /// ProjectSessionsRepository, never decoded here -- SettingsService stays
  /// a plain string store, and the document's shape/versioning lives with
  /// the type that owns it.
  Future<String?> get projectSessionsRaw async => _read(_keyProjectSessions);
  Future<void> setProjectSessionsRaw(String value) =>
      _write(_keyProjectSessions, value);

  /// See [_keyIdFallbackCount]. Unreadable or absent counts as none.
  Future<int> get idFallbackCount async =>
      int.tryParse(await _read(_keyIdFallbackCount) ?? '') ?? 0;

  Future<void> setIdFallbackCount(int value) =>
      _write(_keyIdFallbackCount, value.toString());

  // Setters for settings
  Future<void> setSurveyorId(String value) => _write(_keysurveyorId, value);
  Future<void> setFtpHost(String value) => _write(_keyFtpHost, value);
  Future<void> setFtpUsername(String value) => _write(_keyFtpUsername, value);
  Future<void> setFtpPassword(String value) => _write(_keyFtpPassword, value);
  Future<void> setActiveSurvey(String value) => _write(_keyActiveSurvey, value);
  Future<void> setDeviceUuid(String value) => _write(_keyDeviceUuid, value);

  // Bulk save all settings
  Future<void> saveAllSettings({
    required String surveyorId,
    required String ftpHost,
    required String ftpUsername,
    required String ftpPassword,
    String? activeSurvey,
  }) async {
    await setSurveyorId(surveyorId);
    await setFtpHost(ftpHost);
    await setFtpUsername(ftpUsername);
    await setFtpPassword(ftpPassword);
    if (activeSurvey != null) {
      await setActiveSurvey(activeSurvey);
    }
  }

  // Check if settings are configured
  Future<bool> isConfigured() async {
    final id = await surveyorId;
    return id != null && id.isNotEmpty;
  }

  // Clear all settings
  Future<void> clearAllSettings() => _deleteAll();

  // Survey-specific credentials
  Future<String?> getSurveyUsername(String surveyId) =>
      _read('survey_${surveyId}_username');

  Future<String?> getSurveyPassword(String surveyId) =>
      _read('survey_${surveyId}_password');

  Future<void> setSurveyCredentials(
      String surveyId, String username, String password) async {
    await _write('survey_${surveyId}_username', username);
    await _write('survey_${surveyId}_password', password);
  }

  /// Get credentials for a survey - returns survey-specific if available, otherwise falls back to global
  Future<Map<String, String>?> getCredentialsForSurvey(String surveyId) async {
    final surveyUsername = await getSurveyUsername(surveyId);
    final surveyPassword = await getSurveyPassword(surveyId);

    if (surveyUsername != null && surveyPassword != null) {
      return {'username': surveyUsername, 'password': surveyPassword};
    }

    final globalUsername = await ftpUsername;
    final globalPassword = await ftpPassword;

    if (globalUsername != null && globalPassword != null) {
      return {'username': globalUsername, 'password': globalPassword};
    }

    return null;
  }

  // Survey-specific Surveyor ID -- a field worker can legitimately be
  // assigned a different Surveyor ID per project, the same reason
  // credentials are per-survey above.
  Future<String?> getSurveyorIdForSurvey(String surveyId) =>
      _read('survey_${surveyId}_surveyorId');

  Future<void> setSurveyorIdForSurvey(String surveyId, String value) =>
      _write('survey_${surveyId}_surveyorId', value);

  /// Surveyor ID for [surveyId] if one was saved for that survey, else the
  /// global Surveyor ID -- the same survey-then-global fallback
  /// [getCredentialsForSurvey] already applies to username/password.
  Future<String?> getSurveyorIdOrGlobal(String surveyId) async {
    final perSurvey = await getSurveyorIdForSurvey(surveyId);
    if (perSurvey != null && perSurvey.isNotEmpty) return perSurvey;
    return surveyorId;
  }
}
