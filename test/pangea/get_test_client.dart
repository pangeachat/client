import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Client> getTestClient() async {
  final client = Client(
    'testclient',
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
    deviceId: 'GHTYAJCE',
  );

  return client;
}
