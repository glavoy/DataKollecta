/// Raised by the database layer for a failure the caller is expected to see.
///
/// Lives in its own file because both `DbService` and `SurveyTableSchema`
/// throw it, and neither should have to import the other to do so.
/// `db_service.dart` re-exports it, so `import 'db_service.dart'` still brings
/// it into scope exactly as before.
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);
  @override
  String toString() => message;
}
