// lib/services/settings_service.dart
/// Service for managing app settings and user credentials
///
/// Uses flutter_secure_storage for encrypted storage of sensitive data

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Keys for stored values
  static const String _keysurveyorId = 'surveyor_id';
  static const String _keyFtpHost = 'ftp_host';
  static const String _keyFtpUsername = 'ftp_username';
  static const String _keyFtpPassword = 'ftp_password';
  static const String _keyActiveSurvey = 'active_survey';

  // New HTTP/API keys
  static const String _keyProjectCode = 'project_code';
  static const String _keyApiUsername = 'api_username';
  static const String _keyApiPassword = 'api_password';
  static const String _keyAuthToken = 'auth_token';

  // Getters for settings
  Future<String?> get surveyorId async {
    return await _storage.read(key: _keysurveyorId);
  }

  Future<String?> get ftpHost async {
    return await _storage.read(key: _keyFtpHost);
  }

  Future<String?> get ftpUsername async {
    return await _storage.read(key: _keyFtpUsername);
  }

  Future<String?> get ftpPassword async {
    return await _storage.read(key: _keyFtpPassword);
  }

  Future<String?> get activeSurvey async {
    return await _storage.read(key: _keyActiveSurvey);
  }

  // New API getters
  Future<String?> get projectCode async {
    return await _storage.read(key: _keyProjectCode);
  }

  Future<String?> get apiUsername async {
    return await _storage.read(key: _keyApiUsername);
  }

  Future<String?> get apiPassword async {
    return await _storage.read(key: _keyApiPassword);
  }

  Future<String?> get authToken async {
    return await _storage.read(key: _keyAuthToken);
  }

  // Setters for settings
  Future<void> setSurveyorId(String value) async {
    await _storage.write(key: _keysurveyorId, value: value);
  }

  Future<void> setFtpHost(String value) async {
    await _storage.write(key: _keyFtpHost, value: value);
  }

  Future<void> setFtpUsername(String value) async {
    await _storage.write(key: _keyFtpUsername, value: value);
  }

  Future<void> setFtpPassword(String value) async {
    await _storage.write(key: _keyFtpPassword, value: value);
  }

  Future<void> setActiveSurvey(String value) async {
    await _storage.write(key: _keyActiveSurvey, value: value);
  }

  // New API setters
  Future<void> setProjectCode(String value) async {
    await _storage.write(key: _keyProjectCode, value: value);
  }

  Future<void> setApiUsername(String value) async {
    await _storage.write(key: _keyApiUsername, value: value);
  }

  Future<void> setApiPassword(String value) async {
    await _storage.write(key: _keyApiPassword, value: value);
  }

  Future<void> setAuthToken(String value) async {
    await _storage.write(key: _keyAuthToken, value: value);
  }

  // Bulk save all settings (legacy - for FTP upload only now)
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

  // Bulk save API settings
  Future<void> saveApiSettings({
    required String surveyorId,
    required String projectCode,
    required String apiUsername,
    required String apiPassword,
    String? activeSurvey,
  }) async {
    await setSurveyorId(surveyorId);
    await setProjectCode(projectCode);
    await setApiUsername(apiUsername);
    await setApiPassword(apiPassword);
    if (activeSurvey != null) {
      await setActiveSurvey(activeSurvey);
    }
  }

  // Check if settings are configured
  Future<bool> isConfigured() async {
    final surveyorId = await this.surveyorId;
    return surveyorId != null && surveyorId.isNotEmpty;
  }

  // Clear all settings
  Future<void> clearAllSettings() async {
    await _storage.deleteAll();
  }

  // Survey-specific credentials
  Future<String?> getSurveyUsername(String surveyId) async {
    return await _storage.read(key: 'survey_${surveyId}_username');
  }

  Future<String?> getSurveyPassword(String surveyId) async {
    return await _storage.read(key: 'survey_${surveyId}_password');
  }

  Future<void> setSurveyCredentials(String surveyId, String username, String password) async {
    await _storage.write(key: 'survey_${surveyId}_username', value: username);
    await _storage.write(key: 'survey_${surveyId}_password', value: password);
  }

  /// Get credentials for a survey - returns survey-specific if available, otherwise falls back to global
  /// NOTE: This is now only used for FTP uploads. Downloads use getApiCredentials()
  Future<Map<String, String>?> getCredentialsForSurvey(String surveyId) async {
    // Try survey-specific first
    final surveyUsername = await getSurveyUsername(surveyId);
    final surveyPassword = await getSurveyPassword(surveyId);

    if (surveyUsername != null && surveyPassword != null) {
      return {'username': surveyUsername, 'password': surveyPassword};
    }

    // Fall back to FTP credentials (for upload)
    final globalUsername = await ftpUsername;
    final globalPassword = await ftpPassword;

    if (globalUsername != null && globalPassword != null) {
      return {'username': globalUsername, 'password': globalPassword};
    }

    return null;
  }

  /// Get API credentials for download operations
  Future<Map<String, String>?> getApiCredentials() async {
    final username = await apiUsername;
    final password = await apiPassword;
    final projCode = await projectCode;

    if (username != null && password != null && projCode != null) {
      return {
        'username': username,
        'password': password,
        'projectCode': projCode,
      };
    }

    return null;
  }
}
