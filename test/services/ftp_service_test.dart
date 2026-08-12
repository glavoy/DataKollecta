import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/config/app_config.dart';
import 'package:GiSTX/services/app_strings.dart';
import 'package:GiSTX/services/ftp_service.dart';

/// Upload diagnostics reach the interviewer through errorUploading, so the
/// prose follows the build language while the stage name stays English.
///
///     flutter test test/services/ftp_service_test.dart
///     flutter test test/services/ftp_service_test.dart --dart-define=GISTX_COUNTRY="Burkina Faso"
void main() {
  const s = AppStrings(AppConfig.isFrench);

  FtpUploadResult failure(FtpUploadStage stage, String message) =>
      FtpUploadResult(
        success: false,
        stage: stage,
        remoteDirectory: '/r21/data',
        remoteFilename: 'x.zip',
        localBytes: 10,
        remoteBytes: null,
        message: message,
      );

  group('upload failure message', () {
    test('the prose follows the build language', () {
      final text = failure(FtpUploadStage.changeDirectory,
              s.cannotAccessDirectory('/r21/data'))
          .failureMessage;

      if (AppConfig.isFrench) {
        expect(text, startsWith('Échec du téléversement'));
        expect(text, contains("Impossible d'accéder à /r21/data"));
      } else {
        expect(text, startsWith('Upload failed during'));
        expect(text, contains('Cannot access /r21/data'));
      }
    });

    test('the stage name stays in English in both builds', () {
      // It names a step in the code. Keeping it stable is what makes a
      // photographed error report diagnosable.
      for (final stage in FtpUploadStage.values) {
        expect(failure(stage, 'x').failureMessage, contains(stage.label));
      }
      expect(FtpUploadStage.changeDirectory.label, 'changeDirectory');
      expect(FtpUploadStage.verifySize.label, 'verifySize');
    });

    test('every prose message is translated in the French build', () {
      final messages = [
        s.notConnectedToServer,
        s.cannotAccessDirectory('/r21/data'),
        s.fileNotFoundInDirectory('x.zip', '/r21/data'),
        s.fileSizeMismatch('x.zip', '/r21/data', 5, 10),
      ];

      for (final message in messages) {
        if (AppConfig.isFrench) {
          expect(message, isNot(contains('the FTP server')));
          expect(message, isNot(contains('was not found')));
          expect(message, isNot(contains('expected')));
        } else {
          expect(message, isNot(contains('serveur')));
        }
      }
    });
  });
}
