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

  /// The product this build was compiled for. A second, independent axis
  /// from [country]:
  ///
  ///     dart run tool/build.dart apk                          -> gistx
  ///     dart run tool/build.dart apk --product datakollecta    -> datakollecta
  ///
  /// [country] must never change app identity -- same applicationId, same
  /// keystore, same on-device database, because it is a market selector for
  /// one app. [product] must always change it: GiSTX and DataKollecta are
  /// two separate apps that need to install side by side, not two markets
  /// for one app, so this deliberately forks applicationId, the signing
  /// key, the storage folder and the local database, the same way changing
  /// applicationId itself would.
  static const String product =
      String.fromEnvironment('APP_PRODUCT', defaultValue: 'gistx');

  /// True for the Supabase/HTTP-sync build. Folds away at compile time, so
  /// the GiSTX build carries no HTTP sync code and the DataKollecta build
  /// no FTP/SFTP code.
  static const bool isDataKollecta = product == 'datakollecta';

  /// The single path segment under the platform base directory that holds
  /// this product's zips/surveys/databases/backups/outbox.
  ///
  /// Changing this for an already-shipped build orphans every installed
  /// device's data, exactly as changing applicationId would. It is
  /// per-product, never per-country -- Uganda and Burkina Faso share one
  /// storage folder on purpose, because they are the same app.
  static const String storageFolder = isDataKollecta ? 'DataKollecta' : 'GiSTX';

  /// Name recorded in every collected record's `swver` field, and shown as
  /// the window/MaterialApp title.
  static const String appName = isDataKollecta ? 'DataKollecta' : 'GiSTX';

  /// The bundled splash/logo image for this product. Both images are
  /// declared in pubspec.yaml's asset list regardless of which build is
  /// running, since Flutter bundles by declaration, not by reachability --
  /// simpler than a per-product pubspec for a few hundred KB of art.
  static const String brandingAsset = isDataKollecta
      ? 'assets/branding/datakollecta.png'
      : 'assets/branding/gistx.png';

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
