import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../settings_service.dart';

/// A stable per-install identifier sent as `device_id` on every HTTP sync
/// request.
///
/// Uses each platform's own device-info API where one exists (Android,
/// Windows). Where the OS has nothing to offer -- macOS, Linux, iOS, or any
/// platform call that throws -- a random id is generated once and persisted
/// via [SettingsService], so the device still gets one *stable* id rather
/// than the literal string `'unknown'` the DataKollecta reference branch
/// fell back to. That string made every macOS/Linux/iOS record
/// indistinguishable from every other at the server.
class DeviceIdentity {
  static Future<String> deviceId() async {
    String? nativeId;
    try {
      nativeId = await _nativeDeviceId();
    } catch (e) {
      debugPrint('[DeviceIdentity] Platform device id lookup failed: $e');
      nativeId = null;
    }

    final settings = SettingsService();
    return resolveDeviceId(
      nativeId: nativeId,
      readPersisted: () => settings.deviceUuid,
      writePersisted: settings.setDeviceUuid,
    );
  }

  static Future<String?> _nativeDeviceId() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await plugin.androidInfo).id;
    if (Platform.isWindows) return (await plugin.windowsInfo).deviceId;
    if (Platform.isMacOS) return (await plugin.macOsInfo).systemGUID;
    if (Platform.isLinux) return (await plugin.linuxInfo).machineId;
    if (Platform.isIOS) return (await plugin.iosInfo).identifierForVendor;
    return null;
  }

  /// The actual selection/fallback logic, kept free of platform channels so
  /// it can be verified without a running platform-info plugin: prefer
  /// [nativeId] when non-empty; otherwise reuse a previously persisted id;
  /// otherwise generate one and persist it for next time.
  ///
  /// Public to allow that fallback behavior to be tested directly.
  @visibleForTesting
  static Future<String> resolveDeviceId({
    required String? nativeId,
    required Future<String?> Function() readPersisted,
    required Future<void> Function(String) writePersisted,
    String Function() generate = _generateUuid,
  }) async {
    if (nativeId != null && nativeId.isNotEmpty) return nativeId;

    final existing = await readPersisted();
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = generate();
    await writePersisted(generated);
    return generated;
  }

  static String _generateUuid() => const Uuid().v4();
}
