import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A logged-in client whose world is only what the test puts in it.
///
/// Logging in against [FakeMatrixApi] starts a sync, and that sync's fixture
/// carries rooms of its own -- including a DM. Tests here build the rooms they
/// mean to test and then assert over `client.rooms`, so an ambient room nobody
/// asked for reads as a bug in the code under test: `hasFriendDM` was true on
/// a "brand new account" because the account was never brand new. Stop the
/// sync and start from empty, so the room list is the test's own doing.
///
/// [name] is the client NAME, which is the key every per-account service in
/// [MatrixState] is held under — the call services, the analytics services.
/// A test that wants two logged-in accounts has to give them different names
/// or they resolve to the same service and prove nothing. [deviceId] is
/// separate because the same account on two devices is a different scenario
/// from two accounts.
Future<Client> getTestClient({
  String name = 'testclient',
  String deviceId = 'GHTYAJCE',
}) async {
  final client = Client(
    name,
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  await client.login(
    LoginType.mLoginPassword,
    token: 'abcd',
    identifier: AuthenticationUserIdentifier(
      user: '@test:fakeServer.notExisting',
    ),
    deviceId: deviceId,
  );

  await client.abortSync();
  client.rooms.clear();

  return client;
}
