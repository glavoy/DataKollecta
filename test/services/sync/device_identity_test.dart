import 'package:flutter_test/flutter_test.dart';
import 'package:datakollecta/services/sync/device_identity.dart';

void main() {
  test('a non-empty native id is returned as-is, without touching storage',
      () async {
    var readCalls = 0;
    var writeCalls = 0;

    final id = await DeviceIdentity.resolveDeviceId(
      nativeId: 'android-native-id',
      readPersisted: () async {
        readCalls++;
        return null;
      },
      writePersisted: (_) async => writeCalls++,
    );

    expect(id, 'android-native-id');
    expect(readCalls, 0);
    expect(writeCalls, 0);
  });

  test('a null native id falls back to a persisted id when one exists',
      () async {
    var writeCalls = 0;

    final id = await DeviceIdentity.resolveDeviceId(
      nativeId: null,
      readPersisted: () async => 'already-persisted-uuid',
      writePersisted: (_) async => writeCalls++,
    );

    expect(id, 'already-persisted-uuid');
    expect(writeCalls, 0);
  });

  test('an empty native id is treated the same as a missing one', () async {
    final id = await DeviceIdentity.resolveDeviceId(
      nativeId: '',
      readPersisted: () async => 'already-persisted-uuid',
      writePersisted: (_) async {},
    );

    expect(id, 'already-persisted-uuid');
  });

  test('no native id and nothing persisted generates and persists a new id',
      () async {
    String? written;

    final id = await DeviceIdentity.resolveDeviceId(
      nativeId: null,
      readPersisted: () async => null,
      writePersisted: (value) async => written = value,
      generate: () => 'freshly-generated-uuid',
    );

    expect(id, 'freshly-generated-uuid');
    expect(written, 'freshly-generated-uuid');
  });

  test('the fallback id is never the literal string "unknown"', () async {
    final id = await DeviceIdentity.resolveDeviceId(
      nativeId: null,
      readPersisted: () async => null,
      writePersisted: (_) async {},
    );

    expect(id, isNot('unknown'));
    expect(id, isNotEmpty);
  });
}
