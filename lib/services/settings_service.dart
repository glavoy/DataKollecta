// lib/services/settings_service.dart
/// Service for managing app settings and user credentials
///
/// Uses flutter_secure_storage on mobile/Windows; falls back to shared_preferences
/// on macOS where keychain entitlements conflict with local ad-hoc signing.

import 'dart:io';
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
    return _secureStorage.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> _delete(String key) async {
    if (_usePrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _secureStorage.delete(key: key);
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
  static const String _keyProjectCode = 'project_code';
  static const String _keyApiUsername = 'api_username';
  static const String _keyApiPassword = 'api_password';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyAuthTokenExpiresAt = 'auth_token_expires_at';

  // Getters for settings
  Future<String?> get surveyorId async => _read(_keysurveyorId);
  Future<String?> get ftpHost async => _read(_keyFtpHost);
  Future<String?> get ftpUsername async => _read(_keyFtpUsername);
  Future<String?> get ftpPassword async => _read(_keyFtpPassword);
  Future<String?> get activeSurvey async => _read(_keyActiveSurvey);

  /// A random id generated and persisted the first time a platform's own
  /// device-info APIs have nothing usable to offer (see [DeviceIdentity]).
  Future<String?> get deviceUuid async => _read(_keyDeviceUuid);

  /// The DataKollecta project slug entered in Settings. There is no
  /// project-switcher UI -- one free-text code per install.
  Future<String?> get projectCode async => _read(_keyProjectCode);
  Future<String?> get apiUsername async => _read(_keyApiUsername);
  Future<String?> get apiPassword async => _read(_keyApiPassword);

  /// The stored bearer token, but only if it hasn't expired -- an expired
  /// token reads the same as no token at all, so callers never need a
  /// separate expiry check.
  Future<String?> get validAuthToken async {
    final token = await _read(_keyAuthToken);
    final expiresAtStr = await _read(_keyAuthTokenExpiresAt);
    if (token == null || expiresAtStr == null) return null;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) return null;
    return token;
  }

  // Setters for settings
  Future<void> setSurveyorId(String value) => _write(_keysurveyorId, value);
  Future<void> setFtpHost(String value) => _write(_keyFtpHost, value);
  Future<void> setFtpUsername(String value) => _write(_keyFtpUsername, value);
  Future<void> setFtpPassword(String value) => _write(_keyFtpPassword, value);
  Future<void> setActiveSurvey(String value) => _write(_keyActiveSurvey, value);
  Future<void> setDeviceUuid(String value) => _write(_keyDeviceUuid, value);
  Future<void> setProjectCode(String value) => _write(_keyProjectCode, value);
  Future<void> setApiUsername(String value) => _write(_keyApiUsername, value);
  Future<void> setApiPassword(String value) => _write(_keyApiPassword, value);

  Future<void> setAuthToken(String token, DateTime expiresAt) async {
    await _write(_keyAuthToken, token);
    await _write(_keyAuthTokenExpiresAt, expiresAt.toIso8601String());
  }

  Future<void> clearAuthToken() async {
    await _delete(_keyAuthToken);
    await _delete(_keyAuthTokenExpiresAt);
  }

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
}
