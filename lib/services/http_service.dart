import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Model for survey metadata from API response
class SurveyMetadata {
  final String name;
  final String downloadUrl;
  final String surveyPackageId;

  SurveyMetadata({
    required this.name,
    required this.downloadUrl,
    required this.surveyPackageId,
  });

  factory SurveyMetadata.fromJson(Map<String, dynamic> json) {
    return SurveyMetadata(
      name: json['name'] as String,
      downloadUrl: json['download_url'] as String,
      surveyPackageId: json['id'] as String,
    );
  }
}

/// Service for HTTP-based survey operations (replacing FTP)
class HttpService {
  // Static API endpoint
  static const String _apiEndpoint =
      'https://qetzeqyuuiposzseqwvb.supabase.co/functions/v1/app-login';
  // Supabase anon key - required for Edge Functions
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFldHplcXl1dWlwb3N6c2Vxd3ZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMzYyODYsImV4cCI6MjA4MjcxMjI4Nn0.RqIPiYMUr46tJhgPTgwPwWWbAPymr_VGszuMsHbCTmE';

  String? _authToken;

  /// Authenticate with the API and get survey list
  /// Returns the auth token and list of available surveys
  Future<({String token, List<SurveyMetadata> surveys})> authenticate(
      String username,
      String password,
      String projectCode, {
      required String deviceId,
      required String deviceInfo,
      }) async {
    try {
      // Make authentication request
      final requestBody = {
        'project_code': projectCode,
        'username': username,
        'password': password,
        'device_id': deviceId,
        'device_info': deviceInfo,
      };

      debugPrint('[HttpService] Sending request to: $_apiEndpoint');
      debugPrint('[HttpService] Request body: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_supabaseAnonKey',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[HttpService] Response status: ${response.statusCode}');
      debugPrint('[HttpService] Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
            'Authentication failed: ${response.statusCode} - ${response.body}');
      }

      final responseData = json.decode(response.body) as Map<String, dynamic>;

      // Extract token (adjust the key based on your API response)
      final token = responseData['token'] as String?;
      if (token == null) {
        throw Exception('No token received from authentication');
      }

      _authToken = token;

      // Extract surveys list
      final surveysJson = responseData['surveys'] as List<dynamic>?;
      if (surveysJson == null) {
        throw Exception('No surveys list in response');
      }

      final surveys = surveysJson
          .map((s) => SurveyMetadata.fromJson(s as Map<String, dynamic>))
          .toList();

      debugPrint(
          '[HttpService] Authentication successful. Found ${surveys.length} surveys.');

      return (token: token, surveys: surveys);
    } catch (e) {
      debugPrint('[HttpService] Authentication failed: $e');
      rethrow;
    }
  }

  /// Download a survey zip file using the signed URL
  Future<File?> downloadSurveyZip(String downloadUrl, String surveyName) async {
    try {
      debugPrint('[HttpService] Downloading survey: $surveyName');
      debugPrint('[HttpService] URL: $downloadUrl');

      // Make HTTP GET request to download the file
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode != 200) {
        throw Exception(
            'Download failed: ${response.statusCode} - ${response.reasonPhrase}');
      }

      // Get local zips directory
      Directory baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory() ??
            await getApplicationSupportDirectory();
      } else if (Platform.isWindows) {
        // Windows: Use LOCALAPPDATA for AppData\Local
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null) {
          baseDir = Directory(localAppData);
        } else {
          baseDir = await getApplicationSupportDirectory();
        }
      } else {
        // Linux/Mac
        baseDir = await getApplicationSupportDirectory();
      }

      final zipsDir = Directory(p.join(baseDir.path, 'DataKollecta', 'zips'));
      if (!await zipsDir.exists()) {
        await zipsDir.create(recursive: true);
      }

      // Extract original filename from URL and strip timestamp prefix
      String filename;
      try {
        final uri = Uri.parse(downloadUrl);
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          filename = pathSegments.last;
          
          // Strip timestamp prefix (e.g., "1768751055830_survey.zip" -> "survey.zip")
          final underscoreIndex = filename.indexOf('_');
          if (underscoreIndex != -1) {
            final prefix = filename.substring(0, underscoreIndex);
            // Check if the prefix is likely a timestamp (numeric and long)
            if (RegExp(r'^\d+$').hasMatch(prefix)) {
              filename = filename.substring(underscoreIndex + 1);
            }
          }
        } else {
          filename = '$surveyName.zip';
        }
      } catch (e) {
        filename = '$surveyName.zip';
      }

      final localFile = File(p.join(zipsDir.path, filename));

      // Write the downloaded bytes to file
      await localFile.writeAsBytes(response.bodyBytes);

      debugPrint('[HttpService] Download complete: ${localFile.path}');
      return localFile;
    } catch (e) {
      debugPrint('[HttpService] Download failed: $e');
      return null;
    }
  }

  /// Get the current auth token
  String? get authToken => _authToken;

  /// Clear authentication state
  void clearAuth() {
    _authToken = null;
  }
}
