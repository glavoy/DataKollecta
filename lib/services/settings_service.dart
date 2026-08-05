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

  // Getters for settings
  Future<String?> get surveyorId async => _read(_keysurveyorId);
  Future<String?> get ftpHost async => _read(_keyFtpHost);
  Future<String?> get ftpUsername async => _read(_keyFtpUsername);
  Future<String?> get ftpPassword async => _read(_keyFtpPassword);
  Future<String?> get activeSurvey async => _read(_keyActiveSurvey);

  // Setters for settings
  Future<void> setSurveyorId(String value) => _write(_keysurveyorId, value);
  Future<void> setFtpHost(String value) => _write(_keyFtpHost, value);
  Future<void> setFtpUsername(String value) => _write(_keyFtpUsername, value);
  Future<void> setFtpPassword(String value) => _write(_keyFtpPassword, value);
  Future<void> setActiveSurvey(String value) => _write(_keyActiveSurvey, value);

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
