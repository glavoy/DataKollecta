import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import 'app_strings.dart';

/// Wording for the messages an interviewer sees when a sync fails.
const AppStrings _s = AppStrings(AppConfig.isFrench);

enum FtpUploadStage {
  changeDirectory,
  upload,
  verifyFilename,
  verifySize,
}

extension FtpUploadStageLabel on FtpUploadStage {
  String get label {
    switch (this) {
      case FtpUploadStage.changeDirectory:
        return 'changeDirectory';
      case FtpUploadStage.upload:
        return 'upload';
      case FtpUploadStage.verifyFilename:
        return 'verifyFilename';
      case FtpUploadStage.verifySize:
        return 'verifySize';
    }
  }
}

class FtpUploadResult {
  final bool success;
  final FtpUploadStage stage;
  final String remoteDirectory;
  final String remoteFilename;
  final int localBytes;
  final int? remoteBytes;
  final String message;

  const FtpUploadResult({
    required this.success,
    required this.stage,
    required this.remoteDirectory,
    required this.remoteFilename,
    required this.localBytes,
    required this.remoteBytes,
    required this.message,
  });

  String get failureMessage {
    if (success) return message;
    return _s.uploadFailedAtStage(stage.label, message);
  }
}

/// Small adapter seam around the FTP package. It lets connection behaviour be
/// tested without opening real sockets from widget/unit tests.
abstract interface class FtpClient {
  Future<bool> connect();
  Future<bool> disconnect();
  Future<bool> changeDirectory(String? directory);
  Future<List<FTPEntry>> listDirectoryContent();
  Future<bool> downloadFile(String? remoteName, File localFile);
  Future<bool> uploadFile(File file, {String remoteName, bool supportIPV6});
  Future<int> sizeFile(String filename);
}

typedef FtpClientFactory = FtpClient Function({
  required String host,
  required int port,
  required String username,
  required String password,
});

class _FtpConnectClient implements FtpClient {
  final FTPConnect _client;

  _FtpConnectClient(this._client);

  @override
  Future<bool> changeDirectory(String? directory) =>
      _client.changeDirectory(directory);

  @override
  Future<bool> connect() => _client.connect();

  @override
  Future<bool> disconnect() => _client.disconnect();

  @override
  Future<bool> downloadFile(String? remoteName, File localFile) =>
      _client.downloadFile(remoteName, localFile);

  @override
  Future<List<FTPEntry>> listDirectoryContent() =>
      _client.listDirectoryContent();

  @override
  Future<int> sizeFile(String filename) => _client.sizeFile(filename);

  @override
  Future<bool> uploadFile(File file,
          {String remoteName = '', bool supportIPV6 = true}) =>
      _client.uploadFile(
        file,
        sRemoteName: remoteName,
        supportIPV6: supportIPV6,
      );
}

class FtpService {
  static const _downloadTimeout = Duration(minutes: 2);
  static const _ugandaPrimaryHost = 'ftp-sync.idrcdata.org';
  static const _ugandaProviderHost = 'ftp-4fa9bafd.registeredsite.com';

  // FTP connection (Uganda)
  FtpClient? _ftpConnect;
  final FtpClientFactory _ftpClientFactory;
  // SFTP connection (Burkina Faso)
  SSHClient? _sshClient;
  SftpClient? _sftpClient;

  String _pathPrefix = '';
  bool get _usesSftp => _sftpClient != null;

  FtpService({FtpClientFactory? ftpClientFactory})
      : _ftpClientFactory = ftpClientFactory ?? _createFtpClient;

  static FtpClient _createFtpClient({
    required String host,
    required int port,
    required String username,
    required String password,
  }) =>
      _FtpConnectClient(
        FTPConnect(host, user: username, pass: password, port: port),
      );

  /// Accounts whose files do not sit at the usual depth. The test account's
  /// home directory holds a copy of the production layout one level down, and
  /// neither folder can be renamed on our side.
  ///
  /// A prefix with a slash in it only works over SFTP, which builds absolute
  /// paths. The FTP branch below walks the prefix as a single changeDirectory
  /// hop, so teach it to walk segments before adding an entry for a build that
  /// uses FTP.
  static const Map<String, String> _burkinaPathPrefix = {
    'r21_test': 'r21_test/r21',
  };

