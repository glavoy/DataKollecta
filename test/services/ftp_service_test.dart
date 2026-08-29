import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:datakollecta/config/app_config.dart';
import 'package:datakollecta/services/app_strings.dart';
import 'package:datakollecta/services/ftp_service.dart';

class _FakeFtpClient implements FtpClient {
  _FakeFtpClient(this._connect);

  final Future<bool> Function() _connect;
  int disconnectCalls = 0;

  @override
  Future<bool> changeDirectory(String? directory) async => true;

  @override
  Future<bool> connect() => _connect();

  @override
  Future<bool> disconnect() async {
    disconnectCalls++;
    return true;
  }

  @override
  Future<bool> downloadFile(String? remoteName, File localFile) async => true;

  @override
  Future<List<FTPEntry>> listDirectoryContent() async => [];

  @override
  Future<int> sizeFile(String filename) async => 0;

  @override
  Future<bool> uploadFile(File file,
          {String remoteName = '', bool supportIPV6 = true}) async =>
      true;
}

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

  group('Uganda FTP host fallback', () {
    test('uses the controlled hostname first', () async {
      if (AppConfig.country != 'Uganda') return;

      final attemptedHosts = <String>[];
      final primary = _FakeFtpClient(() async => true);
      final service = FtpService(
        ftpClientFactory: ({
          required host,
          required port,
          required username,
          required password,
        }) {
          attemptedHosts.add(host);
          return primary;
        },
      );

      expect(await service.connect('interviewer', 'secret'), isTrue);
      expect(attemptedHosts, ['ftp-sync.idrcdata.org']);
    });

    test('uses the provider hostname once after a primary connection failure',
        () async {
      if (AppConfig.country != 'Uganda') return;

      final attemptedHosts = <String>[];
      final primary = _FakeFtpClient(
          () => Future<bool>.error(FTPException('Could not connect')));
      final fallback = _FakeFtpClient(() async => true);
      final service = FtpService(
        ftpClientFactory: ({
          required host,
          required port,
          required username,
          required password,
        }) {
          attemptedHosts.add(host);
          return host == 'ftp-sync.idrcdata.org' ? primary : fallback;
        },
      );

      expect(await service.connect('interviewer', 'secret'), isTrue);
      expect(attemptedHosts, [
        'ftp-sync.idrcdata.org',
        'ftp-4fa9bafd.registeredsite.com',
      ]);
      expect(primary.disconnectCalls, 1);
    });

    test('returns failure after both current hosts fail', () async {
      if (AppConfig.country != 'Uganda') return;

      final attemptedHosts = <String>[];
      final clients = <_FakeFtpClient>[];
      final service = FtpService(
        ftpClientFactory: ({
          required host,
          required port,
          required username,
          required password,
        }) {
          attemptedHosts.add(host);
          final client = _FakeFtpClient(
              () => Future<bool>.error(FTPException('Could not connect')));
          clients.add(client);
          return client;
        },
      );

      expect(await service.connect('interviewer', 'secret'), isFalse);
      expect(attemptedHosts, [
        'ftp-sync.idrcdata.org',
        'ftp-4fa9bafd.registeredsite.com',
      ]);
      expect(clients.map((client) => client.disconnectCalls), [1, 1]);
    });

    test('does not fall back after an explicit authentication rejection',
        () async {
      if (AppConfig.country != 'Uganda') return;

      final attemptedHosts = <String>[];
      final primary = _FakeFtpClient(
          () => Future<bool>.error(FTPException('Wrong password', '530')));
      final service = FtpService(
        ftpClientFactory: ({
          required host,
          required port,
          required username,
          required password,
        }) {
          attemptedHosts.add(host);
          return primary;
        },
      );

      expect(await service.connect('interviewer', 'secret'), isFalse);
      expect(attemptedHosts, ['ftp-sync.idrcdata.org']);
      expect(primary.disconnectCalls, 1);
    });
  });
}
