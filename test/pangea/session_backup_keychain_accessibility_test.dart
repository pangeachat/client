import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/init_with_restore.dart';

// The session backup is written on every client init, including iOS
// background launches while the device is locked. The plugin default
// (`unlocked`, i.e. kSecAttrAccessibleWhenUnlocked) is unreachable in that
// state and the write fails with errSecInteractionNotAllowed (-25308, Sentry
// CLIENT-4ZN). Pins the accessibility level the store actually sends to the
// iOS plugin, so a `const FlutterSecureStorage()` can't quietly come back.
void main() {
  test('session backup keychain store is reachable after first unlock', () {
    final params = InitWithRestoreExtension.sessionBackupStorage.iOptions
        .toMap();
    expect(params['accessibility'], 'first_unlock');
  });
}
