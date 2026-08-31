import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/services/survey_config_service.dart';

/// Redirects path_provider's application-support lookup to a temp
/// directory, so SurveyConfigService's real file-system code can run
/// against a throwaway sandbox instead of the host's real app-support
/// folder.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.basePath);
  final String basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('survey_config_service_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('getManifestForFolder', () {
    Future<Directory> surveysDir() async =>
        Directory(p.join(tempDir.path, AppConfig.storageFolder, 'surveys'));

    Future<void> writeManifest(
      String folderName, {
      required String surveyId,
      required String surveyName,
    }) async {
      final dir = Directory(p.join((await surveysDir()).path, folderName));
      await dir.create(recursive: true);
      final manifest = File(p.join(dir.path, 'survey_manifest.gistx'));
      await manifest.writeAsString(
        json.encode({'surveyId': surveyId, 'surveyName': surveyName}),
      );
    }

    test(
        'returns the manifest by folder name even when the manifest surveyName differs',
        () async {
      // Exactly the mismatch that broke credential association: the zip's
      // filename stem ("avert_ug_2026_08_31") never matches the manifest's
      // human-readable surveyName ("AVERT UG 2026-08-31").
      await writeManifest(
        'avert_ug_2026_08_31',
        surveyId: 'avert_ug_2026_08_31',
        surveyName: 'AVERT UG 2026-08-31',
      );

      final manifest = await SurveyConfigService()
          .getManifestForFolder('avert_ug_2026_08_31');

      expect(manifest, isNotNull);
      expect(manifest!['surveyId'], 'avert_ug_2026_08_31');
      expect(manifest['surveyName'], 'AVERT UG 2026-08-31');
    });

    test('returns null for a folder that does not exist', () async {
      final manifest =
          await SurveyConfigService().getManifestForFolder('nonexistent');

      expect(manifest, isNull);
    });
  });
}
