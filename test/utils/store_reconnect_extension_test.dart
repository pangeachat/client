// IndexedDB only exists in a browser, so the VM suite skips this file. Run it
// with `fvm flutter test --platform chrome test/utils/store_reconnect_extension_test.dart`.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/matrix_sdk_extensions/store_reconnect_extension.dart';

const _userId = '@learner:example.org';

Future<int> _insertClient(MatrixSdkDatabase database, String name) =>
    database.insertClient(
      name,
      'https://example.org',
      'token',
      null,
      null,
      _userId,
      null,
      null,
      null,
      null,
    );

void main() {
  test('an open store connection is left alone', () async {
    const name = 'store_reconnect_open';
    final database = await MatrixSdkDatabase.init(name);
    final client = Client(name, database: database);

    expect(await client.reconnectStoreIfClosed(), isFalse);

    await _insertClient(database, name);
    expect((await database.getClient(name))?['user_id'], _userId);
  });

  test('a login survives a store connection the browser dropped', () async {
    const name = 'store_reconnect_closed';
    final database = await MatrixSdkDatabase.init(name);
    final client = Client(name, database: database);

    // The state iOS Safari leaves behind: a handle that is closing for good.
    await database.close();
    await expectLater(
      _insertClient(database, name),
      throwsA(predicate((e) => e.toString().contains('connection is closing'))),
    );

    expect(await client.reconnectStoreIfClosed(), isTrue);

    await _insertClient(database, name);
    expect((await database.getClient(name))?['user_id'], _userId);
  });
}
