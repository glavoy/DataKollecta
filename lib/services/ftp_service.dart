import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';

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
    return 'Upload failed during ${stage.label}: $message';
  }
}

class FtpService {
  static const _downloadTimeout = Duration(minutes: 2);


  // FTP connection (Uganda)
  FTPConnect? _ftpConnect;
  // SFTP connection (Burkina Faso)
  SSHClient? _sshClient;
  SftpClient? _sftpClient;

  String _pathPrefix = '';
  bool get _usesSftp => _sftpClient != null;

  /// Server for the country this build was compiled for.
  static ({String host, int port, String pathPrefix}) _countryConfig(
      String country) {
    if (country == 'Burkina Faso') {
      return (host: 'ftp.crundata.net', port: 2220, pathPrefix: 'r21');
    }
    return (host: '0f7a55b.netsolhost.com', port: 21, pathPrefix: '');
  }

  String get _uploadDirectory =>
      _pathPrefix.isEmpty ? '/data' : '/$_pathPrefix/data';

  /// Connect to the server (SFTP for Burkina Faso, FTP for Uganda)
  Future<bool> connect(String username, String password) async {
    const country = AppConfig.country;
    final config = _countryConfig(country);
    _pathPrefix = config.pathPrefix;

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
      _ftpConnect = FTPConnect(config.host,
          user: username, pass: password, port: config.port);
      try {
        await _ftpConnect!.connect();
        return true;
      } catch (e) {
        debugPrint('[FtpService] FTP connection failed: $e');
        return false;
      }
    }
  }

  /// List zip files in the /survey/ directory
  Future<List<String>> listSurveyZips() async {
    if (_usesSftp) {
      try {
        final dir =
            _pathPrefix.isEmpty ? '/survey' : '/$_pathPrefix/survey';
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
    final zipsDir = Directory(p.join(baseDir.path, 'GiSTX', 'zips'));
    if (!await zipsDir.exists()) {
      await zipsDir.create(recursive: true);
    }
    final localFile = File(p.join(zipsDir.path, filename));

    if (_usesSftp) {
      try {
        final remotePath =
            _pathPrefix.isEmpty ? '/survey/$filename' : '/$_pathPrefix/survey/$filename';
        final bytes = await _sftpDownloadBytes(remotePath)
            .timeout(_downloadTimeout);
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
        message: 'Not connected to FTP server.',
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
            message: 'Cannot access /$_pathPrefix on the FTP server.',
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
          message: 'Cannot access $remoteDirectory on the FTP server.',
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
          message: '$remoteFilename was not found in $remoteDirectory.',
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
      debugPrint('[FtpService] SFTP verified upload: $remotePath ($remoteBytes bytes)');
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
        sRemoteName: remoteFilename,
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
        message: '$remoteFilename was not found in $remoteDirectory.',
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