  /// Server and folder for a login on the country this build was compiled for.
  static ({String host, int port, String pathPrefix}) _serverConfig(
      String country, String username) {
    if (country == 'Burkina Faso') {
      return (
        host: 'ftp.crundata.net',
        port: 2220,
        pathPrefix: _burkinaPathPrefix[username] ?? 'r21',
      );
    }
    return (host: _ugandaPrimaryHost, port: 21, pathPrefix: '');
  }

  String get _uploadDirectory =>
      _pathPrefix.isEmpty ? '/data' : '/$_pathPrefix/data';

  /// Connect to the server (SFTP for Burkina Faso, FTP for Uganda)
  Future<bool> connect(String username, String password) async {
    const country = AppConfig.country;
    final config = _serverConfig(country, username);
    _pathPrefix = config.pathPrefix;
    debugPrint(
        '[FtpService] $username -> ${_pathPrefix.isEmpty ? '/' : '/$_pathPrefix'}');

    if (country == 'Burkina Faso') {
      try {
        final socket = await SSHSocket.connect(config.host, config.port);
        _sshClient = SSHClient(
          socket,
          username: username,
          onPasswordRequest: () => password,
        );
        await _sshClient!.authenticated;
        _sftpClient = await _sshClient!.sftp();
        return true;
      } catch (e) {
        debugPrint('[FtpService] SFTP connection failed: $e');
        _sshClient?.close();
        _sshClient = null;
        _sftpClient = null;
        return false;
      }
    } else {
      return _connectUganda(username, password, config.port);
    }
  }

  /// Connect through the controlled hostname first. The direct provider name
  /// is only an emergency fallback while DNS changes propagate or are fixed.
  Future<bool> _connectUganda(
      String username, String password, int port) async {
    if (_ftpConnect != null) await disconnect();

    final primary = await _tryFtpConnection(
      host: _ugandaPrimaryHost,
      port: port,
      username: username,
      password: password,
      isFallback: false,
    );
    if (primary.connected) return true;
    if (primary.authenticationFailed) return false;

    final fallback = await _tryFtpConnection(
      host: _ugandaProviderHost,
      port: port,
      username: username,
      password: password,
      isFallback: true,
    );
    return fallback.connected;
  }

  Future<({bool connected, bool authenticationFailed})> _tryFtpConnection({
    required String host,
    required int port,
    required String username,
    required String password,
    required bool isFallback,
  }) async {
    final client = _ftpClientFactory(
      host: host,
      port: port,
      username: username,
      password: password,
    );
    debugPrint(
        '[FtpService] FTP ${isFallback ? 'fallback ' : ''}connection attempt: $host');

    try {
      await client.connect();
      _ftpConnect = client;
      debugPrint(
          '[FtpService] FTP ${isFallback ? 'fallback ' : ''}connection succeeded: $host');
      return (connected: true, authenticationFailed: false);
    } catch (error) {
      final authenticationFailed = _isAuthenticationFailure(error);
      debugPrint(
          '[FtpService] FTP ${isFallback ? 'fallback ' : ''}connection failed: $host ($error)');
      try {
        await client.disconnect();
      } catch (_) {
        // The failed client is deliberately discarded either way.
      }
      return (
        connected: false,
        authenticationFailed: authenticationFailed,
      );
    }
  }

  static bool _isAuthenticationFailure(Object error) {
    if (error is! FTPException) return false;
    return error.message.startsWith('Wrong username') ||
        error.message == 'Wrong password';
  }

  /// List zip files in the /survey/ directory
  Future<List<String>> listSurveyZips() async {
    if (_usesSftp) {
      try {
        final dir = _pathPrefix.isEmpty ? '/survey' : '/$_pathPrefix/survey';
        final items = await _sftpClient!.listdir(dir);
        return items
            .where((item) =>
                item.filename.toLowerCase().endsWith('.zip') &&
                item.filename != '.' &&
                item.filename != '..')
            .map((item) => item.filename)
            .toList();
      } catch (e) {
        debugPrint('[FtpService] SFTP list failed: $e');
        return [];
      }
    }

    if (_ftpConnect == null) return [];
    try {
      if (_pathPrefix.isNotEmpty)
        await _ftpConnect!.changeDirectory(_pathPrefix);
      await _ftpConnect!.changeDirectory('survey');
      final entries = await _ftpConnect!.listDirectoryContent();

      // Filter for .zip files
      return entries
          .where((entry) =>
              entry.name != null && entry.name!.toLowerCase().endsWith('.zip'))
          .map((entry) => entry.name!)
          .toList();
    } catch (e) {
      debugPrint('[FtpService] FTP list failed: $e');
      return [];
    }
  }

