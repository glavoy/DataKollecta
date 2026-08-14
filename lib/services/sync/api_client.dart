import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import 'sync_backend.dart';

/// One authenticated session against the DataKollecta Supabase backend: the
/// bearer token, its expiry, and the surveys the login response listed
/// (each carrying a signed download URL good for 24 hours).
class ApiSession {
  final String token;
  final DateTime expiresAt;
  final List<ApiSurvey> surveys;

  const ApiSession({
    required this.token,
    required this.expiresAt,
    required this.surveys,
  });
}

class ApiSurvey {
  final String id;
  final String name;
  final String? downloadUrl;

  const ApiSurvey({required this.id, required this.name, this.downloadUrl});
}

class ApiSyncResult {
  final List<String> synced;
  final List<ApiSyncFailure> failed;
  final List<String> formchangesSynced;
  final List<ApiSyncFailure> formchangesFailed;

  const ApiSyncResult({
    required this.synced,
    required this.failed,
    required this.formchangesSynced,
    required this.formchangesFailed,
  });
}

class ApiSyncFailure {
  final String id;
  final String error;
  const ApiSyncFailure({required this.id, required this.error});
}

/// Talks to the two deployed Supabase edge functions -- app-login and
/// app-sync -- plus plain signed-URL downloads.
///
/// Every request/response is logged at method/host/status/count granularity
/// only, never body content: defects #1 and #2 in the DataKollecta
/// reference branch logged the full request body (including the plaintext
/// password) and the full response body (including every synced record's
/// data) on every call.
class ApiClient {
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qetzeqyuuiposzseqwvb.supabase.co',
  );

  // The anon key is designed to be public -- both edge functions immediately
  // switch to a service-role client server-side, so this is a deployment
  // convenience (a future staging project becomes a build flag), not a
  // secret being exposed.
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFldHplcXl1dWlwb3N6c2Vxd3ZiIiwicm9sZ'
        'SI6ImFub24iLCJpYXQiOjE3NjcxMzYyODYsImV4cCI6MjA4MjcxMjI4Nn0.'
        'RqIPiYMUr46tJhgPTgwPwWWbAPymr_VGszuMsHbCTmE',
  );

  final http.Client _client;
  final Duration requestTimeout;
  final Duration downloadTimeout;

  ApiClient({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 2),
  }) : _client = client ?? http.Client();

  Uri get _loginUri => Uri.parse('$_supabaseUrl/functions/v1/app-login');
  Uri get _syncUri => Uri.parse('$_supabaseUrl/functions/v1/app-sync');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_supabaseAnonKey',
      };

  Future<ApiSession> login({
    required String projectCode,
    required String username,
    required String password,
    required String deviceId,
    required Map<String, dynamic> deviceInfo,
  }) async {
    final response = await _post(
      _loginUri,
      {
        'project_code': projectCode,
        'username': username,
        'password': password,
        'device_id': deviceId,
        'device_info': deviceInfo,
      },
      logLabel: 'login',
    );

    if (response.statusCode == 401 || response.statusCode == 404) {
      throw SyncAuthException(
          _errorMessage(response) ?? 'Invalid project code, username, or password');
    }

    final body = _decodeBody(response, logLabel: 'login');
    if (response.statusCode != 200 || body == null) {
      throw SyncTransferException('Login failed (${response.statusCode})');
    }

    final token = body['token'] as String?;
    final expiresAtStr = body['expires_at'] as String?;
    if (token == null || expiresAtStr == null) {
      throw const SyncTransferException(
          'Login response was missing token/expires_at');
    }

    final surveysJson = body['surveys'] as List<dynamic>? ?? const [];
    final surveys = surveysJson.map((raw) {
      final map = raw as Map<String, dynamic>;
      final id = map['id'] as String;
      return ApiSurvey(
        id: id,
        name: (map['name'] as String?) ?? id,
        downloadUrl: map['download_url'] as String?,
      );
    }).toList();

    return ApiSession(
      token: token,
      expiresAt: DateTime.parse(expiresAtStr),
      surveys: surveys,
    );
  }

  Future<ApiSyncResult> postSync({
    required String token,
    required List<Map<String, dynamic>> submissions,
    required List<Map<String, dynamic>> formchanges,
  }) async {
    final payload = <String, dynamic>{
      'token': token,
      'submissions': submissions,
      if (formchanges.isNotEmpty) 'formchanges': formchanges,
    };

    final response = await _post(_syncUri, payload, logLabel: 'sync');

    if (response.statusCode == 401) {
      throw SyncAuthException(_errorMessage(response) ?? 'Session expired');
    }

    final body = _decodeBody(response, logLabel: 'sync');
    if (response.statusCode != 200 || body == null) {
      throw SyncTransferException('Sync failed (${response.statusCode})');
    }

    List<String> ids(dynamic raw) =>
        (raw as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

    List<ApiSyncFailure> failures(dynamic raw) =>
        (raw as List<dynamic>? ?? const []).map((raw) {
          final map = raw as Map<String, dynamic>;
          return ApiSyncFailure(
            id: map['id']?.toString() ?? '',
            error: map['error']?.toString() ?? 'Unknown error',
          );
        }).toList();

    return ApiSyncResult(
      synced: ids(body['synced']),
      failed: failures(body['failed']),
      formchangesSynced: ids(body['formchanges_synced']),
      formchangesFailed: failures(body['formchanges_failed']),
    );
  }

  /// Downloads a survey package from a signed URL (as returned by [login])
  /// into this product's zips folder, mirroring how FtpService resolves and
  /// writes into the same folder for the FTP flavor.
  Future<File> downloadSurveyZip(String downloadUrl, String filename) async {
    debugPrint('[ApiClient] GET download (signed URL)');
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(downloadUrl)).timeout(downloadTimeout);
    } on TimeoutException {
      throw SyncConnectionException(
          'Download timed out after $downloadTimeout');
    } catch (e) {
      throw SyncConnectionException('Could not reach server: $e');
    }
    debugPrint(
        '[ApiClient] download <- ${response.statusCode}, ${response.bodyBytes.length} bytes');

    if (response.statusCode != 200) {
      throw SyncTransferException('Download failed (${response.statusCode})');
    }

    final zipsDir = await _getZipsDirectory();
    final localFile = File(p.join(zipsDir.path, filename));
    await localFile.writeAsBytes(response.bodyBytes);
    return localFile;
  }

  Future<http.Response> _post(Uri uri, Map<String, dynamic> payload,
      {required String logLabel}) async {
    debugPrint('[ApiClient] POST $logLabel -> ${uri.host}${uri.path}');
    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: _headers, body: json.encode(payload))
          .timeout(requestTimeout);
    } on TimeoutException {
      throw SyncConnectionException('$logLabel timed out after $requestTimeout');
    } catch (e) {
      throw SyncConnectionException('Could not reach server: $e');
    }
    debugPrint('[ApiClient] $logLabel <- ${response.statusCode}');
    return response;
  }

  Map<String, dynamic>? _decodeBody(http.Response response,
      {required String logLabel}) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ApiClient] $logLabel response was not valid JSON');
      return null;
    }
  }

  String? _errorMessage(http.Response response) {
    final body = _decodeBody(response, logLabel: 'error');
    return body?['error'] as String?;
  }

  /// Duplicates the platform-base-dir resolution already present in
  /// FtpService/DbService/SurveyConfigService (each keeps its own copy
  /// today) rather than introducing a new shared helper unprompted.
  Future<Directory> _getZipsDirectory() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      baseDir = localAppData != null
          ? Directory(localAppData)
          : await getApplicationSupportDirectory();
    } else {
      baseDir = await getApplicationSupportDirectory();
    }
    final zipsDir =
        Directory(p.join(baseDir.path, AppConfig.storageFolder, 'zips'));
    if (!await zipsDir.exists()) {
      await zipsDir.create(recursive: true);
    }
    return zipsDir;
  }

  void close() => _client.close();
}
