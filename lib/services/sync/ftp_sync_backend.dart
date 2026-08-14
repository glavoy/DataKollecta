import 'dart:io';

import '../ftp_service.dart';
import 'sync_backend.dart';

/// Adapts the existing, unmodified [FtpService] to [SyncBackend]. Upload
/// stays out of this seam -- `sync_screen.dart` calls `FtpService.uploadFile`
/// directly, exactly as it does today.
class FtpSyncBackend implements SyncBackend {
  final FtpService _ftp = FtpService();

  @override
  Future<bool> connect(String username, String password) =>
      _ftp.connect(username, password);

  @override
  Future<List<RemoteSurvey>> listSurveys() async {
    final filenames = await _ftp.listSurveyZips();
    return filenames.map(RemoteSurvey.new).toList();
  }

  @override
  Future<File?> downloadSurvey(String filename) =>
      _ftp.downloadSurveyZip(filename);

  @override
  Future<void> disconnect() => _ftp.disconnect();
}
