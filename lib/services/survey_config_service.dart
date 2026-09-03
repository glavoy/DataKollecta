// lib/services/survey_config_service.dart
/// Service for loading and managing survey configurations
///
/// Reads survey manifests and provides helper methods for accessing
/// survey-specific resources like XML files and metadata.
///
/// Updated to support dynamic loading from ApplicationDocumentsDirectory
/// and auto-extraction of bundled zip files.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import 'settings_service.dart';
import 'sync/project_sessions.dart';

class SurveyConfigService {
  static final SurveyConfigService _instance = SurveyConfigService._internal();
  factory SurveyConfigService() => _instance;
  SurveyConfigService._internal();

  final _settingsService = SettingsService();
  final ProjectSessionsRepository _sessionsRepo = ProjectSessionsRepository.shared;

  // Cache for loaded survey manifests
  final Map<String, Map<String, dynamic>> _manifestCache = {};

  /// Initialize surveys by extracting zips from local storage
  Future<void> initializeSurveys() async {
    try {
      final baseDir = await _getBaseDir();
      final zipsDir = Directory(p.join(baseDir.path, AppConfig.storageFolder, 'zips'));
      final surveysDir = Directory(p.join(baseDir.path, AppConfig.storageFolder, 'surveys'));

      if (!await zipsDir.exists()) {
        await zipsDir.create(recursive: true);
      }
      if (!await surveysDir.exists()) {
        await surveysDir.create(recursive: true);
      }

      // Scan for zip files in the zips directory
      final List<FileSystemEntity> entities = await zipsDir.list().toList();
      final zipFiles = entities.where((e) => e.path.endsWith('.zip')).toList();

      debugPrint(
          '[SurveyConfig] Found ${zipFiles.length} zips in ${zipsDir.path}');

      for (final entity in zipFiles) {
        if (entity is! File) continue;

        final zipPath = entity.path;
        final zipName = p.basename(zipPath);
        final surveyFolderName = zipName.replaceAll('.zip', '');
        final targetDir = Directory(p.join(surveysDir.path, surveyFolderName));

        // Only extract if target directory doesn't exist
        if (!await targetDir.exists()) {
          try {
            final zipData = await entity.readAsBytes();
            final archive = ZipDecoder().decodeBytes(zipData);

            // Peek the manifest before writing anything, so a databaseName
            // collision with an already-installed survey belonging to a
            // DIFFERENT PROJECT can be refused before this zip ever becomes
            // a folder on disk. This matters for DataKollecta because a zip
            // can arrive here via side-loading (copied straight into the
            // zips/ folder) rather than through
            // HttpSyncBackend.downloadSurvey, which performs the equivalent
            // guard before download instead.
            //
            // What is NOT a collision: a new surveyId onto an existing
            // databaseName within the same project. That is precisely how a
            // survey is versioned -- new surveyId per release (a new
            // extraction folder, so the updated XML is actually read),
            // unchanged databaseName, so DbService opens the existing SQLite
            // file, ALTER TABLEs the new questions in, and the subject-ID
            // counter carries on. Refusing it made "add one question to a
            // deployed survey" impossible on DataKollecta, and had already
            // done real damage on the GiSTX side: confirmed live on
            // 2026-08-31, a new AVERT version was refused forever with
            // "databaseName ... already used by survey ..." because an
            // earlier version was installed under the same databaseName by
            // design. That is what the isDataKollecta gate below was added
            // for; this narrows the DataKollecta half to the same rule
            // rather than exempting GiSTX from a rule that was too broad for
            // both.
            //
            // Still DataKollecta-only, because "which project owns this
            // survey" only exists there -- GiSTX has no multi-project
            // concept, so it has no cross-project collision to detect.
            //
            // Deliberately matches HttpSyncBackend._guardAgainstCollision,
            // the equivalent guard on the download path: refuse only a
            // genuine cross-project collision, and let an owner with no
            // known project binding through (a side-loaded zip, or one
            // installed before this tracking existed -- see that method's
            // comment). Both are real device-global keys, so the two guards
            // disagreeing would mean a zip the download path accepts is
            // silently dropped at extraction.
            if (AppConfig.isDataKollecta) {
              final manifestEntry = _findManifestEntry(archive);
              if (manifestEntry != null) {
                final manifest = json.decode(
                        utf8.decode(manifestEntry.content as List<int>))
                    as Map<String, dynamic>;
                final zipSurveyId = manifest['surveyId'] as String?;
                final databaseName = manifest['databaseName'] as String?;
                if (zipSurveyId != null && databaseName != null) {
                  final owner =
                      await findSurveyIdForDatabaseName(databaseName);
                  if (owner != null && owner != zipSurveyId) {
                    final doc = await _sessionsRepo.load();
                    final ownerProject = doc.projectFor(owner);
                    final incomingProject = doc.projectFor(zipSurveyId);
                    if (ownerProject != null &&
                        incomingProject != null &&
                        ownerProject != incomingProject) {
                      debugPrint(
                          '[SurveyConfig] Refusing to extract $zipName: databaseName '
                          '"$databaseName" is used by survey "$owner" in project '
                          '"$ownerProject", but this zip belongs to project '
                          '"$incomingProject".');
                      continue;
                    }
                  }
                }
              }
            }

            debugPrint(
                '[SurveyConfig] Extracting $zipName to ${targetDir.path}');
            for (final file in archive) {
              final filename = file.name;
              if (file.isFile) {
                if (filename.contains('__MACOSX') || filename.startsWith('.')) {
                  continue;
                }

                final data = file.content as List<int>;
                final outFile = File(p.join(targetDir.path, filename));
                await outFile.create(recursive: true);
                await outFile.writeAsBytes(data);
              } else {
                if (!filename.contains('__MACOSX') &&
                    !filename.startsWith('.')) {
                  await Directory(p.join(targetDir.path, filename))
                      .create(recursive: true);
                }
              }
            }
          } catch (e) {
            debugPrint('[SurveyConfig] Failed to extract $zipName: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[SurveyConfig] Error initializing surveys: $e');
    }
  }

  ArchiveFile? _findManifestEntry(Archive archive) {
    for (final file in archive.files) {
      if (file.isFile && p.basename(file.name) == 'survey_manifest.gistx') {
        return file;
      }
    }
    return null;
  }

  /// The already-installed survey (if any) whose manifest declares
  /// [databaseName] -- the same physical SQLite file two different
  /// surveyIds would otherwise silently share. Used to refuse extracting
  /// or downloading a second survey onto the same database.
  Future<String?> findSurveyIdForDatabaseName(String databaseName) async {
    final surveysDir = await getSurveysDirectory();
    if (!await surveysDir.exists()) return null;

    final entities = await surveysDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        try {
          final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
          final file = File(manifestPath);
          if (await file.exists()) {
            final manifest = await _loadManifestFromFile(file);
            if (manifest['databaseName'] == databaseName) {
              return manifest['surveyId'] as String?;
            }
          }
        } catch (e) {
          // ignore
        }
      }
    }
    return null;
  }

  /// Reads a survey's manifest directly from its known extraction folder name
  /// (the downloaded zip's own filename stem) -- unlike [getSurveyId], this
  /// never depends on matching the human-readable manifest surveyName, so it
  /// works even when the zip's filename and the manifest's display name
  /// differ (the normal case under DataKollecta-SurveyGen's naming
  /// convention).
  Future<Map<String, dynamic>?> getManifestForFolder(String folderName) async {
    final surveysDir = await getSurveysDirectory();
    final manifestFile =
        File(p.join(surveysDir.path, folderName, 'survey_manifest.gistx'));
    if (!await manifestFile.exists()) return null;
    return _loadManifestFromFile(manifestFile);
  }

  /// Delete a survey (extracted folder and source zip)
  Future<void> deleteSurvey(String surveyName) async {
    try {
      final surveysDir = await getSurveysDirectory();
      final baseDir = await _getBaseDir();
      final zipsDir = Directory(p.join(baseDir.path, AppConfig.storageFolder, 'zips'));

      // Find the survey folder by name
      final entities = await surveysDir.list().toList();
      Directory? surveyFolder;
      String? surveyId;

      for (final entity in entities) {
        if (entity is Directory) {
          final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
          final file = File(manifestPath);
          if (await file.exists()) {
            final manifest = await _loadManifestFromFile(file);
            if (manifest['surveyName'] == surveyName) {
              surveyFolder = entity;
              surveyId = manifest['surveyId'] as String?;
              break;
            }
          }
        }
      }

      if (surveyFolder != null) {
        // 1. Delete extracted folder
        debugPrint(
            '[SurveyConfig] Deleting survey folder: ${surveyFolder.path}');
        await surveyFolder.delete(recursive: true);

        // 2. Delete source zip if it exists
        // We assume zip name matches folder name (which matches surveyId usually, or at least the folder name)
        // The folder name comes from the zip name during extraction.
        final folderName = p.basename(surveyFolder.path);
        final zipPath = p.join(zipsDir.path, '$folderName.zip');
        final zipFile = File(zipPath);

        if (await zipFile.exists()) {
          debugPrint('[SurveyConfig] Deleting source zip: $zipPath');
          await zipFile.delete();
        }

        // Clear cache
        _manifestCache.clear();

        // Clear its project association -- fixing, rather than replicating,
        // the missing-cleanup gap in the old per-survey FTP credential
        // pattern (getSurveyUsername/setSurveyCredentials never had a
        // delete). Without this, a re-added survey reusing the same
        // surveyId would spuriously trip the collision guard against its
        // own stale binding.
        if (surveyId != null) {
          await _sessionsRepo.update((doc) => doc.withoutAssociation(surveyId!));
        }

        // If this was the active survey, clear it from settings
        final activeSurvey = await _settingsService.activeSurvey;
        if (activeSurvey == surveyName) {
          await _settingsService.setActiveSurvey('');
        }
      }
    } catch (e) {
      debugPrint('[SurveyConfig] Error deleting survey: $e');
      rethrow;
    }
  }

  Future<Directory> _getBaseDir() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      // Windows: Use LOCALAPPDATA for AppData\Local
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        return Directory(localAppData);
      } else {
        return await getApplicationSupportDirectory();
      }
    } else {
      // Linux/Mac
      return await getApplicationSupportDirectory();
    }
  }

  /// Get the local directory where surveys are stored
  Future<Directory> getSurveysDirectory() async {
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
    return Directory(p.join(baseDir.path, AppConfig.storageFolder, 'surveys'));
  }

  /// Get the local directory where outbox files are stored
  Future<Directory> getOutboxDirectory() async {
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
    return Directory(p.join(baseDir.path, AppConfig.storageFolder, 'outbox'));
  }

  /// Get the survey ID from the survey name stored in settings
  /// Returns null if no survey is selected or if survey not found
  Future<String?> getActiveSurveyId() async {
    final surveyName = await _settingsService.activeSurvey;
    debugPrint('[SurveyConfig] Getting survey ID for survey name: $surveyName');

    if (surveyName == null) {
      debugPrint('[SurveyConfig] No survey name found in settings');
      return null;
    }

    final surveysDir = await getSurveysDirectory();
    if (!await surveysDir.exists()) {
      debugPrint('[SurveyConfig] Surveys directory does not exist');
      return null;
    }

    final entities = await surveysDir.list().toList();

    // Check each survey folder for a matching survey name
    for (final entity in entities) {
      if (entity is Directory) {
        try {
          final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
          final manifestFile = File(manifestPath);

          if (await manifestFile.exists()) {
            final manifest = await _loadManifestFromFile(manifestFile);
            final manifestSurveyName = manifest['surveyName'] as String?;

            if (manifestSurveyName == surveyName) {
              final surveyId = manifest['surveyId'] as String?;
              debugPrint('[SurveyConfig] ✓ Match found! Survey ID: $surveyId');
              return surveyId;
            }
          }
        } catch (e) {
          debugPrint(
              '[SurveyConfig] Failed to load manifest from ${entity.path}: $e');
          continue;
        }
      }
    }

    debugPrint(
        '[SurveyConfig] ✗ No matching survey found for name: $surveyName');
    return null;
  }

  /// Load a survey manifest from a file
  Future<Map<String, dynamic>> _loadManifestFromFile(File file) async {
    final path = file.path;
    if (_manifestCache.containsKey(path)) {
      return _manifestCache[path]!;
    }

    final manifestJson = await file.readAsString();
    final manifest = json.decode(manifestJson) as Map<String, dynamic>;
    _manifestCache[path] = manifest;
    return manifest;
  }

  /// Get the full local path for a questionnaire XML file
  Future<String?> getQuestionnaireAssetPath(String filename) async {
    final surveyId = await getActiveSurveyId();
    if (surveyId == null) return null;

    final surveysDir = await getSurveysDirectory();
    // We assume the folder name matches the surveyId (or we need to find it again)
    // For simplicity, let's assume folder name == surveyId which is standard
    // If not, we'd need to store the folder path in getActiveSurveyId

    // Re-scanning to find the folder that contains this surveyId
    // Optimization: Cache surveyId -> folderPath mapping

    final entities = await surveysDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
        if (await File(manifestPath).exists()) {
          final manifest = await _loadManifestFromFile(File(manifestPath));
          if (manifest['surveyId'] == surveyId) {
            return p.join(entity.path, filename);
          }
        }
      }
    }
    return null;
  }

  /// Get the active survey's manifest
  Future<Map<String, dynamic>?> getActiveSurveyManifest() async {
    final surveyId = await getActiveSurveyId();
    if (surveyId == null) return null;

    final surveysDir = await getSurveysDirectory();
    final entities = await surveysDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
        final file = File(manifestPath);
        if (await file.exists()) {
          final manifest = await _loadManifestFromFile(file);
          if (manifest['surveyId'] == surveyId) {
            return manifest;
          }
        }
      }
    }
    return null;
  }

  /// Get list of all available surveys (names)
  Future<List<String>> getAvailableSurveys() async {
    final List<String> availableSurveys = [];
    final surveysDir = await getSurveysDirectory();

    if (!await surveysDir.exists()) return [];

    final entities = await surveysDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        try {
          final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
          final file = File(manifestPath);
          if (await file.exists()) {
            final manifest = await _loadManifestFromFile(file);
            final name = manifest['surveyName'] as String?;
            if (name != null) {
              availableSurveys.add(name);
            }
          }
        } catch (e) {
          // ignore invalid folders
        }
      }
    }
    return availableSurveys;
  }

  /// Get the survey ID for a given survey name
  Future<String?> getSurveyId(String surveyName) async {
    final surveysDir = await getSurveysDirectory();
    if (!await surveysDir.exists()) return null;

    final entities = await surveysDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        try {
          final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
          final file = File(manifestPath);
          if (await file.exists()) {
            final manifest = await _loadManifestFromFile(file);
            if (manifest['surveyName'] == surveyName) {
              return manifest['surveyId'] as String?;
            }
          }
        } catch (e) {
          // ignore
        }
      }
    }
    return null;
  }

  /// Check if a survey is currently configured in settings
  Future<bool> isSurveyConfigured() async {
    final surveyId = await getActiveSurveyId();
    return surveyId != null;
  }

  /// Get the surveyor ID from settings
  Future<String?> getSurveyorId() async {
    return await _settingsService.surveyorId;
  }

  /// Check if all required settings are configured
  Future<bool> areSettingsConfigured() async {
    final activeSurvey = await _settingsService.activeSurvey;
    if (activeSurvey == null || activeSurvey.isEmpty) return false;

    // Surveyor ID is never read on DataKollecta -- it only feeds GiSTX's FTP
    // upload filename (see sync_screen.dart) -- so it isn't part of what
    // "configured" means for this product.
    if (AppConfig.isDataKollecta) return true;

    final surveyorId = await _settingsService.surveyorId;
    return surveyorId != null && surveyorId.isNotEmpty;
  }

  /// Clear the manifest cache
  void clearCache() {
    _manifestCache.clear();
  }
}
