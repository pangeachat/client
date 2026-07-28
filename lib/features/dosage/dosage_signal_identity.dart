import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/utils/platform_infos.dart';

/// Per-span metadata helpers for dosage signals: a fresh span id and the
/// device platform token. Grouped as statics — neither needs instance state.
class DosageSignalIdentity {
  DosageSignalIdentity._();

  static final Random _random = Random.secure();

  /// A RFC-4122 version-4 UUID string (the server validates `span_id` as
  /// UUIDv4). Generated from a cryptographic source so ids don't collide
  /// across a burst of offline-flushed spans. Self-contained so the feature
  /// carries no new package dependency.
  static String uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// A short, stable platform token for the span's `platform` field. Reads the
  /// live [PlatformInfos] flags (which now detect native Windows, not just
  /// web-on-Windows) and maps them via [platformToken].
  static String platform() => platformToken(
    isWeb: PlatformInfos.isWeb,
    isAndroid: PlatformInfos.isAndroid,
    isIOS: PlatformInfos.isIOS,
    isMacOS: PlatformInfos.isMacOS,
    isWindows: PlatformInfos.isWindows,
    isLinux: PlatformInfos.isLinux,
  );

  /// Pure platform-flag → token mapping. Extracted so the mapping is unit-
  /// testable off a host that isn't the target OS — in particular that a
  /// Windows host maps to `windows`, never `unknown`.
  @visibleForTesting
  static String platformToken({
    required bool isWeb,
    required bool isAndroid,
    required bool isIOS,
    required bool isMacOS,
    required bool isWindows,
    required bool isLinux,
  }) {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    if (isMacOS) return 'macos';
    if (isWindows) return 'windows';
    if (isLinux) return 'linux';
    return 'unknown';
  }
}
