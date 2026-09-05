import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// The plain-text SQL journal written alongside every insert and update.
///
/// Split out of `DbService`. Every survey table gets a `<table>_bak` file under
/// `<base>/<storageFolder>/backups/<surveyId>/`, appended to with the statement
/// that would reproduce the write. It is a belt-and-braces record for a device
/// whose SQLite file goes bad, never read back by the app.
///
/// This is the most self-contained region of the old file: file system only, no
/// `Database`, no open-database registry, no schema. It was spread across seven
/// hundred lines of `db_service.dart` for no reason other than where it was
/// added.
///
/// **The escaping here is for a file, not for execution.** Nothing runs these
/// statements; they exist to be read by a person or replayed by hand. That is
/// why this is not the identifier guard in `SurveyTableSchema` and must not be
/// confused with it -- [escapeSqlValue] quotes a *value*, and the table and
/// column names in the surrounding statement are interpolated raw by the
/// callers in `DbService`. Safe as long as it stays a file that nothing feeds
/// back into a database.
class DbBackup {
  /// Appends [sql] to this survey's journal for [tableName].
  ///
  /// Never throws: a failed backup must not fail the save it accompanies.
  static Future<void> write(
      String surveyId, String tableName, String sql) async {
    try {
      final backupsDir = await _backupsDirectory();
      final surveyBackupDir = Directory(p.join(backupsDir.path, surveyId));
      if (!await surveyBackupDir.exists()) {
        await surveyBackupDir.create(recursive: true);
      }

      final backupFile = File(p.join(surveyBackupDir.path, '${tableName}_bak'));

      // Append mode
      await backupFile.writeAsString('$sql\n', mode: FileMode.append);
    } catch (e) {
      _logError('Failed to write backup: $e');
    }
  }

  /// A Dart value as a SQL literal, for the journal.
  static String escapeSqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is DateTime) return "'${value.toIso8601String()}'";
    return "'${escapeSqlString(value.toString())}'";
  }

  /// Doubles single quotes, so an apostrophe in an answer cannot end the
  /// literal it sits in.
  static String escapeSqlString(String str) {
    return str.replaceAll("'", "''");
  }

  static Future<Directory> _backupsDirectory() => AppPaths.backupsDir();

  // The prefix deliberately still reads `[DbService ERROR]`. These lines went
  // to the console under that tag before the split, and this refactor is meant
  // to change nothing an operator can observe -- including what they grep for.
  // Renaming it is a one-line follow-up, not something to fold in here.
  static void _logError(String message) {
    debugPrint('[DbService ERROR] $message');
  }
}