  /// Download a specific zip file to the local zips folder
  Future<File?> downloadSurveyZip(String filename) async {
    // Resolve local destination regardless of protocol
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory() ??
          await getApplicationSupportDirectory();
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        baseDir = Directory(localAppData);
      } else {
        baseDir = await getApplicationSupportDirectory();
      }
    } else {
      baseDir = await getApplicationSupportDirectory();
    }
    final zipsDir =
        Directory(p.join(baseDir.path, AppConfig.storageFolder, 'zips'));
    if (!await zipsDir.exists()) {
      await zipsDir.create(recursive: true);
    }
    final localFile = File(p.join(zipsDir.path, filename));

    if (_usesSftp) {
      try {
        final remotePath = _pathPrefix.isEmpty
            ? '/survey/$filename'
            : '/$_pathPrefix/survey/$filename';
        final bytes =
            await _sftpDownloadBytes(remotePath).timeout(_downloadTimeout);
        await localFile.writeAsBytes(bytes);
        return localFile;
      } on TimeoutException {
        debugPrint(
            '[FtpService] SFTP download timed out after $_downloadTimeout: $filename');
        return null;
      } catch (e) {
        debugPrint('[FtpService] SFTP download failed: $e');
        return null;
      }
    }

    if (_ftpConnect == null) return null;
    try {
      // Ensure we are in the right directory on server
      if (_pathPrefix.isNotEmpty)
        await _ftpConnect!.changeDirectory(_pathPrefix);
      await _ftpConnect!.changeDirectory('survey');

      await _ftpConnect!.downloadFile(filename, localFile);
      return localFile;
    } catch (e) {
      debugPrint('[FtpService] FTP download failed: $e');
      return null;
    }
  }

  /// Upload a file to the /data/ directory
  Future<FtpUploadResult> uploadFile(File file, String remoteFilename) async {
    final localBytes = await file.length();
    final remoteDirectory = _uploadDirectory;

    if (_usesSftp) {
      return _sftpUploadAndVerify(
        file: file,
        remoteFilename: remoteFilename,
        remoteDirectory: remoteDirectory,
        localBytes: localBytes,
      );
    }

    if (_ftpConnect == null) {
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.upload,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: _s.notConnectedToServer,
      );
    }

    try {
      // Ensure we are in the right directory on server
      if (_pathPrefix.isNotEmpty) {
        final prefixChanged = await _ftpConnect!.changeDirectory(_pathPrefix);
        if (!prefixChanged) {
          return FtpUploadResult(
            success: false,
            stage: FtpUploadStage.changeDirectory,
            remoteDirectory: remoteDirectory,
            remoteFilename: remoteFilename,
            localBytes: localBytes,
            remoteBytes: null,
            message: _s.cannotAccessDirectory('/$_pathPrefix'),
          );
        }
      }

      final dataChanged = await _ftpConnect!.changeDirectory('data');
      if (!dataChanged) {
        return FtpUploadResult(
          success: false,
          stage: FtpUploadStage.changeDirectory,
          remoteDirectory: remoteDirectory,
          remoteFilename: remoteFilename,
          localBytes: localBytes,
          remoteBytes: null,
          message: _s.cannotAccessDirectory(remoteDirectory),
        );
      }

      final firstAttempt = await _uploadAndVerify(
        file: file,
        remoteFilename: remoteFilename,
        remoteDirectory: remoteDirectory,
        localBytes: localBytes,
        supportIPV6: true,
      );
      if (firstAttempt.success ||
          firstAttempt.stage == FtpUploadStage.changeDirectory) {
        return firstAttempt;
      }

      debugPrint(
          '[FtpService] Retrying upload with IPv4 PASV mode: ${firstAttempt.failureMessage}');
      return _uploadAndVerify(
        file: file,
        remoteFilename: remoteFilename,
        remoteDirectory: remoteDirectory,
        localBytes: localBytes,
        supportIPV6: false,
      );
    } catch (e) {
      debugPrint('[FtpService] FTP upload failed: $e');
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.upload,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: e.toString(),
      );
    }
  }

  Future<Uint8List> _sftpDownloadBytes(String remotePath) async {
    final remoteFile =
        await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      return await remoteFile.readBytes();
    } finally {
      await remoteFile.close();
    }
  }

  Future<FtpUploadResult> _sftpUploadAndVerify({
    required File file,
    required String remoteFilename,
    required String remoteDirectory,
    required int localBytes,
  }) async {
    final remotePath = '$remoteDirectory/$remoteFilename';
    try {
      final bytes = await file.readAsBytes();
      final remoteFile = await _sftpClient!.open(
        remotePath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      await remoteFile.writeBytes(bytes);
      await remoteFile.close();
    } catch (e) {
      debugPrint('[FtpService] SFTP upload transfer failed: $e');
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.upload,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: e.toString(),
      );
    }

    // Verify by size
    try {
      final attrs = await _sftpClient!.stat(remotePath);
      final remoteBytes = attrs.size;
      if (remoteBytes == null) {
        return FtpUploadResult(
          success: false,
          stage: FtpUploadStage.verifyFilename,
          remoteDirectory: remoteDirectory,
          remoteFilename: remoteFilename,
          localBytes: localBytes,
          remoteBytes: null,
          message: _s.fileNotFoundInDirectory(remoteFilename, remoteDirectory),
        );
      }
      if (remoteBytes != localBytes) {
        return FtpUploadResult(
          success: false,
          stage: FtpUploadStage.verifySize,
          remoteDirectory: remoteDirectory,
          remoteFilename: remoteFilename,
          localBytes: localBytes,
          remoteBytes: remoteBytes,
          message: _s.fileSizeMismatch(
              remoteFilename, remoteDirectory, remoteBytes, localBytes),
        );
      }
      debugPrint(
          '[FtpService] SFTP verified upload: $remotePath ($remoteBytes bytes)');
      return FtpUploadResult(
        success: true,
        stage: FtpUploadStage.verifySize,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: remoteBytes,
        message: 'Verified $remotePath ($remoteBytes bytes).',
      );
    } catch (e) {
      debugPrint('[FtpService] SFTP verify failed: $e');
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.verifyFilename,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: e.toString(),
      );
    }
  }

  Future<FtpUploadResult> _uploadAndVerify({
    required File file,
    required String remoteFilename,
    required String remoteDirectory,
    required int localBytes,
    required bool supportIPV6,
  }) async {
    try {
      await _ftpConnect!.uploadFile(
        file,
        remoteName: remoteFilename,
        supportIPV6: supportIPV6,
      );
    } catch (e) {
      debugPrint('[FtpService] Upload transfer failed: $e');
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.upload,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: e.toString(),
      );
    }

    final remoteBytes = await _ftpConnect!.sizeFile(remoteFilename);
    if (remoteBytes == -1) {
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.verifyFilename,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: null,
        message: _s.fileNotFoundInDirectory(remoteFilename, remoteDirectory),
      );
    }

    if (remoteBytes != localBytes) {
      return FtpUploadResult(
        success: false,
        stage: FtpUploadStage.verifySize,
        remoteDirectory: remoteDirectory,
        remoteFilename: remoteFilename,
        localBytes: localBytes,
        remoteBytes: remoteBytes,
        message:
            '$remoteFilename exists in $remoteDirectory but is $remoteBytes bytes; expected $localBytes bytes.',
      );
    }

    final remotePath = '$remoteDirectory/$remoteFilename';
    debugPrint(
        '[FtpService] Verified upload: $remotePath ($remoteBytes bytes)');
    return FtpUploadResult(
      success: true,
      stage: FtpUploadStage.verifySize,
      remoteDirectory: remoteDirectory,
      remoteFilename: remoteFilename,
      localBytes: localBytes,
      remoteBytes: remoteBytes,
      message: 'Verified $remotePath ($remoteBytes bytes).',
    );
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    if (_sftpClient != null) {
      _sftpClient = null;
    }
    if (_sshClient != null) {
      _sshClient!.close();
      _sshClient = null;
    }
    if (_ftpConnect != null) {
      try {
        await _ftpConnect!.disconnect();
      } catch (e) {
        debugPrint('[FtpService] FTP disconnect failed: $e');
      }
      _ftpConnect = null;
    }
  }
}
