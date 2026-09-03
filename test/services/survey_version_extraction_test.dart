// The extraction-time databaseName guard, which is what decides whether a new
// VERSION of a survey can be installed on a device that already has an earlier
// one.
//
// A version deliberately reuses its predecessor's databaseName -- that shared
// SQLite file is exactly what keeps the data together and the subject-ID
// counter continuous -- while taking a new surveyId so it lands in a new
// extraction folder and its updated XML is actually read. The guard must let
// that through, and must still refuse the case it exists for: two DIFFERENT
// projects' surveys pointed at one physical database.
//
// DataKollecta-only, because the guard is: GiSTX has no multi-project concept
// and so has no cross-project collision to detect. Under a GiSTX build these
// tests are skipped rather than asserting the opposite behaviour, since the
// suite must pass in both.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/services/survey_config_service.dart';
import 'package:datakollecta/services/sync/project_sessions.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.basePath);
  final String basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

List<int> _buildZip({
  required String surveyId,
  required String databaseName,
}) {
  final archive = Archive();
  final manifest = json.encode({
    'surveyId': surveyId,
    'surveyName': surveyId,
    'databaseName': databaseName,
    'xmlFiles': <String>[],
    'crfs': <Map<String, dynamic>>[],
  });
  final bytes = utf8.encode(manifest);
  archive.addFile(ArchiveFile('survey_manifest.gistx', bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory zipsDir;
  late Directory surveysDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('survey_version_extraction');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});

    zipsDir = Directory(p.join(tempDir.path, AppConfig.storageFolder, 'zips'));
    surveysDir =
        Directory(p.join(tempDir.path, AppConfig.storageFolder, 'surveys'));
    await zipsDir.create(recursive: true);
    await surveysDir.create(recursive: true);

    // ProjectSessionsRepository.shared is a singleton over SettingsService, so
    // each test has to clear it explicitly -- setMockInitialValues alone does
    // not reset what a previous test wrote through it.
    await ProjectSessionsRepository.shared
        .update((_) => ProjectSessionsDocument.empty);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<void> install(String surveyId, String databaseName) async {
    await File(p.join(zipsDir.path, '$surveyId.zip'))
        .writeAsBytes(_buildZip(surveyId: surveyId, databaseName: databaseName));
    await SurveyConfigService().initializeSurveys();
  }

  bool extracted(String surveyId) =>
      Directory(p.join(surveysDir.path, surveyId)).existsSync();

  test('a new version installs alongside the old one, sharing its database',
      () async {
    await ProjectSessionsRepository.shared.update((doc) => doc
        .withAssociation('prism_css_v1', 'prism')
        .withAssociation('prism_css_v2', 'prism'));

    await install('prism_css_v1', 'prism_css.sqlite');
    await install('prism_css_v2', 'prism_css.sqlite');

    // Both folders present: the phone reads v2's XML while both point at the
    // one SQLite file, which is what carries the data and the ID counter over.
    expect(extracted('prism_css_v1'), isTrue);
    expect(extracted('prism_css_v2'), isTrue,
        reason: 'a new version reusing its predecessor\'s databaseName within '
            'the same project must extract -- refusing it is what made '
            '"add a question to a deployed survey" impossible');
  }, skip: !AppConfig.isDataKollecta);

  test('a different project\'s survey may not claim an in-use database',
      () async {
    await ProjectSessionsRepository.shared.update((doc) => doc
        .withAssociation('prism_css_v1', 'prism')
        .withAssociation('other_study', 'other'));

    await install('prism_css_v1', 'prism_css.sqlite');
    await install('other_study', 'prism_css.sqlite');

    expect(extracted('prism_css_v1'), isTrue);
    expect(extracted('other_study'), isFalse,
        reason: 'two projects sharing one physical database means colliding '
            'tables and a shared subject-ID counter');
  }, skip: !AppConfig.isDataKollecta);

  test('a side-loaded zip with no known project is allowed through', () async {
    // No associations recorded at all -- a zip copied straight into zips/, or
    // one installed before project tracking existed. Matches what
    // HttpSyncBackend._guardAgainstCollision does on the download path; the
    // two guards disagreeing would silently drop a zip that path accepts.
    await install('prism_css_v1', 'prism_css.sqlite');
    await install('prism_css_v2', 'prism_css.sqlite');

    expect(extracted('prism_css_v1'), isTrue);
    expect(extracted('prism_css_v2'), isTrue);
  }, skip: !AppConfig.isDataKollecta);
}
