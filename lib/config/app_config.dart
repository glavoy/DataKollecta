/// Application configuration
///
/// This file contains all configurable application-level settings.

class AppConfig {
  // Software version - now read from pubspec.yaml via PackageInfo
  // See auto_fields.dart for implementation

  // Logging configuration
  static const bool enableDebugLogging = true;
  static const bool enableErrorDialogs = true;

  // Default survey folder path
  static const String surveysAssetPath = 'assets/surveys';

  // Database folder path
  static const String databaseFolderPath = 'assets/database';
}
