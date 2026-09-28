import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/utils/client_manager.dart';

/// Startup renewal of an expired access token (#9304,
/// session-lifetime.instructions.md). Tokens last 24 hours, so a learner who
/// opens the app less than daily restores a session whose token has already
/// expired; every request sent before the renewal lands is refused.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  /// A session restored from storage the way the app restores one at
  /// startup, with an access token that expired an hour ago.
  Future<Client> restoredWithExpiredToken(
    Future<void> Function(Client) onSoftLogout,
  ) async {
    final client = Client(
      'renewal-test',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'renewal-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
      onSoftLogout: onSoftLogout,
    );
    await client.checkHomeserver(
      Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false,
    );
    await client.init(
      newToken: 'abcd',
      newRefreshToken: 'refresh_abcd',
      newTokenExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      newUserID: '@test:fakeServer.notExisting',
      newHomeserver: client.homeserver,
      newDeviceName: 'Test',
      newDeviceID: 'GHTYAJCE',
      waitForFirstSync: false,
    );
    return client;
  }

  test('an expired token is renewed before startup carries on', () async {
    final client = await restoredWithExpiredToken(
      (client) => client.refreshAccessToken(),
    );
    addTearDown(client.dispose);

    await ClientManager.renewExpiredToken(client);

    expect(client.accessToken, 'a_new_token');
    expect(client.isLogged(), true);
  });

  test(
    'startup carries on after the wait when renewal cannot finish',
    () async {
      // A renewal that never answers, as when the device is offline.
      final never = Completer<void>();
      final client = await restoredWithExpiredToken((_) => never.future);
      addTearDown(client.dispose);

      await ClientManager.renewExpiredToken(
        client,
        wait: const Duration(milliseconds: 50),
      );

      expect(client.isLogged(), true);
    },
  );

  test(
    'a session the server rejects starts signed out, without throwing',
    () async {
      final client = await restoredWithExpiredToken((_) async {
        throw MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Invalid refresh token',
        });
      });
      addTearDown(client.dispose);

      await ClientManager.renewExpiredToken(client);

      expect(client.isLogged(), false);
    },
  );
}
