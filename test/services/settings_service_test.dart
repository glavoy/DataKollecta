import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:datakollecta/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Runs on the host's shared_preferences branch of SettingsService
    // (macOS/Linux), no secure-storage mocking needed.
    SharedPreferences.setMockInitialValues({});
  });

  group('getSurveyorIdOrGlobal', () {
    test('prefers the survey-specific Surveyor ID when one is set', () async {
      final settings = SettingsService();
      await settings.setSurveyorId('58');
      await settings.setSurveyorIdForSurvey('survey_a', '27');

      expect(await settings.getSurveyorIdOrGlobal('survey_a'), '27');
    });

    test('falls back to the global Surveyor ID when none is saved for the survey',
        () async {
      final settings = SettingsService();
      await settings.setSurveyorId('58');

      expect(await settings.getSurveyorIdOrGlobal('survey_b'), '58');
    });

    test('returns null when neither a survey-specific nor a global value exists',
        () async {
      final settings = SettingsService();

      expect(await settings.getSurveyorIdOrGlobal('survey_c'), isNull);
    });

    test('one Surveyor ID can be associated with more than one survey',
        () async {
      final settings = SettingsService();
      await settings.setSurveyorIdForSurvey('survey_a', '27');
      await settings.setSurveyorIdForSurvey('survey_d', '27');

      expect(await settings.getSurveyorIdOrGlobal('survey_a'), '27');
      expect(await settings.getSurveyorIdOrGlobal('survey_d'), '27');
    });
  });
}
