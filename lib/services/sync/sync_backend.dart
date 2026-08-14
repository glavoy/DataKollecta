import 'dart:io';

import '../../config/app_config.dart';
import 'ftp_sync_backend.dart';
import 'http_sync_backend.dart';

/// A survey package available for download from a sync backend's server.
class RemoteSurvey {
  final String filename;
  const RemoteSurvey(this.filename);
}

/// Failures a [SyncBackend] can raise. A sealed family so a call site can
/// exhaustively `switch` on it into a user-facing message, rather than
/// sniffing exception text (`message.contains('404')`) the way the
/// DataKollecta reference branch did.
sealed class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

/// The server could not be reached at all (DNS, socket, timeout).
class SyncConnectionException extends SyncException {
  const SyncConnectionException(super.message);
}

/// The server was reached but rejected the credentials or session.
class SyncAuthException extends SyncException {
  const SyncAuthException(super.message);
}

/// The connection and auth succeeded but a list/download/upload call failed.
class SyncTransferException extends SyncException {
  const SyncTransferException(super.message);
}

/// Download-only seam shared by every sync backend. Upload is deliberately
/// NOT part of this interface -- FTP ships one whole-database zip while HTTP
/// ships incrementally-acknowledged record batches, and forcing both behind
/// one `Future<void> upload()` would hide that difference rather than
/// abstract it. Each product's sync screen calls its own upload path
/// directly instead.
abstract class SyncBackend {
  Future<bool> connect(String username, String password);
  Future<List<RemoteSurvey>> listSurveys();
  Future<File?> downloadSurvey(String filename);
  Future<void> disconnect();
}

/// Compile-time selection, so the unused implementation tree-shakes away --
/// the GiSTX build carries no HTTP/Supabase code, the DataKollecta build no
/// ftpconnect/dartssh2 code.
SyncBackend createSyncBackend() =>
    AppConfig.isDataKollecta ? HttpSyncBackend() : FtpSyncBackend();
