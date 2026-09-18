import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'get_test_client.dart';

/// Regression: Sentry CLIENT-EPP (#9018).
///
/// `ClientManager.getClients` forgets signed-out accounts when the store holds
/// more than one name. With every stored account signed out it forgot all of
/// them, handed `Matrix` an empty client list, and `MatrixState.client` threw
/// on the first read inside `initState` — no login screen, nothing to recover
/// from short of clearing site data. The decision is pinned here so at least
/// one client always survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    // PlatformInfos.clientName reads the application name from AppSettings.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  /// A client nobody ever logged in on — `isLogged()` is false, as it is for
  /// a stored account whose session ended.
  Future<Client> signedOut(String name) async => Client(
    name,
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      name,
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  test('forgets only the signed-out accounts while one is signed in', () async {
    final signedIn = await getTestClient(name: 'live');
    final stale = await signedOut('stale');
    addTearDown(signedIn.dispose);
    addTearDown(stale.dispose);

    expect(ClientManager.signedOutClientsToForget([stale, signedIn]), [stale]);
  });

  test(
    'keeps the most recent client when every account is signed out',
    () async {
      final older = await signedOut('Pangea Chat-1');
      final newer = await signedOut('Pangea Chat-2');
      addTearDown(older.dispose);
      addTearDown(newer.dispose);

      expect(ClientManager.signedOutClientsToForget([older, newer]), [older]);
    },
  );

  test(
    "keeps the build's own client name when every account is signed out",
    () async {
      final older = await signedOut('Pangea Chat-1');
      final own = await signedOut(PlatformInfos.clientName);
      final newer = await signedOut('Pangea Chat-3');
      addTearDown(older.dispose);
      addTearDown(own.dispose);
      addTearDown(newer.dispose);

      expect(ClientManager.signedOutClientsToForget([older, own, newer]), [
        older,
        newer,
      ]);
    },
  );
}
