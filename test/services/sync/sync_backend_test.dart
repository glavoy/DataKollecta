import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/config/app_config.dart';
import 'package:GiSTX/services/sync/ftp_sync_backend.dart';
import 'package:GiSTX/services/sync/http_sync_backend.dart';
import 'package:GiSTX/services/sync/sync_backend.dart';

/// Exactly one branch is live per build (AppConfig.product is a compile-time
/// constant), so only one of these two assertions runs per flavor.
void main() {
  test('the GiSTX product resolves to FtpSyncBackend', () {
    if (AppConfig.isDataKollecta) return;
    expect(createSyncBackend(), isA<FtpSyncBackend>());
  });

  test('the DataKollecta product resolves to HttpSyncBackend', () {
    if (!AppConfig.isDataKollecta) return;
    expect(createSyncBackend(), isA<HttpSyncBackend>());
  });
}
