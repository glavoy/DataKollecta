// Diagnostic-only end-to-end test simulating exactly what
// _downloadSurvey/_associateCredentialsWithDownloadedSurvey/_uploadData do
// on a real device, using the real SurveyConfigService/SettingsService
// code (only path_provider and shared_preferences are faked). Written to
// track down a reported live bug: after deleting and re-downloading
// surveys under two different logins, upload always used the "last"
// credentials regardless of which survey was active.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/services/settings_service.dart';
import 'package:datakollecta/services/survey_config_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.basePath);
  final String basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

/// Builds a zip byte payload containing a survey_manifest.gistx with the
/// given surveyId/surveyName/databaseName -- same shape DataKollecta-
/// SurveyGen produces.
List<int> _buildZip({
  required String surveyId,
  required String surveyName,
  required String databaseName,
}) {
  final archive = Archive();
  final manifest = json.encode({
    'surveyId': surveyId,
    'surveyName': surveyName,
    'databaseName': databaseName,
    'xmlFiles': <String>[],
    'crfs': <Map<String, dynamic>>[],
  });
  final bytes = utf8.encode(manifest);
  archive.addFile(ArchiveFile('survey_manifest.gistx', bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}

/// Mirrors exactly what SyncScreen._downloadSurvey does after a successful
/// FTP download: write the zip to `zips/<filename>`, then run the same
/// association step.
Future<void> _simulateDownload({
  required String zipsDirPath,
  required String filename,
  required List<int> zipBytes,
  required SettingsService settings,
  required SurveyConfigService surveyConfig,
  required String username,
  required String password,
}) async {
  final zipFile = File(p.join(zipsDirPath, filename));
  await zipFile.writeAsBytes(zipBytes);

  // -- _associateCredentialsWithDownloadedSurvey, reproduced verbatim --
  await surveyConfig.initializeSurveys();
  final surveyFolderName =
      filename.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
  final manifest = await surveyConfig.getManifestForFolder(surveyFolderName);
  final surveyId = manifest?['surveyId'] as String?;
  expect(surveyId, isNotNull,
      reason: 'getManifestForFolder failed to resolve a surveyId for '
          '$surveyFolderName -- this is the actual bug if it fails here.');

  await settings.setSurveyCredentials(surveyId!, username, password);
  final currentGlobalSurveyorId = await settings.surveyorId;
  if (currentGlobalSurveyorId != null && currentGlobalSurveyorId.isNotEmpty) {
    await settings.setSurveyorIdForSurvey(surveyId, currentGlobalSurveyorId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String zipsDirPath;

  setUp(() async {
    tempDir =
        Directory.systemTemp.createTempSync('survey_download_e2e_test');
    zipsDirPath =
        p.join(tempDir.path, AppConfig.storageFolder, 'zips');
    await Directory(zipsDirPath).create(recursive: true);
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
      'two surveys downloaded under two different logins each upload with their own credentials/Surveyor ID',
      () async {
    final settings = SettingsService();
    final surveyConfig = SurveyConfigService();

    // 1. Configure Surveyor ID 27 + credentials A, "download" Survey 1.
    await settings.setSurveyorId('27');
    await _simulateDownload(
      zipsDirPath: zipsDirPath,
      filename: 'survey_one.zip',
      zipBytes: _buildZip(
        surveyId: 'survey_one_id',
        surveyName: 'Survey One',
        databaseName: 'survey_one.sqlite',
      ),
      settings: settings,
      surveyConfig: surveyConfig,
      username: 'userA',
      password: 'passA',
    );

    // 2. Configure Surveyor ID 58 + credentials B, "download" Survey 2.
    await settings.setSurveyorId('58');
    await _simulateDownload(
      zipsDirPath: zipsDirPath,
      filename: 'survey_two.zip',
      zipBytes: _buildZip(
        surveyId: 'survey_two_id',
        surveyName: 'Survey Two',
        databaseName: 'survey_two.sqlite',
      ),
      settings: settings,
      surveyConfig: surveyConfig,
      username: 'userB',
      password: 'passB',
    );

    // 3. Switch the active survey back to Survey One and resolve exactly
    // what _uploadData() would resolve.
    await settings.setActiveSurvey('Survey One');
    final activeName1 = await settings.activeSurvey;
    final surveyId1 = await surveyConfig.getSurveyId(activeName1!);
    expect(surveyId1, 'survey_one_id');

    final creds1 = await settings.getCredentialsForSurvey(surveyId1!);
    final surveyorId1 = await settings.getSurveyorIdOrGlobal(surveyId1);

    expect(creds1?['username'], 'userA',
        reason: 'Survey One should upload with credentials A, not '
            'whatever is currently global (B).');
    expect(creds1?['password'], 'passA');
    expect(surveyorId1, '27',
        reason: 'Survey One should upload with Surveyor ID 27, not the '
            'currently global 58.');

    // 4. Switch to Survey Two, confirm it resolves to B/58.
    await settings.setActiveSurvey('Survey Two');
    final activeName2 = await settings.activeSurvey;
    final surveyId2 = await surveyConfig.getSurveyId(activeName2!);
    expect(surveyId2, 'survey_two_id');

    final creds2 = await settings.getCredentialsForSurvey(surveyId2!);
    final surveyorId2 = await settings.getSurveyorIdOrGlobal(surveyId2);

    expect(creds2?['username'], 'userB');
    expect(creds2?['password'], 'passB');
    expect(surveyorId2, '58');
  });
}
