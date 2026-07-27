import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/dosage/dosage_signal_identity.dart';

/// The span `platform` token must map each platform flag to a stable string. In
/// particular a Windows host maps to 'windows', never 'unknown' — the mapping
/// half of the native-Windows detection fix (PlatformInfos.isWindows now covers
/// native Windows, so this flag is true there and the token is 'windows').
void main() {
  String tokenFor({
    bool isWeb = false,
    bool isAndroid = false,
    bool isIOS = false,
    bool isMacOS = false,
    bool isWindows = false,
    bool isLinux = false,
  }) => DosageSignalIdentity.platformToken(
    isWeb: isWeb,
    isAndroid: isAndroid,
    isIOS: isIOS,
    isMacOS: isMacOS,
    isWindows: isWindows,
    isLinux: isLinux,
  );

  test('a Windows host maps to windows, not unknown', () {
    expect(tokenFor(isWindows: true), 'windows');
  });

  test('each platform maps to its token', () {
    expect(tokenFor(isWeb: true), 'web');
    expect(tokenFor(isAndroid: true), 'android');
    expect(tokenFor(isIOS: true), 'ios');
    expect(tokenFor(isMacOS: true), 'macos');
    expect(tokenFor(isLinux: true), 'linux');
  });

  test('no known platform maps to unknown', () {
    expect(tokenFor(), 'unknown');
  });
}
