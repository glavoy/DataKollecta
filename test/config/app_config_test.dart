import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/config/app_config.dart';

/// The country is fixed when the app is built. These assertions hold for
/// whichever flavor the suite is run under, so a broken --dart-define or a
/// stray default shows up as a failure rather than as the wrong server or the
/// wrong language in the field.
///
///     flutter test
///     flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"
void main() {
  test('the build resolves to exactly one known country', () {
    expect(
      AppConfig.country,
      anyOf('Uganda', 'Burkina Faso'),
      reason: 'GISTX_COUNTRY was set to an unrecognised value; the app would '
          'silently fall back to Uganda settings.',
    );
  });

  test('language and default-country flags agree with the country', () {
    expect(AppConfig.isFrench, AppConfig.country == 'Burkina Faso');
    expect(AppConfig.isDefaultCountry, AppConfig.country == 'Uganda');
  });

  test('exactly one of the two flavors is active', () {
    expect(AppConfig.isFrench && AppConfig.isDefaultCountry, isFalse);
  });

  test('an unflavored build is Uganda in English', () {
    const isFlavored =
        bool.hasEnvironment('GISTX_COUNTRY') ? true : false;
    if (!isFlavored) {
      expect(AppConfig.country, 'Uganda');
      expect(AppConfig.isFrench, isFalse);
      expect(AppConfig.isDefaultCountry, isTrue);
    }
  });
}
