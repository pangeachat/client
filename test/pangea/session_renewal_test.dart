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

  test('startup waits for the renewal to land before carrying on', () async {
    // Hold the renewal until the test releases it: returning before then is
    // exactly the race this guards against (the SDK's own sync loop renews
    // too, so checking only the final token would pass without the wait).
    final release = Completer<void>();
    final client = await restoredWithExpiredToken((client) async {
      await release.future;
      await client.refreshAccessToken();
    });
    addTearDown(client.dispose);

    var returned = false;
    final renewal = ClientManager.renewExpiredToken(
      client,
    ).then((_) => returned = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(returned, isFalse);

    release.complete();
    await renewal;
    expect(returned, isTrue);
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
