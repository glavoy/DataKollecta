import 'dart:io';

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

/// Download-only seam, implemented by [FtpSyncBackend] for the GiSTX
/// product. Upload is deliberately NOT part of this interface -- FTP ships
/// one whole-database zip while DataKollecta's HTTP backend ships
/// incrementally-acknowledged record batches, and forcing both behind one
/// `Future<void> upload()` would hide that difference rather than abstract
/// it. Each product's sync screen calls its own upload path directly
/// instead.
///
/// [HttpSyncBackend] (the DataKollecta product) deliberately does NOT
/// implement this interface: once a device can hold several concurrent
/// project sessions, `connect(username, password)` has no meaning without
/// knowing *which* project, and login/download are keyed by project
/// throughout that backend's own API instead. [SyncException] and its
/// family are still shared here, since those genuinely are common to both
/// products.
abstract class SyncBackend {
  Future<bool> connect(String username, String password);
  Future<List<RemoteSurvey>> listSurveys();
  Future<File?> downloadSurvey(String filename);
  Future<void> disconnect();
}
