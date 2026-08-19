import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/sync/http_sync_backend.dart';

void main() {
  group('resolveLocalFilename', () {
    test('strips a numeric timestamp prefix from the signed URL\'s filename',
        () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/'
        '1768751055830_avert_english.zip?token=abc',
        'AVERT',
      );
      expect(name, 'avert_english.zip');
    });

    test('leaves a filename with no numeric prefix untouched', () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/survey.zip',
        'AVERT',
      );
      expect(name, 'survey.zip');
    });

    test('does not strip a prefix that only looks numeric-ish', () {
      final name = HttpSyncBackend.resolveLocalFilename(
        'https://x.supabase.co/storage/v1/object/sign/surveys/'
        'v2_survey.zip',
        'AVERT',
      );
      expect(name, 'v2_survey.zip');
    });

    test('falls back to "<surveyName>.zip" for a malformed URL', () {
      final name =
          HttpSyncBackend.resolveLocalFilename('https://[invalid', 'AVERT');
      expect(name, 'AVERT.zip');
    });

    test('falls back to "<surveyName>.zip" when the URL has no path segments',
        () {
      final name =
          HttpSyncBackend.resolveLocalFilename('https://x.supabase.co', 'AVERT');
      expect(name, 'AVERT.zip');
    });
  });
}
