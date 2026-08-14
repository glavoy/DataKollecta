import 'package:flutter_test/flutter_test.dart';
import 'package:GiSTX/config/app_config.dart';
import 'package:GiSTX/services/sync/ftp_sync_backend.dart';
import 'package:GiSTX/services/sync/sync_backend.dart';

/// createSyncBackend() only has one live branch until HttpSyncBackend lands
/// later in the Phase 3 rollout, so this only asserts the GiSTX side.
void main() {
  test('the GiSTX product resolves to FtpSyncBackend', () {
    if (AppConfig.isDataKollecta) return;
    expect(createSyncBackend(), isA<FtpSyncBackend>());
  });
}
