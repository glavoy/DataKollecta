/// Application configuration
///
/// This file contains all configurable application-level settings.

class AppConfig {
  /// The country this build was compiled for.
  ///
  /// Set at build time, not at runtime:
  ///
  ///     flutter build apk                                          -> Uganda
  ///     flutter build apk --dart-define=GISTX_COUNTRY="Burkina Faso"
  ///
  /// Because it is a compile-time constant, the conditions below fold away
  /// during compilation: a Uganda build carries no country control in its UI,
  /// and a Burkina Faso build needs no setting to switch to French or SFTP.
  ///
  /// Deliberately NOT a Gradle product flavor: those conventionally add an
  /// applicationIdSuffix, which would make the second build a separate app
  /// that cannot update the first, orphaning the database already on the
  /// device. `--dart-define` cannot change the application id.
  static const String country =
      String.fromEnvironment('GISTX_COUNTRY', defaultValue: 'Uganda');

  /// Whether this build shows its UI in French.
  static const bool isFrench = country == 'Burkina Faso';

  /// True for the plain build. Used to hide country-specific UI entirely
  /// rather than showing a control with only one option.
  static const bool isDefaultCountry = country == 'Uganda';

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
