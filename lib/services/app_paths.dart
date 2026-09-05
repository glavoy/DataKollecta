// lib/services/app_paths.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// Where this product keeps its files, resolved in one place.
///
/// Eight copies of this rule used to live in `SurveyConfigService` (three),
/// `DbService` (two), `DbBackup`, `FtpService` and `ApiClient` -- the last of
/// which carried a comment saying it duplicated the others "rather than
/// introducing a new shared helper unprompted". They had to agree and nothing
/// made them: one had a Windows fallback comment the others lacked, and any
/// future change to where data lives had to be made eight times or the app
/// would read from one directory and write to another.
///
/// The layout is unchanged, and deliberately so -- it is where every already
/// installed device keeps its surveys and databases:
///
///     <base>/<AppConfig.storageFolder>/zips
///                                     /surveys/<surveyId>
///                                     /databases/<databaseName>
///                                     /backups/<surveyId>
///                                     /outbox
///
/// `<base>` is the external storage directory on Android, `%LOCALAPPDATA%` on
/// Windows, and the application support directory on macOS and Linux.
class AppPaths {
  AppPaths._();

  /// Redirects every path below this directory instead of the platform's.
  ///
  /// This exists for **DataKollecta-SurveyTest**, the desktop app that runs
  /// simulated interviews against a survey package. It has to be able to
  /// install a package and fill a database without touching the field app's
  /// data, and it links this package as a dependency, so it shares
  /// [AppConfig.storageFolder] and would otherwise write into the real
  /// `GiSTX/` folder on the same machine.
  ///
  /// A production seam rather than a `@visibleForTesting` one, because its
  /// consumer is a shipped application and not a test. Overriding
  /// `PathProviderPlatform` would have covered macOS and Linux only: the
  /// Windows branch reads an environment variable directly and never asks
  /// path_provider anything.
  ///
  /// Null in both field products, where nothing sets it.
  static Directory? overrideBaseDir;

  /// The platform's base directory, or [overrideBaseDir] when one is set.
  static Future<Directory> baseDir() async {
    final override = overrideBaseDir;
    if (override != null) return override;

    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      // Windows: Use LOCALAPPDATA for AppData\Local
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        return Directory(localAppData);
      } else {
        // Fallback if LOCALAPPDATA not set (unlikely)
        return await getApplicationSupportDirectory();
      }
    } else {
      // Linux/Mac
      return await getApplicationSupportDirectory();
    }
  }

  /// `<base>/<AppConfig.storageFolder>` -- this product's whole tree.
  static Future<Directory> storageDir() async =>
      Directory(p.join((await baseDir()).path, AppConfig.storageFolder));

  /// One directory inside that tree.
  ///
  /// [create] mirrors what each call site did before this was shared: the
  /// zips and databases directories were created on demand, the others were
  /// returned as-is for the caller to check. Keeping that per-caller rather
  /// than creating everything avoids a build that leaves empty folders behind
  /// on a device that never used the feature.
  static Future<Directory> subdir(String name, {bool create = false}) async {
    final dir = Directory(p.join((await storageDir()).path, name));
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> zipsDir({bool create = true}) =>
      subdir('zips', create: create);

  static Future<Directory> surveysDir({bool create = false}) =>
      subdir('surveys', create: create);

  static Future<Directory> databasesDir({bool create = true}) =>
      subdir('databases', create: create);

  static Future<Directory> backupsDir({bool create = false}) =>
      subdir('backups', create: create);

  static Future<Directory> outboxDir({bool create = false}) =>
      subdir('outbox', create: create);
}
